;;; cerebro-results.el --- batch entry point for the results layer -*- lexical-binding: t; -*-

;; Usage: emacs --batch -l bin/cerebro-results.el -- [index|check|open|deps|dependents] [NAME]
;; Prints, to stdout, the same *cerebro-results* report the interactive
;; `cerebro-results-*' commands (.emacs.d/lisp/cerebro-results.el) build.
;; No org-roam-db-sync step (unlike bin/cerebro-query.el): the results
;; layer reads the .org files directly, so there is no cache to refresh.

(let* ((here (file-name-directory (or load-file-name buffer-file-name)))
       (lisp-dir (expand-file-name "../.emacs.d/lisp" here)))
  (add-to-list 'load-path lisp-dir))
(require 'cerebro-results)

(let* ((args (delete "--" (copy-sequence command-line-args-left)))
       (cmd (or (car args) "index"))
       (rest (cdr args)))
  (condition-case err
      (progn
        (pcase cmd
          ("index" (cerebro-results-index))
          ("check" (cerebro-results-check))
          ;; What still owes a proof: `open' plus the `assumed' ones,
          ;; which are the debts you forget you took on.
          ((or "open" "unproved") (cerebro-results-open))
          ((or "deps" "dependencies")
           (cerebro-results-dependencies
            (or (car rest) (error "deps needs a result NAME (make results CMD=deps NAME=...)"))))
          ((or "dependents" "impact")
           (cerebro-results-dependents
            (or (car rest) (error "dependents needs a result NAME (make results CMD=dependents NAME=...)"))))
          (_ (error "unknown results command `%s' (know: index check open deps dependents)" cmd)))
        (princ (with-current-buffer "*cerebro-results*" (buffer-string)))
        (kill-emacs 0))
    (error
     (message "cerebro-results failed: %s" (error-message-string err))
     (kill-emacs 1))))
