;;; cerebro-help.el --- the manual, the conventions, and the settings -*- lexical-binding: t; -*-

;; This repository documents itself at length -- README.org is the manual,
;; CLAUDE.md the operational brief, notes/README.org the note-authoring
;; conventions -- and none of it was reachable from inside the editor.
;; The answer to "how do I write a #+DEPENDS: again?" was to leave Emacs,
;; find the file, and search it. The answer to "what does
;; `cerebro-preview-relative-size' currently *say*?" was worse: you had to
;; already know the variable existed.
;;
;; So this is the help surface, under `C-c H':
;;
;;   C-c H h   the manual              (README.org)
;;   C-c H c   the note conventions    (notes/README.org)
;;   C-c H b   the operational brief   (CLAUDE.md)
;;   C-c H k   every cerebro key, grouped by prefix
;;   C-c H v   every cerebro setting, with its value -- RET describes one
;;   C-c H m   the module map: what each file is for
;;   C-c H ?   the command palette (same as `C-c ?')
;;
;; Two of those are *derived* rather than written, and that is the point.
;; A key list maintained by hand goes stale the first time a binding
;; moves; this one is read from the keymap. A settings list maintained by
;; hand omits the setting you added last week; this one is
;; `apropos'-generated. Neither can be wrong about the thing it describes.

(require 'cerebro-base) ;; cerebro-root, cerebro-report
(require 'seq)

(defgroup cerebro-help nil
  "Reaching the documentation from inside the editor."
  :group 'cerebro)

;; -- The written documents ----------------------------------------------
;; Data: a key, a path, and what it is. Adding a document is a row.

(defconst cerebro-help-documents
  '((?h "README.org"         "the manual -- principles, workflow, every subsystem")
    (?c "notes/README.org"   "the note conventions, the tag taxonomy, a compilable exemplar")
    (?b "CLAUDE.md"          "the operational brief -- invariants, how to verify a change")
    (?i "issues/issues.org"  "the committed backlog")
    (?g "guix.scm"           "the pinned environment: every package, one file"))
  "Rows of (KEY RELATIVE-PATH DESCRIPTION) for `cerebro-help-document'.")

(defun cerebro-help--path (relative)
  "RELATIVE resolved against the repository root."
  (expand-file-name relative cerebro-root))

;;;###autoload
(defun cerebro-help-document (path)
  "Open one of this repository's own documents (`C-c H d').
Completion is over `cerebro-help-documents', so the manual is as easy to
reach as a note -- which is the only way documentation gets read."
  (interactive
   (let* ((rows (mapcar (lambda (row)
                          (cons (format "%-18s %s" (nth 1 row) (nth 2 row))
                                (nth 1 row)))
                        cerebro-help-documents))
          (choice (completing-read "Document: " (mapcar #'car rows) nil t)))
     (list (cdr (assoc choice rows)))))
  (let ((file (cerebro-help--path path)))
    (if (file-readable-p file)
        (find-file file)
      (user-error "cerebro-help: %s is not in this checkout" path))))

(defmacro cerebro-help--define-opener (name relative doc)
  "Define an interactive command NAME opening RELATIVE, documented DOC."
  `(defun ,name ()
     ,doc
     (interactive)
     (cerebro-help-document ,relative)))

(cerebro-help--define-opener cerebro-help-manual "README.org"
  "Open README.org, the human-facing manual (`C-c H h').")
(cerebro-help--define-opener cerebro-help-conventions "notes/README.org"
  "Open the note-authoring conventions and the tag taxonomy (`C-c H c').")
(cerebro-help--define-opener cerebro-help-brief "CLAUDE.md"
  "Open CLAUDE.md, the operational brief and the invariants (`C-c H b').")

;; -- The keys, read from the keymap -------------------------------------

(defconst cerebro-help-prefixes
  '(("C-c m" . "make a note")
    ("C-c u" . "look, feel, reading mode")
    ("C-c r" . "results: the graph, and moving through it")
    ("C-c e" . "export & PDF")
    ("C-c n" . "org-roam notes")
    ("C-c q" . "graph queries")
    ("C-c v" . "org-ql views")
    ("C-c b" . "bibliography")
    ("C-c d" . "the cerebro CLI")
    ("C-c G" . "the guix environment")
    ("C-c B" . "backups")
    ("C-c H" . "documentation & settings")
    ("C-c w" . "window layout"))
  "Prefix -> what that family of keys is for.
The same table which-key shows (cerebro-keys.el reads it), kept here
because a printed reference and a popup should not disagree about what a
prefix means.")

(defun cerebro-help-key-rows (&optional prefixes)
  "Every binding under PREFIXES, as (PREFIX KEY COMMAND) rows.
Read from the live keymap with `where-is-internal', so a key that moved
is reported where it moved to. Pure with respect to the keymap: it takes
no arguments beyond the prefix table and touches no buffer."
  (let (rows)
    (dolist (cell (or prefixes cerebro-help-prefixes))
      (let ((prefix (car cell)))
        (dolist (command (sort (apropos-internal "\\`\\(cerebro\\|org\\)-" #'commandp)
                               #'string<))
          (dolist (key (where-is-internal command))
            (let ((described (key-description key)))
              (when (and (string-prefix-p (concat prefix " ") described)
                         ;; One row per key, not one per alias.
                         (not (assoc described rows)))
                (push (list prefix described command) rows)))))))
    (nreverse rows)))

(defun cerebro-help--key-lines ()
  "The key reference as display lines, grouped by prefix."
  (let ((rows (cerebro-help-key-rows))
        lines)
    (dolist (cell cerebro-help-prefixes)
      (let* ((prefix (car cell))
             (mine (seq-filter (lambda (r) (equal (car r) prefix)) rows)))
        (when mine
          (push (format "%s  --  %s" prefix (cdr cell)) lines)
          (dolist (row mine)
            (push (format "    %-14s %s" (nth 1 row) (nth 2 row)) lines))
          (push "" lines))))
    (nreverse lines)))

;;;###autoload
(defun cerebro-help-keys ()
  "Every cerebro key, grouped by prefix (`C-c H k').
Derived from the keymap, never from a list: a binding that moved shows
up where it moved to, which a hand-written reference cannot promise."
  (interactive)
  (cerebro-report "cerebro keys" (cerebro-help--key-lines) #'identity
                  "*cerebro-help*"))

;; -- The settings, with their values ------------------------------------

(defun cerebro-help-settings ()
  "Every cerebro user option, as symbols, sorted.

`define-minor-mode' generates a `...-mode-hook' defcustom for each mode,
which is a customizable variable and is not a *setting*: nobody opens a
configuration browser to look at `cerebro-focus-mode-hook'. Dropping
them is the difference between a list you read and a list you scroll
past."
  (sort (seq-remove (lambda (symbol) (string-suffix-p "-hook" (symbol-name symbol)))
                    (apropos-internal "\\`cerebro-" #'custom-variable-p))
        #'string<))

(defun cerebro-help-setting-line (symbol)
  "SYMBOL as one line: name, current value, first line of its docstring."
  (let ((doc (or (car (split-string (or (documentation-property
                                         symbol 'variable-documentation)
                                        "")
                                    "\n"))
                 "")))
    (format "%-42s %-22s %s"
            (symbol-name symbol)
            (truncate-string-to-width
             (prin1-to-string (symbol-value symbol)) 22 nil nil "…")
            doc)))

;;;###autoload
(defun cerebro-help-configuration ()
  "Every cerebro setting and what it is currently set to (`C-c H v').

`apropos'-generated, so a defcustom added later appears here without
being registered anywhere -- the only kind of settings list that stays
true. Picking one opens `describe-variable' on it, which is where the
full documentation and the customize link already live: this is a way
in, not a second copy."
  (interactive)
  (let* ((settings (cerebro-help-settings))
         (rows (mapcar (lambda (s) (cons (cerebro-help-setting-line s) s)) settings))
         (choice (completing-read
                  (format "cerebro setting (%d): " (length settings))
                  (mapcar #'car rows) nil t)))
    (describe-variable (cdr (assoc choice rows)))))

;; -- The module map -----------------------------------------------------

(defun cerebro-help--module-files ()
  "Every cerebro-*.el under .emacs.d/lisp/, sorted."
  (let ((dir (expand-file-name ".emacs.d/lisp" cerebro-root)))
    (when (file-directory-p dir)
      (sort (directory-files dir t "\\`cerebro-.*\\.el\\'") #'string<))))

(defun cerebro-help-module-line (file)
  "FILE as `name -- summary', taking the summary from its own first line.
Every module in this repository opens with the standard Elisp header
line (`;;; cerebro-x.el --- what it is'), so the map is read from the
files instead of being a list that drifts from them."
  (let ((summary
         (with-temp-buffer
           (insert-file-contents file nil 0 400)
           (goto-char (point-min))
           (if (re-search-forward "^;;;[ \t]*[^ \t]+[ \t]*---[ \t]*\\(.*?\\)[ \t]*\\(-\\*-.*\\)?$" nil t)
               (string-trim (match-string 1))
             ""))))
    (format "%-26s %s" (file-name-nondirectory file) summary)))

;;;###autoload
(defun cerebro-help-modules ()
  "What each cerebro module is for (`C-c H m').
Read from the modules' own header lines, so this cannot describe a file
as something it stopped being."
  (interactive)
  (cerebro-report
   (format "cerebro modules (%d)" (length (cerebro-help--module-files)))
   (mapcar #'cerebro-help-module-line (cerebro-help--module-files))
   #'identity
   "*cerebro-help*"))

(provide 'cerebro-help)
