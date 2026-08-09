;;; cerebro-isolation-tests.el --- ERT tests for the writable line -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-isolation-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test').
;;
;; One decision, made in one pure function, and it has to be exactly
;; right in both directions. Too strict and the editor cannot write the
;; archive it exists for; too loose and the guard rail is decorative.
;; Both failures are quiet, which is why they are pinned here.

(require 'ert)
(require 'cerebro-isolation)

(defun cerebro-isolation-tests--in-repo (relative)
  (expand-file-name relative cerebro-root))

;; -- The archive is writable --------------------------------------------

(ert-deftest cerebro-isolation-test-the-archive-is-writable ()
  "Everything this editor exists to write, it can write.
Notes are the point; issues and the bibliography are *part of* the
archive -- `C-c c i' captures into one and `C-c b n' writes the other."
  (dolist (path '("notes/math/abc123.org"
                  "notes/courses/analysis-A.org"
                  "notes/conjectures/xyz.org"
                  "notes/README.org"
                  "issues/issues.org"
                  "bib/references.bib"))
    (should (cerebro-isolation-writable-p (cerebro-isolation-tests--in-repo path)))))

(ert-deftest cerebro-isolation-test-the-machinery-is-not ()
  "The config, the tools, the classes and the tests open read-only.
Not because editing them is forbidden -- `C-c H u' does it in one
command -- but so that it is a deliberate act rather than something that
happens because a buffer was open."
  (dolist (path '(".emacs.d/init.el"
                  ".emacs.d/lisp/cerebro-org.el"
                  "guix.scm"
                  "makefile"
                  "bin/cerebro"
                  "bin/notes-lint.el"
                  "latex/cerebro.cls"
                  "tests/cerebro-org-tests.el"
                  "README.org"
                  "CLAUDE.md"))
    (should-not (cerebro-isolation-writable-p (cerebro-isolation-tests--in-repo path)))))

(ert-deftest cerebro-isolation-test-outside-the-repository-is-writable ()
  "This is a policy about not damaging cerebro, not a claim on the session.
An Emacs that opened an unrelated file read-only would just be broken."
  (should (cerebro-isolation-writable-p "/tmp/anything.txt"))
  (should (cerebro-isolation-writable-p (expand-file-name "~/notes.org"))))

(ert-deftest cerebro-isolation-test-no-file-is-not-protected ()
  "A buffer with no file cannot be outside the archive."
  (should-not (cerebro-isolation-writable-p nil)))

(ert-deftest cerebro-isolation-test-prefix-matching-is-on-directories ()
  "`notes' must not make `notes-backup/' writable too.

String-prefix matching on a path is the classic way to get this wrong:
without the trailing separator, any sibling whose name merely *starts*
with a writable directory's name would be let through."
  (let ((cerebro-isolation-writable-directories '("notes")))
    (should (cerebro-isolation-writable-p (cerebro-isolation-tests--in-repo "notes/a.org")))
    (should-not (cerebro-isolation-writable-p
                 (cerebro-isolation-tests--in-repo "notes-backup/a.org")))
    (should-not (cerebro-isolation-writable-p
                 (cerebro-isolation-tests--in-repo "notesomething.org")))))

;; -- Applying it --------------------------------------------------------

(ert-deftest cerebro-isolation-test-hook-is-installed ()
  "On `find-file-hook', so every route to a buffer is covered -- a key, a
link, a grep result -- not only the commands this config defines."
  (should (memq #'cerebro-isolation-protect find-file-hook)))

(ert-deftest cerebro-isolation-test-protect-marks-machinery-read-only ()
  "The hook sets `buffer-read-only' for machinery and leaves notes alone."
  (with-temp-buffer
    (setq buffer-file-name (cerebro-isolation-tests--in-repo "guix.scm"))
    (cerebro-isolation-protect)
    (should buffer-read-only))
  (with-temp-buffer
    (setq buffer-file-name (cerebro-isolation-tests--in-repo "notes/math/a.org"))
    (cerebro-isolation-protect)
    (should-not buffer-read-only)))

(ert-deftest cerebro-isolation-test-can-be-switched-off ()
  "A session spent working *on* cerebro turns the policy off wholesale."
  (with-temp-buffer
    (setq buffer-file-name (cerebro-isolation-tests--in-repo "guix.scm"))
    (let ((cerebro-isolation-enabled nil))
      (cerebro-isolation-protect))
    (should-not buffer-read-only)))

(ert-deftest cerebro-isolation-test-unlock-is-deliberate-and-reports ()
  "`C-c H u' crosses the line and says so; on a note it says that instead.
The whole value of the guard rail is in noticing that you crossed it."
  (with-temp-buffer
    (setq buffer-file-name (cerebro-isolation-tests--in-repo "guix.scm"))
    (cerebro-isolation-protect)
    (should buffer-read-only)
    (cerebro-isolation-unlock)
    (should-not buffer-read-only))
  ;; On something already writable it is a no-op, not a silent success.
  (with-temp-buffer
    (setq buffer-file-name (cerebro-isolation-tests--in-repo "notes/math/a.org"))
    (cerebro-isolation-unlock)
    (should-not buffer-read-only))
  ;; And a buffer with no file has nothing to unlock.
  (with-temp-buffer
    (should-error (cerebro-isolation-unlock) :type 'user-error)))

(provide 'cerebro-isolation-tests)
