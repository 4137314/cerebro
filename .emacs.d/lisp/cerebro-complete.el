;;; cerebro-complete.el --- minibuffer completion and live search -*- lexical-binding: t; -*-

;; A lifelong note database is only as good as your ability to *reach*
;; something in it. Emacs' default completion (a two-column *Completions*
;; window you have to look away to read) is the weakest link once there
;; are hundreds of notes, named results and issues: every `C-c n f',
;; `C-c d f', refile target, tag prompt and `M-x' goes through it.
;;
;; Four small, single-purpose packages from guix.scm fix that, and they
;; are the right kind of dependency for this project: each one does one
;; thing to the *built-in* completion machinery instead of replacing it
;; (no framework, no state of its own, no network, nothing to relearn if
;; one of them is ever dropped -- completion just goes back to vanilla):
;;
;;   vertico    -- show candidates vertically in the minibuffer
;;   orderless  -- match space-separated fragments in any order
;;                 ("heine borel" finds "Borel--Heine covering theorem")
;;   marginalia -- annotate candidates (file sizes, docstrings, ...)
;;   consult    -- live-previewing search/jump commands over buffers,
;;                 lines, outlines and grep
;;
;; Everything is loaded through `cerebro-guix-soft-require', so outside
;; the pinned environment this module still loads and simply leaves the
;; stock completion in place (invariant 4).
;;
;; Note: the consult commands below *replace* standard keys (C-x b, M-y,
;; M-g g). Those bindings therefore live here, where availability is
;; known, and NOT in cerebro-keys.el -- binding C-x b to a void command
;; would take away `switch-to-buffer' in the degraded, outside-guix mode.

(require 'cerebro-org)  ;; org-directory
(require 'cerebro-guix)  ;; cerebro-guix-soft-require
(require 'cerebro-theme) ;; cerebro-theme-nerd-icons-p

;; -- Core behaviour, useful with or without the packages ---------------
(setq enable-recursive-minibuffers t) ; a search inside a search
(minibuffer-depth-indicate-mode 1)    ; ...shown as [2] so it can't confuse
(setq completion-ignore-case t
      read-file-name-completion-ignore-case t
      read-buffer-completion-ignore-case t)
;; Emacs 30 still offers the old *Completions* window on TAB; keep it
;; tidy for the case where vertico is absent.
(setq completions-detailed t)

;; -- orderless: match fragments in any order ---------------------------
;; `basic' stays in the list as the fallback that makes TAB-completion of
;; a unique prefix still work; files keep the classic styles, since
;; path completion is prefix-shaped by nature and orderless makes
;; `~/n/c/a' style expansion worse, not better.
(if (cerebro-guix-soft-require 'orderless)
    (setq completion-styles '(orderless basic)
          completion-category-defaults nil
          completion-category-overrides '((file (styles basic partial-completion))))
  ;; Degraded but still better than the default: `flex' is built into
  ;; Emacs and gives fuzzy matching without any package at all.
  (setq completion-styles '(basic partial-completion flex)))

;; -- vertico: the vertical minibuffer ----------------------------------
(when (cerebro-guix-soft-require 'vertico)
  (setq vertico-count 12   ; tall enough for a real candidate list, short
                           ; enough not to swallow the buffer below
        vertico-cycle t)
  (vertico-mode 1))

;; -- marginalia: what a candidate actually is --------------------------
(when (cerebro-guix-soft-require 'marginalia)
  (marginalia-mode 1))

;; An icon per candidate kind (a file, a buffer, a command): the fastest
;; way to tell what a list is made of before reading a word of it. Only
;; when a Nerd Font is installed -- otherwise every line starts with a
;; box (see `cerebro-theme-nerd-icons-p').
(when (cerebro-guix-soft-require 'nerd-icons-completion)
  ;; Loaded either way (so `cerebro env' can report it), *enabled* only
  ;; when a font can actually draw the glyphs -- in batch, and on a
  ;; machine with no Nerd Font, icons would be a column of boxes.
  (when (cerebro-theme-nerd-icons-p)
    (nerd-icons-completion-mode 1)
    (add-hook 'marginalia-mode-hook #'nerd-icons-completion-marginalia-setup)))

;; -- consult: live search over the second brain ------------------------
;; Bound on the standard consult keys (M-s = search, M-g = goto) rather
;; than on cerebro's own `C-c' prefixes: these are general editing
;; commands, and using the conventional keys means the muscle memory
;; transfers to any other Emacs.
(when (cerebro-guix-soft-require 'consult)
  (setq consult-narrow-key "<") ; narrow a candidate list by source
  ;; Live preview stays on for the in-buffer commands (line, outline,
  ;; grep hits: cheap, and it is what makes them worth using), but is put
  ;; behind M-. for the ones that would *open files* -- arrowing through
  ;; a buffer/file list would otherwise visit and org-fontify whole notes
  ;; one keypress at a time.
  (consult-customize consult-buffer consult-recent-file :preview-key "M-.")

  (global-set-key (kbd "C-x b")   #'consult-buffer)
  (global-set-key (kbd "C-x 4 b") #'consult-buffer-other-window)
  (global-set-key (kbd "M-y")     #'consult-yank-pop)
  (global-set-key (kbd "M-g g")   #'consult-goto-line)
  (global-set-key (kbd "M-g M-g") #'consult-goto-line)
  (global-set-key (kbd "M-g i")   #'consult-imenu)
  (global-set-key (kbd "M-g o")   #'consult-outline)   ; jump by heading
  (global-set-key (kbd "M-s l")   #'consult-line)
  (global-set-key (kbd "M-s f")   #'consult-find)
  ;; `M-s g' stays grep over the *repository* (code included); `C-c s' is
  ;; the notes. Both go through ripgrep when it is there.
  (global-set-key (kbd "M-s g")   (if (executable-find "rg")
                                      #'consult-ripgrep #'consult-grep))
  (global-set-key (kbd "M-s r")   #'consult-ripgrep)

  ;; What makes the search feel fuzzy: consult splits the input at the
  ;; first space, sends the head to ripgrep and filters the rest with the
  ;; completion style -- which is `orderless' here, so the remaining
  ;; words match in any order.
  (setq consult-async-min-input 2
        consult-async-refresh-delay 0.15
        consult-async-input-debounce 0.1
        consult-async-input-throttle 0.2))

;; -- corfu: the same idea, inside the buffer ---------------------------
;; Completion in the *buffer* (`completion-at-point') is the other half of
;; the story: an org-roam link, a `#+' keyword, a LaTeX macro, an Elisp
;; symbol. Emacs' default for that is a window that opens behind your
;; text; corfu shows the same candidates in a small popup at point, from
;; the same capf machinery -- no separate completion engine, and it reads
;; the orderless style configured above.
;;
;; Corfu draws its popup in a child frame, which a terminal frame cannot
;; do. That matters here because the normal launch path is a *daemon*
;; (bin/cerebro), where at startup there is no graphical frame yet and
;; `display-graphic-p' is nil -- so enabling it must be deferred to the
;; first real frame rather than decided now.
(when (cerebro-guix-soft-require 'corfu)
  (setq corfu-auto t            ; suggest as you type...
        corfu-auto-delay 0.25   ; ...but not while you are still typing fast
        corfu-auto-prefix 2
        corfu-cycle t
        corfu-quit-no-match 'separator
        corfu-preselect 'prompt ; never replace what you typed without asking
        corfu-on-exact-match nil)

  (defun cerebro-complete--enable-corfu (&optional frame)
    "Turn on `global-corfu-mode' once a graphical frame exists."
    (when (display-graphic-p frame)
      (global-corfu-mode 1)
      (remove-hook 'after-make-frame-functions #'cerebro-complete--enable-corfu)))

  (if (display-graphic-p)
      (cerebro-complete--enable-corfu)
    (add-hook 'after-make-frame-functions #'cerebro-complete--enable-corfu))

  ;; The same icons in the in-buffer popup: a template, a word and a file
  ;; path are three different things, and the margin says which.
  (when (and (cerebro-guix-soft-require 'nerd-icons-corfu)
             (cerebro-theme-nerd-icons-p))
    (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter)))

;; TAB completes once the line is already indented. Org is unaffected (it
;; binds TAB to `org-cycle'), so this only changes code buffers -- where
;; it turns one key into indent-or-complete, the behaviour every other
;; editor has.
(setq tab-always-indent 'complete)

;; -- cape: things worth completing in a note ---------------------------
;; capfs are per-buffer data, so this is a table of mode hook -> the
;; functions to add, not a pile of hooks (invariant 3). `cape-dabbrev' is
;; the one that earns its place in prose: a note repeats long names
;; ("quasi-isomorphism", "Lebesgue-measurable") that no dictionary has,
;; and completing them from the text you already wrote is both faster and
;; a spelling check.
(defconst cerebro-complete-capfs
  '((org-mode        . (cape-dabbrev cape-file))
    (text-mode       . (cape-dabbrev cape-file))
    (emacs-lisp-mode . (cape-elisp-symbol cape-file))
    (prog-mode       . (cape-file)))
  "Major mode -> completion-at-point functions to add in it.
Matched with `derived-mode-p', so a mode inherits its parent's entries
(org-mode gets the text-mode ones too) -- and `add-hook' keeps the list
free of duplicates on its own.")

(defun cerebro-complete-setup-capfs ()
  "Add the capfs `cerebro-complete-capfs' configures for this buffer.
One named function on one hook rather than a lambda per mode: a hook you
can read in `C-h v', remove, and edebug is worth more than three lines
saved -- and re-loading this module cannot then install it twice."
  (dolist (cell cerebro-complete-capfs)
    (when (derived-mode-p (car cell))
      (dolist (fn (cdr cell))
        (when (fboundp fn)
          ;; Depth 90: after the mode's own capf (org-roam links, Elisp
          ;; symbols), which is the one that knows the buffer.
          (add-hook 'completion-at-point-functions fn 90 t))))))

(when (cerebro-guix-soft-require 'cape)
  (add-hook 'after-change-major-mode-hook #'cerebro-complete-setup-capfs)

  ;; Only complete from the notes themselves: dabbrev scanning a magit
  ;; buffer or a compilation log offers noise as if it were vocabulary.
  (setq cape-dabbrev-min-length 4
        cape-dabbrev-check-other-buffers #'cape--buffers-major-mode))

;;;###autoload
(defun cerebro-search-notes ()
  "Search the text of every note, live and fuzzily (`C-c s').

The one command for \"where did I write that\", and deliberately
different from the two structured searches next to it -- `C-c n f'
(org-roam, by title) and `C-c v s' (org-ql, by Org metadata).

Three levels, best first, because the key must always do *something*:
ripgrep through consult (fast enough that each keystroke re-searches the
whole archive), consult over GNU grep, and finally the built-in `rgrep'
with no package at all.

Fuzzy in the sense that matters here: type `borel heine cover' and the
words are matched in any order, anywhere in the line -- consult sends the
first token to the search program and `orderless' filters the rest, so
you never have to remember how you phrased something."
  (interactive)
  (cond
   ((and (fboundp 'consult-ripgrep) (executable-find "rg"))
    (consult-ripgrep org-directory))
   ((fboundp 'consult-grep) (consult-grep org-directory))
   (t (let ((default-directory org-directory))
        (call-interactively #'rgrep)))))

(provide 'cerebro-complete)
