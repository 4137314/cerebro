;;; cerebro-base-tests.el --- ERT tests for the dependency-free layer -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-base-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test').
;;
;; cerebro-base.el is mostly paths, so the interesting test is not what it
;; computes but what it does NOT drag in. CLAUDE.md's invariant 4 says the
;; pure modules "need no Guix package, so [they are] unit-testable and
;; work outside Guix", and that claim had quietly stopped being true:
;; cerebro-results.el and cerebro-hash.el each did `(require 'cerebro-org)'
;; for a directory name, and cerebro-org.el loads org, org-agenda, org-id,
;; org-refile and ispell. Measured, one process per module:
;;
;;     (require 'cerebro-results)   384 ms  ->  60 ms
;;     (require 'cerebro-hash)      350 ms  ->  47 ms
;;     the work either then does     33 ms cold, 4 ms cached
;;
;; A comment cannot hold that line -- the regression is one `require' away
;; and nothing about it looks wrong. `cerebro-base-test-pure-modules-do-
;; not-load-org' is what holds it, and it has to run in a subprocess,
;; because by the time the rest of the suite is running Org is loaded for
;; other reasons and the question can no longer be asked in-process.

(require 'ert)
(require 'cerebro-base)

;; -- What a note is -----------------------------------------------------

(ert-deftest cerebro-base-test-note-file-p-is-the-single-definition ()
  "A README and a build product are not notes; a note in math/ is.

`cerebro-not-a-note-regexp' had no predicate, so every caller that
listed a directory itself re-derived the answer and three of them got it
wrong -- the rehash renamed notes/conjectures/README.org to a digest,
`C-c f j' offered it as the only conjecture, and `C-c e c' called
notes/courses/README.org a course."
  (should (cerebro-note-file-p (expand-file-name "a3f19c04b2e7.org"
                                                 cerebro-math-directory)))
  (should-not (cerebro-note-file-p (expand-file-name "README.org"
                                                     cerebro-conjecture-directory)))
  (should-not (cerebro-note-file-p (expand-file-name "courses/README.org"
                                                     org-directory)))
  (should-not (cerebro-note-file-p (expand-file-name "courses/.build/x-handbook.org"
                                                     org-directory)))
  ;; Not an .org file, and no file at all.
  (should-not (cerebro-note-file-p (expand-file-name "notes.txt" org-directory)))
  (should-not (cerebro-note-file-p nil))
  ;; Anchored on the `/' before the name, so a bare relative name has to
  ;; be expanded before the regexp can see it.
  (should-not (cerebro-note-file-p "README.org")))

(ert-deftest cerebro-base-test-note-files-agrees-with-the-predicate ()
  "The lister and the predicate are one definition, not two."
  (dolist (file (cerebro-note-files))
    (should (cerebro-note-file-p file)))
  (should-not (seq-find (lambda (f) (string-match-p "README" f))
                        (cerebro-note-files))))

(ert-deftest cerebro-base-test-paths-are-under-the-repository ()
  "The archive's directories are derived from one root, not spelled out."
  (should (string-prefix-p (expand-file-name cerebro-root)
                           (expand-file-name org-directory)))
  (should (string-prefix-p (expand-file-name org-directory)
                           (expand-file-name cerebro-math-directory)))
  (should (string-prefix-p (expand-file-name org-directory)
                           (expand-file-name cerebro-conjecture-directory)))
  (should (string-prefix-p (expand-file-name cerebro-root)
                           (expand-file-name cerebro-bib-file))))

(ert-deftest cerebro-base-test-build-output-is-not-a-note ()
  "A course composed for export is a real .org file full of #+INCLUDEs.
Counting it would double every note it pulls in -- in the stats, in the
graph and in the linter -- so `.build/' is excluded by path."
  (should (string-match-p cerebro-not-a-note-regexp "/n/courses/.build/x.org"))
  (should (string-match-p cerebro-not-a-note-regexp "/n/README.org"))
  (should-not (string-match-p cerebro-not-a-note-regexp "/n/math/abc123.org")))

(ert-deftest cerebro-base-test-build-output-is-not-a-directory-either ()
  "`.build/' is excluded from the *directory* list, not only the file one.

Regression test, for a bug whose symptom pointed nowhere near its cause.
This list feeds `org-agenda-files', so a composed course left in
`.build/' by a previous export was scanned as though it were a note --
and the first export after any note was renamed then died with `Cannot
include file .../<the previous digest>.org', naming a file that had just
ceased to exist. The two sibling functions disagreed about what counts
as derived; only one of them was right."
  (let ((dirs (cerebro-note-directories)))
    (should dirs)
    (should-not (seq-find (lambda (d) (string-match-p "/\\.build\\'\\|/\\.build/" d))
                          dirs))
    ;; ...and it still lists the real ones.
    (should (seq-find (lambda (d) (string-suffix-p "/math" d)) dirs))))

(ert-deftest cerebro-base-test-note-files-finds-the-archive ()
  "The real tree, through the memoised lister."
  (let ((files (cerebro-note-files)))
    (should (> (length files) 10))
    (should (seq-every-p (lambda (f) (string-suffix-p ".org" f)) files))
    (should-not (seq-find (lambda (f) (string-match-p cerebro-not-a-note-regexp f))
                          files))))

;; -- The line that has to hold -----------------------------------------

(defun cerebro-base-tests--load-report (module)
  "Load MODULE in a fresh Emacs; return \"clean\", \"ORG\", or LOADFAIL.

A subprocess on purpose: the question is what a *fresh* Emacs pulls in,
and by the time this suite runs Org is loaded for other reasons, so
asking in-process would always answer yes.

Two details that both had to be got right before this could be trusted:

  - stderr is discarded (the `(list t nil)' destination), not folded in.
    A module is entitled to talk on the way up -- cerebro-keys announces
    repeat-mode, cerebro-session announces recentf -- and mixing that
    into the answer made two perfectly clean modules read as failures.
  - the `require' is NOT wrapped in NOERROR. A module that fails to load
    would then report as one that loaded without Org: the same word for
    the opposite outcome, which is how a tier like this stops meaning
    anything."
  (string-trim
   (with-output-to-string
     (with-current-buffer standard-output
       (call-process
        (expand-file-name invocation-name invocation-directory)
        nil (list t nil) nil
        "--batch" "-L" (expand-file-name ".emacs.d/lisp" cerebro-root)
        "--eval"
        (format "(condition-case e (progn (require '%s)
                                          (princ (if (featurep 'org) \"ORG\" \"clean\")))
                   (error (princ (format \"LOADFAIL: %%S\" e))))"
                module))))))

(ert-deftest cerebro-base-test-pure-modules-do-not-load-org ()
  "The modules CLAUDE.md calls pure must load without pulling in Org.

Run in a subprocess on purpose: this is a question about what a *fresh*
Emacs loads, and in this one Org is already loaded by the other tests, so
asking it here would always answer yes. The cost of getting this wrong is
not a crash -- it is every shell entry point silently paying ~340ms to
load an agenda it never uses.

The list is `cerebro-pure-modules', not a copy of it: `make compile'
byte-compiles the same modules with warnings promoted to errors, and two
hand-kept lists of \"the pure ones\" would eventually disagree about
which module the invariant covers."
  (dolist (module (mapcar #'symbol-name cerebro-pure-modules))
    (should (equal (cerebro-base-tests--load-report module) "clean"))))

(ert-deftest cerebro-base-test-org-free-modules-do-not-load-org ()
  "The tier that may use a Guix package but still may not load Org.

The line this holds is the one that had already been crossed:
cerebro-guix used three symbols that all live in cerebro-base and
required cerebro-org for them anyway, so the whole presentation layer --
theme, modeline, focus -- loaded org, org-agenda and ispell to draw
itself. A comment on the `require' named the three base symbols the
entire time. Comments do not run."
  (dolist (module (mapcar #'symbol-name cerebro-org-free-modules))
    (should (equal (cerebro-base-tests--load-report module) "clean"))))

(ert-deftest cerebro-base-test-the-two-tiers-nest ()
  "Pure is the strict half of Org-free, not a second opinion about it.

`cerebro-pure-modules' means \"no Org and no Guix package, and compiles
warning-free\"; `cerebro-org-free-modules' means \"no Org\". The first is
a subset of the second by construction, and pinning it keeps a module
from being quietly promoted in one list and not the other."
  (dolist (module cerebro-pure-modules)
    (should (memq module cerebro-org-free-modules)))
  ;; No duplicates: the list is built by `append', so a module added to
  ;; the pure list and then repeated below would silently be tested twice
  ;; and read as two different decisions.
  (should (equal (length cerebro-org-free-modules)
                 (length (delete-dups (copy-sequence cerebro-org-free-modules))))))

(provide 'cerebro-base-tests)
