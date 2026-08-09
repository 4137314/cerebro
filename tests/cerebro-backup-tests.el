;;; cerebro-backup-tests.el --- ERT tests for the backup policy -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-backup-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test').
;;
;; A backup module has two failure modes worth engineering against, and
;; both are silent: doing nothing while looking configured, and doing
;; something *wrong* -- an rsync with an empty destination, a push to a
;; remote that is not there. So the tests are about refusing to run:
;; every target must be able to say why it cannot, before it runs, and
;; nothing may be enabled by default.

(require 'ert)
(require 'cerebro-backup)

;; -- Nothing happens until you say so ----------------------------------

(ert-deftest cerebro-backup-test-nothing-is-enabled-by-default ()
  "Out of the box no target runs.
Where a copy of a lifetime of notes should go is the owner's decision;
an editor that starts copying them somewhere on its own is a worse
problem than having no backup."
  (should-not (cerebro-backup-enabled-targets))
  (dolist (cell cerebro-backup-targets)
    (should-not (plist-get (cdr cell) :enabled))))

(ert-deftest cerebro-backup-test-unconfigured-target-builds-no-command ()
  "A target with no destination produces nil, not half a command.
`rsync -a --delete ./ ' with an empty destination is not a backup, it is
a mistake with a progress bar."
  (should-not (cerebro-backup-command '(:command "rsync -a ./ %s" :value "")))
  (should-not (cerebro-backup-command '(:command "rsync -a ./ %s" :value "   ")))
  (should (equal (cerebro-backup-command '(:command "rsync -a ./ %s" :value "/mnt/x"))
                 "rsync -a ./ /mnt/x")))

(ert-deftest cerebro-backup-test-every-placeholder-is-filled ()
  "A command with two placeholders gets both filled from one value.
The git target pushes branches *and* tags -- two `%s' in one line."
  (should (equal (cerebro-backup-command
                  '(:command "git push --all %s && git push --tags %s" :value "origin"))
                 "git push --all origin && git push --tags origin")))

;; -- Why a target cannot run -------------------------------------------

(ert-deftest cerebro-backup-test-problems-are-specific ()
  "Each reason is reported separately, so the fix is obvious."
  (let ((target '(:enabled nil :command "rsync -a ./ %s" :value ""
                  :needs ("definitely-not-a-program") :parameter "destination")))
    (let ((problems (cerebro-backup-problems 'mirror target)))
      (should (seq-find (lambda (p) (string-match-p "not enabled" p)) problems))
      (should (seq-find (lambda (p) (string-match-p "destination" p)) problems))
      (should (seq-find (lambda (p) (string-match-p "not installed" p)) problems)))))

(ert-deftest cerebro-backup-test-a-configured-target-has-no-problems ()
  "Enabled, with a value and its programs present: ready."
  (let ((target (list :enabled t :command "sh -c 'true' %s" :value "x"
                      :needs '("sh") :parameter "destination")))
    (should-not (cerebro-backup-problems 'test target))))

;; -- The log ------------------------------------------------------------

(ert-deftest cerebro-backup-test-log-is-plain-text-and-readable-back ()
  "\"When did this last work?\" is answerable with `cat', and by us.
The log is deliberately a text file: on a machine where Emacs no longer
starts, that question still has to have an answer."
  (let ((log (make-temp-file "cerebro-backup-log-")))
    (unwind-protect
        (progn
          (write-region (cerebro-backup-log-line 'mirror (encode-time 0 0 9 1 3 2026))
                        nil log 'append 0)
          (write-region (cerebro-backup-log-line 'git (encode-time 0 30 9 1 3 2026))
                        nil log 'append 0)
          (write-region (cerebro-backup-log-line 'mirror (encode-time 0 0 18 2 3 2026))
                        nil log 'append 0)
          ;; The *last* line about a target is the one that counts.
          (should (equal (cerebro-backup-last-run 'mirror log) "[2026-03-02 Mon 18:00]"))
          (should (equal (cerebro-backup-last-run 'git log) "[2026-03-01 Sun 09:30]"))
          (should-not (cerebro-backup-last-run 'archive log)))
      (delete-file log))))

(provide 'cerebro-backup-tests)
