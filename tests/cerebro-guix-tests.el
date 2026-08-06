;;; cerebro-guix-tests.el --- ERT tests for the environment layer -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-guix-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test'). cerebro-guix.el is deliberately pure Emacs core, so
;; it loads in batch outside Guix -- which is the state it exists to
;; describe.
;;
;; What is worth pinning down here is the reasoning the rest of the
;; config trusts: "am I pinned?" must be false for the bootstrap
;; template (a template that read as a real pin would make an
;; unreproducible environment look reproducible), and a missing package
;; must come back as a *datum* rather than an error, since that is the
;; whole mechanism keeping the optional modules independently loadable.

(require 'ert)
(require 'cerebro-guix)

(defmacro cerebro-guix-tests--with-file (contents &rest body)
  "Write CONTENTS to a temporary file bound to `file', then run BODY."
  (declare (indent 1) (debug t))
  `(let ((file (make-temp-file "cerebro-channels-" nil ".scm" ,contents)))
     (unwind-protect (progn ,@body)
       (delete-file file))))

(ert-deftest cerebro-guix-test-pinned-commit-reads-real-pin ()
  "A real channel commit is returned, not the introduction's commit.
`make-channel-introduction' also carries a 40-hex string; taking the
wrong one would report a pin the time-machine never uses."
  (cerebro-guix-tests--with-file
      (concat "(list (channel\n"
              "       (name 'guix)\n"
              "       (commit \"862e2bf1b5474d117e9f7853f3121ecaa2d23fe6\")\n"
              "       (introduction\n"
              "        (make-channel-introduction\n"
              "         \"9edb3f66fd807b096b48283debdcddccfea34bad\"\n"
              "         (openpgp-fingerprint \"BBB0\")))))\n")
    (should (equal (cerebro-guix-pinned-commit file)
                   "862e2bf1b5474d117e9f7853f3121ecaa2d23fe6"))))

(ert-deftest cerebro-guix-test-pinned-commit-rejects-template ()
  "The shipped bootstrap template counts as *no* pin."
  (cerebro-guix-tests--with-file
      "(list (channel (name 'guix) (commit \"REPLACE-WITH-REAL-COMMIT\")))\n"
    (should-not (cerebro-guix-pinned-commit file))))

(ert-deftest cerebro-guix-test-pinned-commit-missing-file ()
  "A missing channels file is nil, not an error: the status report has to
render on a machine where the repo was only half set up."
  (should-not (cerebro-guix-pinned-commit "/nonexistent/channels.scm")))

(ert-deftest cerebro-guix-test-soft-require-records-missing ()
  "A package that isn't there is recorded once and returns nil."
  (let ((cerebro-guix-missing-packages nil))
    (should-not (cerebro-guix-soft-require 'cerebro-no-such-package))
    (should-not (cerebro-guix-soft-require 'cerebro-no-such-package))
    (should (equal cerebro-guix-missing-packages '(cerebro-no-such-package)))))

(ert-deftest cerebro-guix-test-soft-require-loads-present ()
  "A feature that is available loads and is not recorded as missing."
  (let ((cerebro-guix-missing-packages nil))
    (should (cerebro-guix-soft-require 'subr-x))
    (should-not cerebro-guix-missing-packages)))

(ert-deftest cerebro-guix-test-inside-p-follows-the-environment ()
  "`cerebro-guix-inside-p' is exactly \"GUIX_ENVIRONMENT is set\"."
  (let ((process-environment (cons "GUIX_ENVIRONMENT=/gnu/store/fake-profile"
                                   process-environment)))
    (should (cerebro-guix-inside-p))
    (should (equal (cerebro-guix-profile) "/gnu/store/fake-profile")))
  (let ((process-environment (seq-remove (lambda (v) (string-prefix-p "GUIX_ENVIRONMENT=" v))
                                         process-environment)))
    (should-not (cerebro-guix-inside-p))))

(ert-deftest cerebro-guix-test-status-lines-cover-every-package ()
  "The report renders as plain strings and lists every declared package,
so adding one to `cerebro-guix-optional-packages' (one datum) is all it
takes to have it reported."
  (let ((lines (cerebro-guix-status-lines)))
    (should (seq-every-p #'stringp lines))
    (dolist (cell cerebro-guix-optional-packages)
      (should (seq-find (lambda (l) (string-match-p (regexp-quote (symbol-name (car cell))) l))
                        lines)))))

(ert-deftest cerebro-guix-test-headline-is-one-line ()
  "The dashboard uses the headline as a single init-info line."
  (let ((headline (cerebro-guix-headline)))
    (should (stringp headline))
    (should-not (string-match-p "\n" headline))))

;;; cerebro-guix-tests.el ends here
