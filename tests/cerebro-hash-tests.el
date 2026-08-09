;;; cerebro-hash-tests.el --- ERT tests for content-addressed note names -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-hash-tests.el \
;;          -f ert-run-tests-batch-and-exit   (see `make test').
;;
;; The digest is a *contract*, not an implementation detail: three
;; independent things compute it (this module, bin/cerebro-note in POSIX
;; sh, and bin/notes-lint.el when it checks a file), and a note whose
;; name two of them disagree about would be renamed back and forth
;; forever. So one test below pins the digest of a fixed note to a
;; literal constant. If a change to the canonical form breaks it, that is
;; the test doing its job -- update the constant here AND re-run
;; `cerebro note rehash' over the archive, which is exactly the migration
;; the change implies.

(require 'ert)
(require 'cerebro-hash)

(defconst cerebro-hash-tests--note
  (concat ":PROPERTIES:\n"
          ":ID:       abc-123\n"
          ":END:\n"
          "#+TITLE: Supremum and infimum\n"
          "#+DATE: [2026-08-06 Thu]\n"
          "#+FILETAGS: :seed:analysis:\n"
          "#+MSC: 26A03\n"
          "\n"
          "Body text, which is not part of the note's identity.\n")
  "A fixed note, used as the fixture throughout.")

;; -- The canonical form -------------------------------------------------

(ert-deftest cerebro-hash-test-parse-reads-the-front-matter ()
  "Every declared field is read: the ID from the drawer, the rest from
their `#+KEY:' lines."
  (let ((meta (cerebro-hash-parse cerebro-hash-tests--note)))
    (should (equal (cdr (assoc "ID" meta)) "abc-123"))
    (should (equal (cdr (assoc "TITLE" meta)) "Supremum and infimum"))
    (should (equal (cdr (assoc "DATE" meta)) "[2026-08-06 Thu]"))
    (should (equal (cdr (assoc "FILETAGS" meta)) ":seed:analysis:"))
    (should (equal (cdr (assoc "MSC" meta)) "26A03"))))

(ert-deftest cerebro-hash-test-missing-fields-are-empty-not-absent ()
  "A note with no MSC still hashes: the field is present and empty.
Otherwise adding a classification to a note would be indistinguishable
from a different note entirely, which it is -- but a *missing* field must
not shift the meaning of the fields around it."
  (let ((meta (cerebro-hash-parse "#+TITLE: T\n")))
    (should (equal (cdr (assoc "MSC" meta)) ""))
    (should (string-match-p "^MSC: $" (cerebro-hash-canonical meta)))))

(ert-deftest cerebro-hash-test-whitespace-is-not-identity ()
  "Reformatting the front matter does not rename the file.
`#+TITLE:  A  B' and `#+TITLE: A B' are the same title, and a stray
double space is not a reason to move a file in git."
  (should (equal (cerebro-hash-of-text "#+TITLE: A B\n")
                 (cerebro-hash-of-text "#+TITLE:   A  B  \n"))))

(ert-deftest cerebro-hash-test-canonical-form-is-ordered-and-complete ()
  "The hashed string is one `FIELD: value' line per field, in the
declared order -- the form bin/cerebro-note reproduces in sh."
  (should (equal (cerebro-hash-canonical
                  (cerebro-hash-parse cerebro-hash-tests--note))
                 (concat "ID: abc-123\n"
                         "TITLE: Supremum and infimum\n"
                         "DATE: [2026-08-06 Thu]\n"
                         "FILETAGS: :seed:analysis:\n"
                         "MSC: 26A03\n"))))

;; -- The digest ---------------------------------------------------------

(ert-deftest cerebro-hash-test-digest-is-pinned ()
  "The digest of the fixture, as a literal.
This is the constant bin/cerebro-note must also produce; see the
commentary at the top of this file before changing it."
  (should (equal (cerebro-hash-of-text cerebro-hash-tests--note) "a4e650150324"))
  (should (equal (cerebro-hash-file-name
                  (cerebro-hash-of-text cerebro-hash-tests--note))
                 "a4e650150324.org")))

(ert-deftest cerebro-hash-test-digest-shape ()
  (let ((hash (cerebro-hash-of-text cerebro-hash-tests--note)))
    (should (= (length hash) cerebro-hash-length))
    (should (string-match-p "\\`[0-9a-f]+\\'" hash))))

(ert-deftest cerebro-hash-test-body-is-not-identity ()
  "Rewriting a proof does not rename the note. Retitling it does.
That distinction is the whole design: the name follows what the note
*is*, not what it currently says."
  (let ((edited (concat cerebro-hash-tests--note "\nA new paragraph.\n")))
    (should (equal (cerebro-hash-of-text edited)
                   (cerebro-hash-of-text cerebro-hash-tests--note))))
  (dolist (changed '("#+TITLE: Least upper bound property"
                     "#+FILETAGS: :evergreen:analysis:"
                     "#+MSC: 26A06"))
    (let ((text (replace-regexp-in-string
                 (format "^#\\+%s:.*$" (car (split-string (substring changed 2) ":")))
                 changed cerebro-hash-tests--note)))
      (should-not (equal (cerebro-hash-of-text text)
                         (cerebro-hash-of-text cerebro-hash-tests--note))))))

;; -- Recording the digest in the file -----------------------------------

(ert-deftest cerebro-hash-test-set-line-appends-after-the-front-matter ()
  "The `#+HASH:' line goes below the fields it is computed from, and
above the body."
  (let ((text (cerebro-hash-set-line cerebro-hash-tests--note "deadbeef1234")))
    (should (string-match-p "#\\+MSC: 26A03\n#\\+HASH: deadbeef1234\n" text))))

(ert-deftest cerebro-hash-test-set-line-is-idempotent ()
  "Writing the line twice writes one line, not two."
  (let* ((once (cerebro-hash-set-line cerebro-hash-tests--note "deadbeef1234"))
         (twice (cerebro-hash-set-line once "deadbeef1234")))
    (should (equal once twice))
    (should (= 1 (cl-count "#+HASH: deadbeef1234"
                           (split-string twice "\n") :test #'equal)))))

(ert-deftest cerebro-hash-test-set-line-never-splits-a-named-block ()
  "The line goes after the declared metadata keywords, never after just
any `#+KEYWORD:'. `#+NAME:' is a keyword too, and it has to stay touching
the `#+begin_' line below it -- a line inserted between them detaches the
name and silently breaks the `single' export."
  (let* ((note (concat "#+TITLE: T\n#+MSC: 26A03\n\n"
                       "#+NAME: thm-x\n#+begin_theorem\nS\n#+end_theorem\n"))
         (out (cerebro-hash-set-line note "deadbeef1234")))
    (should (string-match-p "#\\+NAME: thm-x\n#\\+begin_theorem" out))
    (should (string-match-p "#\\+MSC: 26A03\n#\\+HASH: deadbeef1234" out))))

(ert-deftest cerebro-hash-test-set-line-replaces-a-stale-digest ()
  (let* ((stale (cerebro-hash-set-line cerebro-hash-tests--note "000000000000"))
         (fresh (cerebro-hash-set-line stale "111111111111")))
    (should (string-match-p "#\\+HASH: 111111111111" fresh))
    (should-not (string-match-p "000000000000" fresh))))

(ert-deftest cerebro-hash-test-recording-the-hash-does-not-change-it ()
  "The `#+HASH:' keyword is not one of the hashed fields, so writing it
into the file cannot invalidate what it says. Without this the name
could never converge."
  (let* ((hash (cerebro-hash-of-text cerebro-hash-tests--note))
         (recorded (cerebro-hash-set-line cerebro-hash-tests--note hash)))
    (should (equal (cerebro-hash-of-text recorded) hash))))

;; -- Which files this module owns ---------------------------------------

(ert-deftest cerebro-hash-test-which-directories-are-owned ()
  "Notes are hash-named; everything a person named is left alone.
Both note directories are owned -- a conjecture is a note -- and a
course file, which a person named after the course, is not."
  (should (cerebro-hash-note-p (expand-file-name "x.org" cerebro-math-directory)))
  (should (cerebro-hash-note-p (expand-file-name "x.org" cerebro-conjecture-directory)))
  (should (member cerebro-conjecture-directory cerebro-hash-directories))
  (should-not (cerebro-hash-note-p (expand-file-name "README.org" org-directory)))
  (should-not (cerebro-hash-note-p
               (expand-file-name "courses/analysis-A.org" org-directory)))
  (should-not (cerebro-hash-note-p
               (expand-file-name "notes.txt" cerebro-math-directory)))
  (should-not (cerebro-hash-note-p nil)))

;; -- Checking a real file -----------------------------------------------

(ert-deftest cerebro-hash-test-check-file-detects-drift ()
  "A file whose name no longer follows from its contents is reported --
this is what `cerebro lint' calls, and what `cerebro note rehash' fixes."
  (let* ((dir (make-temp-file "cerebro-hash-test" t))
         (hash (cerebro-hash-of-text cerebro-hash-tests--note))
         (right (expand-file-name (concat hash ".org") dir))
         (wrong (expand-file-name "hand-named.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file right
            (insert (cerebro-hash-set-line cerebro-hash-tests--note hash)))
          (with-temp-file wrong (insert cerebro-hash-tests--note))
          (should-not (cerebro-hash-check-file right))
          (let ((drift (cerebro-hash-check-file wrong)))
            (should drift)
            (should (equal (plist-get drift :hash) hash))))
      (delete-directory dir t))))

(ert-deftest cerebro-hash-test-rehash-directory-is-idempotent ()
  "Running the repair twice renames nothing the second time."
  (let ((dir (make-temp-file "cerebro-hash-test" t)))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "hand-named.org" dir)
            (insert cerebro-hash-tests--note))
          (should (= 1 (cerebro-hash-rehash-directory dir)))
          (should (equal (directory-files dir nil "\\.org\\'")
                         (list (cerebro-hash-file-name
                                (cerebro-hash-of-text cerebro-hash-tests--note)))))
          (should (= 0 (cerebro-hash-rehash-directory dir))))
      (delete-directory dir t))))

(ert-deftest cerebro-hash-test-a-readme-is-not-this-module-s-to-name ()
  "The repair leaves README.org alone, as `cerebro note rehash' does.

A README inside notes/math/ or notes/conjectures/ is this repository
explaining the directory, not a note -- `cerebro-note-files' has always
excluded it. This module did not: `cerebro-hash-rehash' wrote a
`#+HASH:' line into notes/conjectures/README.org and renamed it to
e27569f8051f.org, while the shell twin skipped it by name. Two
implementations of one operation, disagreeing about which files exist."
  (should-not (cerebro-hash-note-p
               (expand-file-name "README.org" cerebro-conjecture-directory)))
  (should-not (cerebro-hash-note-p
               (expand-file-name "README.org" cerebro-math-directory)))
  (should (cerebro-hash-note-p
           (expand-file-name "a3f19c04b2e7.org" cerebro-math-directory)))
  ;; ...and the directory repair honours it, on a directory it is handed
  ;; by name (where the ownership half of `cerebro-hash-note-p' cannot
  ;; apply).
  (let ((dir (make-temp-file "cerebro-hash-readme" t)))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "README.org" dir)
            (insert cerebro-hash-tests--note))
          (should (= 0 (cerebro-hash-rehash-directory dir)))
          (should (equal (directory-files dir nil "\\.org\\'") '("README.org"))))
      (delete-directory dir t))))

(provide 'cerebro-hash-tests)
