;;; cerebro-env.el --- print the environment report in batch -*- lexical-binding: t; -*-

;; Usage: emacs --batch -l bin/cerebro-env.el
;; (the `cerebro env' subcommand, which runs this through bin/guix-run so
;; that what it reports is the environment the *editor* gets).
;;
;; The shell-side twin of `M-x cerebro-guix-status': same lines, same
;; source (`cerebro-guix-status-lines'), no second implementation. It
;; answers the question `cerebro doctor' cannot -- doctor checks which
;; tools exist on the host, this checks which Emacs packages the pinned
;; profile actually hands to the config, and at which channel commit.

(let* ((here (file-name-directory (or load-file-name buffer-file-name)))
       (lisp-dir (expand-file-name "../.emacs.d/lisp" here)))
  (add-to-list 'load-path lisp-dir))

;; Load the same soft modules init.el does, so the report reflects what a
;; real session would have: `cerebro-guix-status-lines' reads `featurep',
;; and nothing would be loaded if we only required cerebro-guix itself.
(require 'cerebro-guix)
(require 'cerebro-theme)
(require 'cerebro-appearance)
(require 'cerebro-preview)
(require 'cerebro-focus)
(require 'cerebro-code)
(require 'cerebro-pdf)
(require 'cerebro-complete)
(require 'cerebro-ui)
(require 'cerebro-vc)
(require 'cerebro-dashboard)
(dolist (module '(cerebro-roam cerebro-ql cerebro-drill))
  (require module nil t))

(dolist (line (cerebro-guix-status-lines))
  (princ line)
  (terpri))
