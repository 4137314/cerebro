;;; cerebro-backup.el --- run backups in batch -*- lexical-binding: t; -*-

;; Usage: emacs --batch -l bin/cerebro-backup.el -- [run|status|NAME]
;; (what bin/cerebro-backup runs, and what a cron entry should call).
;;
;; The batch twin of `M-x cerebro-backup': same target table, same
;; commands. It runs them *synchronously* here rather than in a
;; compilation buffer -- a cron job has nowhere to show one, and its exit
;; status is the whole interface.

(let* ((here (file-name-directory (or load-file-name buffer-file-name)))
       (lisp-dir (expand-file-name "../.emacs.d/lisp" here)))
  (add-to-list 'load-path lisp-dir))

(require 'cerebro-backup)

(defun cerebro-backup-batch--run (name)
  "Run target NAME synchronously; return non-nil on success."
  (let* ((target (cerebro-backup-target name))
         (problems (and target (cerebro-backup-problems name target))))
    (cond
     ((null target) (princ (format "cerebro-backup: no target `%s'\n" name)) nil)
     (problems (princ (format "cerebro-backup: %s skipped -- %s\n"
                              name (string-join problems "; ")))
               nil)
     (t
      (princ (format "cerebro-backup: %s\n" name))
      (let ((default-directory cerebro-root)
            (command (cerebro-backup-command target)))
        (if (zerop (call-process "sh" nil t nil "-c" command))
            (progn (cerebro-backup--record name)
                   (princ (format "cerebro-backup: %s ok\n" name))
                   t)
          (princ (format "cerebro-backup: %s FAILED\n" name))
          nil))))))

(let* ((argument (or (car (last command-line-args-left)) "run")))
  (cond
   ((equal argument "status")
    (dolist (cell cerebro-backup-targets)
      (let* ((name (car cell))
             (target (cdr cell))
             (problems (cerebro-backup-problems name target)))
        (princ (format "%-8s %-8s last: %-22s %s\n"
                       name
                       (if problems "waiting" "ready")
                       (or (cerebro-backup-last-run name) "never")
                       (if problems (string-join problems "; ")
                         (cerebro-backup-command target)))))))
   ((equal argument "run")
    (let ((names (cerebro-backup-enabled-targets)))
      (if (null names)
          (progn (princ "cerebro-backup: no target enabled -- see 'cerebro backup status'\n")
                 (kill-emacs 0))
        (kill-emacs (if (seq-every-p #'cerebro-backup-batch--run names) 0 1)))))
   (t (kill-emacs (if (cerebro-backup-batch--run (intern argument)) 0 1)))))
