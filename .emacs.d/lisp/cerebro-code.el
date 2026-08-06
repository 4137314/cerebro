;;; cerebro-code.el --- writing code, and writing notes, with help -*- lexical-binding: t; -*-

;; This repo is a second brain *and* about three thousand lines of Elisp
;; and POSIX sh that keep it working -- edited in the same session as the
;; notes. What a modern editor gives you there is: mistakes shown while
;; you type, structure visible without counting spaces, boilerplate you
;; do not type, and formatting you do not think about.
;;
;; Each of those is here, and each is layered on a *built-in* Emacs
;; mechanism rather than on a framework:
;;
;;   diagnostics   flymake (built in) -- with the elisp byte-compiler,
;;                 shellcheck, and a backend for this repo's own note
;;                 linter, so a broken `#+NAME' is underlined in the note
;;                 as you write it instead of being caught by a git hook
;;   templates     tempel, through `completion-at-point' -- the same corfu
;;                 popup as everything else, no second UI. The templates
;;                 include this project's theorem/definition scaffolds
;;   formatting    apheleia on save, in a subprocess, so point and undo
;;                 survive
;;   structure     indentation bars in code (never in prose), and a
;;                 breadcrumb header line that answers "where am I in this
;;                 file?" -- in an Org note, the outline path
;;   parsing       tree-sitter where a grammar exists
;;
;; One honest note about tree-sitter: Emacs 30 has the engine built in
;; (`system-configuration-features' lists TREE_SITTER here), but a grammar
;; is per language and neither Org nor Emacs Lisp has one upstream. So it
;; applies to the shell scripts in bin/ and nothing else in this repo --
;; it is wired up, from data, and says so rather than pretending.

(require 'cerebro-org)   ;; cerebro-root, cerebro-note-files
(require 'cerebro-guix)  ;; cerebro-guix-soft-require
(require 'flymake)
(require 'seq)

(defgroup cerebro-code nil
  "Diagnostics, templates and structure while editing."
  :group 'cerebro)

;; -- Diagnostics --------------------------------------------------------

(defconst cerebro-code-flymake-modes
  '(emacs-lisp-mode-hook lisp-data-mode-hook sh-mode-hook bash-ts-mode-hook)
  "Mode hooks that turn on `flymake-mode'.
Elisp is checked by the byte-compiler Emacs already carries; shell by
shellcheck (guix.scm). Both report into the same place, so a warning
looks the same whichever half of the repo you are in.")

(dolist (hook cerebro-code-flymake-modes)
  (add-hook hook #'flymake-mode))

;; shellcheck has no built-in flymake backend, and the one on ELPA is one
;; function. It is cheaper to write it than to depend on it -- and this
;; way it reports through the same machinery as everything else.
(defun cerebro-code-shellcheck-backend (report-fn &rest _args)
  "A `flymake' backend running shellcheck over the current buffer."
  (unless (executable-find "shellcheck")
    (funcall report-fn nil)
    (cl-return-from cerebro-code-shellcheck-backend))
  (let* ((source (current-buffer))
         (buffer (generate-new-buffer " *cerebro-shellcheck*")))
    (make-process
     :name "cerebro-shellcheck" :noquery t :connection-type 'pipe
     :buffer buffer
     :command (list "shellcheck" "--format=gcc" "--shell=sh" "-")
     :sentinel
     (lambda (process _event)
       (when (memq (process-status process) '(exit signal))
         (unwind-protect
             (with-current-buffer buffer
               (goto-char (point-min))
               (let (diagnostics)
                 (while (re-search-forward
                         "^-:\\([0-9]+\\):\\([0-9]+\\): \\(error\\|warning\\|note\\): \\(.*\\)$"
                         nil t)
                   (let* ((line (string-to-number (match-string 1)))
                          (kind (match-string 3))
                          (text (match-string 4))
                          (region (flymake-diag-region source line)))
                     (push (flymake-make-diagnostic
                            source (car region) (cdr region)
                            (pcase kind ("error" :error) ("warning" :warning) (_ :note))
                            text)
                           diagnostics)))
                 (funcall report-fn (nreverse diagnostics))))
           (kill-buffer buffer))))
     :stderr nil)
    (save-restriction
      (widen)
      (process-send-region (get-process "cerebro-shellcheck") (point-min) (point-max))
      (process-send-eof (get-process "cerebro-shellcheck")))))

(add-hook 'sh-mode-hook
          (lambda () (add-hook 'flymake-diagnostic-functions
                               #'cerebro-code-shellcheck-backend nil t)))

;; -- The note linter, live ----------------------------------------------
;; The strongest diagnostic in this repo is not about code: it is
;; bin/notes-lint.el, which knows the conventions that fail silently (a
;; naked `$', a dangling `#+DEPENDS:', an undeclared tag). It runs in the
;; pre-push hook -- i.e. minutes or hours after you wrote the mistake.
;; Here it runs on the buffer, on save, and underlines the line.

(defun cerebro-code--lint-command (file)
  "The command that lints FILE, as an argument list."
  (list "emacs" "--batch" "-l" (expand-file-name "bin/notes-lint.el" cerebro-root)
        "--" file))

(defun cerebro-code-parse-lint (output source)
  "Turn notes-lint OUTPUT into flymake diagnostics for buffer SOURCE.
The linter prints `notes-lint: <severity>: <file>: <message>' -- and
lines with no location at all (a summary, a skipped check). Only the
located ones become diagnostics; the rest are not errors to point at.
Pure apart from SOURCE, so the parsing is unit-tested."
  (let ((diagnostics nil))
    (dolist (line (split-string output "\n" t))
      (when (string-match
             "\\`notes-lint: \\(?:\\(error\\|warning\\|info\\): \\)?\\([^ :]+[^:]*\\):\\([0-9]+\\)?:?[ \t]*\\(.*\\)\\'"
             line)
        (let* ((severity (or (match-string 1 line) "warning"))
               (number (match-string 3 line))
               (text (match-string 4 line))
               (region (flymake-diag-region source (if number (string-to-number number) 1))))
          (push (flymake-make-diagnostic
                 source (car region) (cdr region)
                 (pcase severity ("error" :error) ("info" :note) (_ :warning))
                 (concat "notes-lint: " text))
                diagnostics))))
    (nreverse diagnostics)))

(defun cerebro-code-notes-lint-backend (report-fn &rest _args)
  "A `flymake' backend running this repo's note linter on the buffer's file."
  (let ((file (buffer-file-name))
        (source (current-buffer)))
    (if (not (and file (executable-find "emacs")))
        (funcall report-fn nil)
      (let ((buffer (generate-new-buffer " *cerebro-notes-lint*")))
        (make-process
         :name "cerebro-notes-lint" :noquery t :connection-type 'pipe
         :buffer buffer
         :command (cerebro-code--lint-command file)
         :sentinel
         (lambda (process _event)
           (when (memq (process-status process) '(exit signal))
             (unwind-protect
                 (funcall report-fn
                          (cerebro-code-parse-lint
                           (with-current-buffer buffer (buffer-string)) source))
               (kill-buffer buffer)))))))))

(defcustom cerebro-code-lint-on-the-fly t
  "Whether Org notes are linted live (`flymake' + bin/notes-lint.el).
Each check starts a batch Emacs, so it runs on save rather than on every
keystroke -- and this is the switch for a machine where even that is too
much."
  :type 'boolean
  :group 'cerebro-code)

(defalias 'cerebro-code-interactive-buffer-p #'cerebro-interactive-note-buffer-p
  "See `cerebro-interactive-note-buffer-p' (cerebro-org.el), which three
modules share: this one, cerebro-appearance.el and cerebro-preview.el.")

(defun cerebro-code--setup-note-diagnostics ()
  "Turn on live note linting in this Org buffer."
  (when (and cerebro-code-lint-on-the-fly (cerebro-code-interactive-buffer-p))
    (add-hook 'flymake-diagnostic-functions #'cerebro-code-notes-lint-backend nil t)
    ;; On save only: the linter is a whole batch Emacs, not a parser we
    ;; can run per keystroke.
    (setq-local flymake-no-changes-timeout nil)
    (setq-local flymake-start-on-flymake-mode t)
    (flymake-mode 1)))

(add-hook 'org-mode-hook #'cerebro-code--setup-note-diagnostics)

;; -- Templates ----------------------------------------------------------
;; `tempel' expands through `completion-at-point', so the templates show
;; up in the same corfu popup as words and file names -- one completion
;; surface, not a second keybinding to remember. The templates live in
;; .emacs.d/templates (data, versioned), and the ones that matter here are
;; the note scaffolds: `thm', `def', `proof' expand to properly named
;; blocks with `#+NAME:' touching `#+begin_'.

(defconst cerebro-code-template-file
  (expand-file-name ".emacs.d/templates" cerebro-root)
  "Where cerebro's own templates live (see `tempel-path').")

(when (cerebro-guix-soft-require 'tempel)
  (setq tempel-path (list cerebro-code-template-file))
  (defun cerebro-code--tempel-capf ()
    (add-hook 'completion-at-point-functions #'tempel-complete -10 t))
  (add-hook 'prog-mode-hook #'cerebro-code--tempel-capf)
  (add-hook 'text-mode-hook #'cerebro-code--tempel-capf)
  (add-hook 'org-mode-hook  #'cerebro-code--tempel-capf)
  ;; A wider net for languages this repo does not write itself.
  (cerebro-guix-soft-require 'tempel-collection))

;; -- Formatting ---------------------------------------------------------
;; Two rules, and they are not the same rule:
;;   - code is *formatted* (apheleia, in a subprocess, on save);
;;   - prose is not. A note is a mathematical text; re-flowing it would
;;     rewrite the author's line breaks, and this repo's git history is
;;     the record of what was written.
;; Whitespace hygiene applies to both, because a trailing space is never
;; content.

(defun cerebro-code--delete-trailing-whitespace ()
  "Strip trailing whitespace, leaving the region around point alone.
`delete-trailing-whitespace' would otherwise eat the indentation you are
sitting in the middle of typing."
  (let ((column (current-column)))
    (delete-trailing-whitespace)
    (when (and (bolp) (> column 0)) (indent-to column))))

(dolist (hook '(prog-mode-hook conf-mode-hook))
  (add-hook hook (lambda ()
                   (add-hook 'before-save-hook
                             #'cerebro-code--delete-trailing-whitespace nil t))))

(when (cerebro-guix-soft-require 'apheleia)
  ;; Elisp has no external formatter worth running; Emacs' own indenter is
  ;; the reference implementation, so use it as apheleia's for Elisp.
  (when (boundp 'apheleia-mode-alist)
    (setf (alist-get 'emacs-lisp-mode apheleia-mode-alist) 'lisp-indent)
    (setf (alist-get 'lisp-data-mode apheleia-mode-alist) 'lisp-indent))
  (when (boundp 'apheleia-formatters)
    (setf (alist-get 'lisp-indent apheleia-formatters)
          '(apheleia-indent-lisp-buffer)))
  (apheleia-global-mode 1))

;; -- Structure you can see ----------------------------------------------

(when (cerebro-guix-soft-require 'indent-bars)
  (setq indent-bars-treesit-support (and (fboundp 'treesit-available-p)
                                         (treesit-available-p))
        indent-bars-width-frac 0.15   ; a hairline, not a ladder
        indent-bars-pad-frac 0.2
        indent-bars-color '(highlight :face-bg t :blend 0.25)
        indent-bars-highlight-current-depth '(:blend 0.6))
  ;; Code only. In a note, indentation is Org's outline machinery
  ;; (`org-indent-mode'), and a grid of bars through prose is noise.
  (add-hook 'prog-mode-hook #'indent-bars-mode))

;; -- Breadcrumbs --------------------------------------------------------
;; "Where am I in this file?" -- for a note that is the outline path of
;; the heading point is under, and for code the enclosing definition.
;; Emacs answers both already (`org-get-outline-path', `which-function');
;; what was missing is somewhere to *show* it, which is what a header line
;; is for. Hand-rolled because it is fifteen lines and one pure function.

(defcustom cerebro-code-breadcrumb-separator " › "
  "Separator between breadcrumb components."
  :type 'string
  :group 'cerebro-code)

(defface cerebro-code-breadcrumb
  '((t :inherit (shadow) :height 0.95))
  "Face for the breadcrumb header line.")

(defun cerebro-code-breadcrumb-string (components)
  "Join COMPONENTS into a breadcrumb, dropping empty ones. Pure."
  (mapconcat #'identity
             (seq-remove #'string-empty-p (delq nil components))
             cerebro-code-breadcrumb-separator))

(defun cerebro-code-breadcrumb ()
  "The context of point: outline path in Org, enclosing function in code."
  (cerebro-code-breadcrumb-string
   (cond
    ((derived-mode-p 'org-mode)
     (ignore-errors (org-get-outline-path t)))
    (t (list (and (fboundp 'which-function) (which-function)))))))

(defun cerebro-code--breadcrumb-line ()
  "The header-line value, or nil when there is no context to show."
  (let ((crumb (ignore-errors (cerebro-code-breadcrumb))))
    (when (and crumb (not (string-empty-p crumb)))
      (concat " " (propertize crumb 'face 'cerebro-code-breadcrumb)))))

(define-minor-mode cerebro-code-breadcrumb-mode
  "Show the path to point in the header line."
  :init-value nil
  :group 'cerebro-code
  (if cerebro-code-breadcrumb-mode
      (progn
        (when (and (not (derived-mode-p 'org-mode)) (fboundp 'which-function-mode))
          (which-function-mode 1))
        (setq header-line-format '(:eval (cerebro-code--breadcrumb-line))))
    (setq header-line-format nil)))

(defcustom cerebro-code-breadcrumb-modes '(org-mode-hook prog-mode-hook)
  "Mode hooks that get the breadcrumb header line."
  :type '(repeat symbol)
  :group 'cerebro-code)

(defun cerebro-code--maybe-breadcrumb ()
  "Turn the breadcrumb on, in buffers a person is actually looking at."
  (when (or (not (derived-mode-p 'org-mode)) (cerebro-code-interactive-buffer-p))
    (cerebro-code-breadcrumb-mode 1)))

(dolist (hook cerebro-code-breadcrumb-modes)
  (add-hook hook #'cerebro-code--maybe-breadcrumb))

;; -- Tree-sitter --------------------------------------------------------
;; The engine is built in; a grammar is a shared library per language,
;; shipped by guix.scm and found through `treesit-extra-load-path' (a Guix
;; profile puts them in lib/, not in ~/.emacs.d/tree-sitter).

(defconst cerebro-code-treesit-modes
  '((sh-mode . bash-ts-mode))
  "Major mode -> its tree-sitter counterpart, for grammars we ship.
Org and Emacs Lisp are absent because no upstream grammar exists for
either -- most of this repo is therefore parsed the classic way, and
that is a fact about tree-sitter, not a gap in this config.")

(defun cerebro-code-treesit-grammar-directories (&optional profile)
  "Directories to search for grammars, given a Guix PROFILE.
Nil outside the environment: there are no grammars to find there, and a
bogus entry would make `treesit-language-available-p' scan a path that
does not exist on every check."
  (when-let* ((profile (or profile (getenv "GUIX_ENVIRONMENT"))))
    ;; Guix installs grammars as lib/tree-sitter/libtree-sitter-<lang>.so
    ;; (verified in the profile); Emacs' own default is
    ;; ~/.emacs.d/tree-sitter, which nothing here ever writes to.
    (list (expand-file-name "lib/tree-sitter" profile))))

(defun cerebro-code-setup-treesit ()
  "Point Emacs at the grammars this environment provides, and use them."
  (when (and (fboundp 'treesit-available-p) (treesit-available-p))
    (setq treesit-extra-load-path
          (append (cerebro-code-treesit-grammar-directories)
                  (bound-and-true-p treesit-extra-load-path)))
    (dolist (cell cerebro-code-treesit-modes)
      (let ((language (intern (replace-regexp-in-string
                               "-ts-mode\\'" "" (symbol-name (cdr cell))))))
        (when (treesit-language-available-p language)
          (add-to-list 'major-mode-remap-alist cell))))))

(cerebro-code-setup-treesit)

;; -- Small comforts that make an editor feel modern ---------------------
(electric-pair-mode 1)                  ; brackets and quotes close themselves
(setq electric-pair-inhibit-predicate 'electric-pair-conservative-inhibit)
(delete-selection-mode 1)               ; typing replaces the selection
(global-subword-mode 1)                 ; camelCase moves word by word
(setq-default indent-tabs-mode nil)     ; spaces, like everything in this repo
(setq require-final-newline t)
(setq sentence-end-double-space nil)    ; prose here is single-spaced

(provide 'cerebro-code)
