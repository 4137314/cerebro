;;; cerebro-bib-tests.el --- ERT tests for the one bibliography -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-bib-tests.el \
;;          -f ert-run-tests-batch-and-exit   (see `make test').
;;
;; Everything here is the pure half: key generation, entry formatting,
;; and the parsers the linter's citation check and the duplicate check
;; both read. citar is not exercised -- it is a guix.scm package and this
;; suite runs anywhere.

(require 'ert)
(require 'cerebro-bib)
(require 'cerebro-latex) ;; the exporter must point at the same one file

;; -- Keys ---------------------------------------------------------------

(ert-deftest cerebro-bib-test-surname-reads-both-author-shapes ()
  "`Rudin, Walter' and `Walter Rudin' are the same person.
A generator that understands only one of them keys half the library by
first name, and nobody notices until two entries collide."
  (should (equal (cerebro-bib-surname "Rudin, Walter") "rudin"))
  (should (equal (cerebro-bib-surname "Walter Rudin") "rudin"))
  (should (equal (cerebro-bib-surname "Rudin, W.") "rudin"))
  ;; Only the first author, and accents/punctuation reduced to ASCII: a
  ;; key travels through TeX, a shell and a file name.
  (should (equal (cerebro-bib-surname "Bourbaki, N. and Dieudonne, J.") "bourbaki"))
  (should (equal (cerebro-bib-surname "Poincare, Henri") "poincare"))
  (should (equal (cerebro-bib-surname "") "")))

(ert-deftest cerebro-bib-test-key-shape ()
  "surname + year + first meaningful title word."
  (should (equal (cerebro-bib-key "Rudin, Walter" "1976"
                                  "Principles of Mathematical Analysis")
                 "rudin1976principles"))
  ;; Leading articles and prepositions are not the title.
  (should (equal (cerebro-bib-key "Cantor, Georg" "1874" "On a Property of the Set")
                 "cantor1874property"))
  ;; A date Org wrote, rather than a bare year.
  (should (equal (cerebro-bib-key "Hardy, G. H." "[1940]" "A Mathematician's Apology")
                 "hardy1940mathematician")))

(ert-deftest cerebro-bib-test-key-degrades-instead-of-erroring ()
  "A half-filled entry still gets a usable key: adding the reference is
what matters, and an entry keyed `anon' is visibly incomplete."
  (should (equal (cerebro-bib-key nil nil nil) "anon"))
  (should (equal (cerebro-bib-key "" "2020" "Untitled") "anon2020untitled")))

(ert-deftest cerebro-bib-test-unique-key-suffixes ()
  "Two works by one author, one year, same first word -- rare, real, and
not a reason to overwrite the first one."
  (should (equal (cerebro-bib-unique-key "rudin1976principles" '()) "rudin1976principles"))
  (should (equal (cerebro-bib-unique-key "rudin1976principles" '("rudin1976principles"))
                 "rudin1976principlesa"))
  (should (equal (cerebro-bib-unique-key
                  "rudin1976principles"
                  '("rudin1976principles" "rudin1976principlesa"))
                 "rudin1976principlesb")))

;; -- Entries ------------------------------------------------------------

(ert-deftest cerebro-bib-test-format-entry ()
  (let ((entry (cerebro-bib-format-entry
                "book" "rudin1976principles"
                '(("author" . "Rudin, Walter")
                  ("title" . "Principles of Mathematical Analysis")
                  ("publisher" . "McGraw-Hill")
                  ("year" . "1976")))))
    (should (string-prefix-p "@book{rudin1976principles,\n" entry))
    (should (string-match-p "  author = {Rudin, Walter}," entry))
    (should (string-suffix-p "}\n" entry))
    ;; It round-trips through the parser the linter uses.
    (should (equal (cerebro-bib-parse-keys entry) '("rudin1976principles")))))

(ert-deftest cerebro-bib-test-empty-fields-are-omitted ()
  "`doi = {}' claims the work has no DOI; leaving the field out says
nothing, which is what an unanswered prompt meant."
  (let ((entry (cerebro-bib-format-entry
                "article" "x2020y"
                '(("author" . "A") ("title" . "T") ("doi" . "  ") ("pages" . "")))))
    (should-not (string-match-p "doi" entry))
    (should-not (string-match-p "pages" entry))
    (should (string-match-p "author" entry))))

;; -- Reading a .bib -----------------------------------------------------

(defconst cerebro-bib-tests--file
  "% a comment mentioning @nobody{notakey,\n\n@book{rudin1976principles,\n  author = {Rudin, Walter},\n  title = {Principles of Mathematical Analysis},\n  year = {1976}\n}\n\n@Article{ Cantor1874Property ,\n  author = {Cantor, Georg},\n  title = {On a property of the collection of all real algebraic numbers},\n  year = {1874}\n}\n"
  "A .bib with the shapes a hand-written file actually has: a leading
comment, mixed case, and stray whitespace around the key.")

(ert-deftest cerebro-bib-test-parse-keys ()
  (should (equal (cerebro-bib-parse-keys cerebro-bib-tests--file)
                 '("rudin1976principles" "Cantor1874Property")))
  (should-not (cerebro-bib-parse-keys "no entries here\n")))

(ert-deftest cerebro-bib-test-entry-type-and-fields ()
  (let ((entry "@InProceedings{k,\n  author = {A B},\n  title = {A {TeX}-protected word},\n  year = {2020}\n}\n"))
    (should (equal (cerebro-bib-entry-type entry) "inproceedings"))
    (should (equal (cerebro-bib-field entry "author") "A B"))
    ;; One level of nested braces, which is what a protected word needs.
    (should (equal (cerebro-bib-field entry "title") "A {TeX}-protected word"))
    (should-not (cerebro-bib-field entry "journal"))))

(ert-deftest cerebro-bib-test-rekey ()
  "An imported entry is re-keyed to the house convention, and nothing
else about it is touched."
  (let* ((entry "@book{THEIRWEIRDKEY,\n  author = {Rudin, Walter},\n  year = {1976}\n}\n")
         (out (cerebro-bib-rekey entry "rudin1976principles")))
    (should (equal (cerebro-bib-parse-keys out) '("rudin1976principles")))
    (should (string-match-p "author = {Rudin, Walter}" out))
    (should-not (string-match-p "THEIRWEIRDKEY" out))))

;; -- The archive's own bibliography -------------------------------------

(ert-deftest cerebro-bib-test-there-is-exactly-one-bibliography ()
  "One file, and the exporter points at that same file.
Two .bib files is how one book acquires two keys."
  (should (file-readable-p cerebro-bib-file))
  (should (equal org-cite-global-bibliography (list cerebro-bib-file)))
  (should (cerebro-bib-keys)))

(ert-deftest cerebro-bib-test-entry-types-are-well-formed ()
  "Every declared type asks for at least the fields a key is built from."
  (dolist (row cerebro-bib-entry-types)
    (let ((fields (cerebro-bib-type-fields (car row))))
      (should (member "author" fields))
      (should (member "title" fields))
      (should (member "year" fields))
      ;; The first `cerebro-bib-required-fields' are the insisted-on
      ;; ones, so the key's inputs have to be among them.
      (should (<= (length (seq-take fields cerebro-bib-required-fields))
                  (length fields)))))
  (should-error (cerebro-bib-type-fields "sonnet")))

(provide 'cerebro-bib-tests)
