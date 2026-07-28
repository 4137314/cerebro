;;; org-export-latex.el --- batch entry point for parametric export -*- lexical-binding: t; -*-

;; Usage (inside the guix environment; see `make export`):
;;   emacs --batch -l bin/org-export-latex.el -- --profile=full path/to/note.org
;;   emacs --batch -l bin/org-export-latex.el -- --profile=single --target=NAME path/to/note.org
;;
;; Self-contained on purpose: `emacs --batch' does not load init.el, so
;; this adds exactly the lisp/ directory it needs to load-path instead of
;; assuming any particular startup sequence already ran.

(let* ((here (file-name-directory (or load-file-name buffer-file-name)))
       (lisp-dir (expand-file-name "../.emacs.d/lisp" here)))
  (add-to-list 'load-path lisp-dir))
(require 'cerebro-latex)

(let (profile file target
      ;; Emacs does not strip the "--" separator from
      ;; command-line-args-left on its own; do it ourselves.
      (args (delete "--" (copy-sequence command-line-args-left))))
  (dolist (arg args)
    (cond
     ((string-prefix-p "--profile=" arg)
      (setq profile (intern (substring arg (length "--profile=")))))
     ((string-prefix-p "--target=" arg)
      (setq target (substring arg (length "--target="))))
     (t (setq file arg))))
  (unless (and profile file)
    (message "usage: --profile=NAME [--target=NAME] FILE.org")
    (kill-emacs 1))
  (condition-case err
      (progn
        (cerebro-latex-export-to-pdf (expand-file-name file) profile target)
        (message "exported %s (profile: %s%s)" file profile
                 (if target (format ", target: %s" target) ""))
        (kill-emacs 0))
    (error
     (message "export failed: %s" (error-message-string err))
     (kill-emacs 1))))
