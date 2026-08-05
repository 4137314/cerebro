;;; cerebro-today.el --- batch agenda to stdout -*- lexical-binding: t; -*-

;; Usage: emacs --batch -l bin/cerebro-today.el -- [m|i]
;; Prints an agenda custom command (default "m", the morning review) to
;; standard output -- the terminal face of `C-c a m'. Pure Org (no
;; Org-roam, no Guix), so it runs on the plain `emacs' on PATH; the
;; `cerebro' CLI dispatches `cerebro today' / `cerebro agenda' here.

(let* ((here (file-name-directory (or load-file-name buffer-file-name)))
       (lisp-dir (expand-file-name "../.emacs.d/lisp" here)))
  (add-to-list 'load-path lisp-dir))
(require 'cerebro-org)
(require 'cerebro-agenda)

;; Batch agenda wants unpropertised, non-interactive output.
(setq org-agenda-remove-tags nil)

(let* ((args (delete "--" (copy-sequence command-line-args-left)))
       (key (or (car args) "m")))
  ;; org-batch-agenda is a macro keyed by a literal string, so dispatch on
  ;; the two commands cerebro-agenda.el defines rather than passing a var.
  (pcase key
    ("i" (org-batch-agenda "i"))
    (_   (org-batch-agenda "m"))))
