;;; cerebro-query.el --- batch entry point for the graph queries -*- lexical-binding: t; -*-

;; Usage: emacs --batch -l bin/cerebro-query.el -- orphans|hubs|stale-hubs|co-citation|by-tag [args...]
;; Prints the same buffer `cerebro-query-*' would show interactively.

(let* ((here (file-name-directory (or load-file-name buffer-file-name)))
       (lisp-dir (expand-file-name "../.emacs.d/lisp" here)))
  (add-to-list 'load-path lisp-dir))
(require 'cerebro-query)

(let* ((args (delete "--" (copy-sequence command-line-args-left)))
       (cmd (car args))
       (rest (cdr args)))
  (condition-case err
      (progn
        (pcase cmd
          ("orphans" (cerebro-query-orphans))
          ("hubs" (cerebro-query-hubs))
          ("stale-hubs"
           (cerebro-query-stale-hubs
            (and (nth 0 rest) (string-to-number (nth 0 rest)))
            (and (nth 1 rest) (string-to-number (nth 1 rest)))))
          ("co-citation"
           (cerebro-query-co-citation (and (car rest) (string-to-number (car rest)))))
          ("by-tag" (cerebro-query-by-tag (or (car rest) (error "by-tag needs a TAG argument"))))
          (_ (error "unknown query `%s' (know: orphans hubs stale-hubs co-citation by-tag)" cmd)))
        (princ (with-current-buffer "*cerebro-query*" (buffer-string)))
        (kill-emacs 0))
    (error
     (message "cerebro-query failed: %s" (error-message-string err))
     (kill-emacs 1))))
