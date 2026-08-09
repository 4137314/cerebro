;;; cerebro-mode.el --- read and set the macro-mode from the shell -*- lexical-binding: t; -*-

;; Usage: emacs --batch -l bin/cerebro-mode.el -- [math|dev]
;;   (no argument)   report the mode in force, and why
;;   math | dev      switch, and remember it for every later session
;;
;; The shell twin of `C-c M s' / `C-c M m' / `C-c M d'. There is no
;; "this session only" here, and that is not an omission: a batch process
;; cannot change the shell that called it, so the one-off form is
;; `cerebro math' / `cerebro dev' (which export CEREBRO_MODE for the
;; editor they start) or CEREBRO_MODE=dev in front of any command.
;;
;; Batch Elisp rather than POSIX sh -- unlike bin/cerebro-note, which
;; reimplements the note digest in sh on purpose -- because there is
;; nothing here worth having twice: the modes, what each permits and how
;; the state file is read all live in .emacs.d/lisp/cerebro-mode.el, which
;; is a *pure* module (invariant 4), so loading it costs ~50ms and pulls
;; in no Org. A copy of the table in sh would buy nothing and could
;; disagree with the editor about what `dev' means, which is the one thing
;; this must never do.

(let* ((here (file-name-directory (or load-file-name buffer-file-name)))
       (lisp-dir (expand-file-name "../.emacs.d/lisp" here)))
  (add-to-list 'load-path lisp-dir))
(require 'cerebro-mode)

(let* ((args (delete "--" (copy-sequence command-line-args-left)))
       (requested (car args)))
  (condition-case err
      (progn
        (when requested
          (let ((mode (or (cerebro-mode-parse requested)
                          (error "unknown mode `%s' (know: %s)" requested
                                 (mapconcat #'symbol-name (cerebro-mode-names) ", ")))))
            (cerebro-mode-store mode)
            (setq cerebro-mode-current mode)))
        ;; Report either way: `cerebro mode' is a question far more often
        ;; than it is a command, and after a switch the same report is
        ;; exactly the confirmation you want -- what may now be written,
        ;; and which issues you will be shown.
        (dolist (line (cerebro-mode-report-lines)) (princ line) (terpri))
        (kill-emacs 0))
    (error (message "cerebro mode: %s" (error-message-string err))
           (kill-emacs 1))))
