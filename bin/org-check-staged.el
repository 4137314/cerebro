;;; org-check-staged.el --- sanity-check that staged .org files parse -*- lexical-binding: t; -*-

;; Usage: emacs --batch -l bin/org-check-staged.el -- file1.org file2.org
;; Exits non-zero if any file fails to parse as Org. Deliberately a low
;; bar (catches corruption / broken structure, not style) rather than a
;; flaky attempt at full org-lint semantics from a script that can't be
;; build-tested against a real org-roam-equipped Emacs; run `M-x org-lint'
;; by hand for the deeper checks.

(require 'org)
(require 'org-element)

(let (failures
      ;; Emacs does not strip the "--" separator from
      ;; command-line-args-left on its own; do it ourselves.
      (files (delete "--" (copy-sequence command-line-args-left))))
  (dolist (file files)
    (condition-case err
        (with-temp-buffer
          (insert-file-contents file)
          (org-mode)
          (org-element-parse-buffer))
      (error (push (cons file err) failures))))
  (if failures
      (progn
        (dolist (f (reverse failures))
          (message "FAIL %s: %s" (car f) (error-message-string (cdr f))))
        (kill-emacs 1))
    (kill-emacs 0)))
