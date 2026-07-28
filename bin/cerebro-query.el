;;; cerebro-query.el --- batch entry point for the graph queries -*- lexical-binding: t; -*-

;; Usage: emacs --batch -l bin/cerebro-query.el -- orphans|hubs|stale-hubs|co-citation|by-tag [args...]
;; Prints the same buffer `cerebro-query-*' would show interactively.

(let* ((here (file-name-directory (or load-file-name buffer-file-name)))
       (lisp-dir (expand-file-name "../.emacs.d/lisp" here)))
  (add-to-list 'load-path lisp-dir))
(require 'cerebro-query)

;; Interactively, org-roam-db-autosync-mode (cerebro-roam.el) keeps the
;; SQLite cache current; from the CLI there is no running Emacs doing
;; that, so a plain `make query' could otherwise report structure from a
;; stale database (notes edited in any editor since the last autosync).
;; Rebuild it first so the "pattern finding" actually reflects the files
;; on disk. Best-effort: a sync failure must not stop the query.
(condition-case err
    (org-roam-db-sync)
  (error (message "cerebro-query: org-roam-db-sync failed (%s), querying existing DB"
                  (error-message-string err))))

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
          ("by-msc" (cerebro-query-by-msc (or (car rest) (error "by-msc needs an MSC code or class argument"))))
          (_ (error "unknown query `%s' (know: orphans hubs stale-hubs co-citation by-tag by-msc)" cmd)))
        (princ (with-current-buffer "*cerebro-query*" (buffer-string)))
        (kill-emacs 0))
    (error
     (message "cerebro-query failed: %s" (error-message-string err))
     (kill-emacs 1))))
