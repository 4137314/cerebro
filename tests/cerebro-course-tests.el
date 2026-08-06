;;; cerebro-course-tests.el --- ERT tests for courses-as-index -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-course-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test').
;;
;; book.org is generated, so the generator is the only thing standing
;; between a syllabus and a document that fails to compile. Three things
;; are worth pinning down, and all three are silent failures:
;;
;;   - the programme must be read as a *subtree*: a link in the
;;     bibliography or the assessment section is not part of the course;
;;   - the include must start below the note's front matter, or the
;;     second `#+TITLE:' spliced into the middle of the book silently
;;     overrides the book's own title (and the note's tags and :ID: land
;;     in the text);
;;   - a link to a note that no longer exists must be *reported*, not
;;     quietly dropped -- a chapter missing from a book is not something
;;     you notice by reading the LaTeX log.
;;
;; The one impure step (an ID -> a file) is injected, so none of this
;; needs a note database.

(require 'ert)
(require 'cerebro-course)

(defconst cerebro-course-tests--syllabus "\
#+TITLE: Analysis I -- syllabus
#+COURSE_TITLE: Analysis I

* Description
Some prose, and a link that is NOT part of the programme:
[[id:not-a-chapter][Something else]]

* Programme
** Continuity
- [[id:aaa][Limits and continuity]]
** Inner product spaces
- [[id:bbb][Inner product space]]
- [[id:ccc][Cauchy--Schwarz inequality]]

* Bibliography
[[id:zzz][A book I like]]
")

(defun cerebro-course-tests--resolve (id)
  "A stand-in note database: three notes, and `ccc' is missing."
  (pcase id
    ("aaa" (list :file "/repo/notes/math/limits.org"
                 :title "Limits and continuity" :body-line 7))
    ("bbb" (list :file "/repo/notes/math/inner-product.org"
                 :title "Inner product space" :body-line 9))
    (_ nil)))

;; -- Reading the programme ---------------------------------------------

(ert-deftest cerebro-course-test-programme-is-a-subtree ()
  "Only links inside the programme count, and they keep their order."
  (let* ((entries (cerebro-course-parse-programme cerebro-course-tests--syllabus))
         (notes (seq-filter (lambda (e) (eq (plist-get e :kind) 'note)) entries)))
    (should (equal (mapcar (lambda (e) (plist-get e :id)) notes)
                   '("aaa" "bbb" "ccc")))
    ;; The link in `* Description' comes before the programme, the one in
    ;; `* Bibliography' after it: neither is a chapter of the course.
    (should-not (member "not-a-chapter" (mapcar (lambda (e) (plist-get e :id)) notes)))
    (should-not (member "zzz" (mapcar (lambda (e) (plist-get e :id)) notes)))))

(ert-deftest cerebro-course-test-programme-headings-become-levels ()
  "A `** Chapter' under `* Programme' is level 1; its notes hang below it."
  (let ((entries (cerebro-course-parse-programme cerebro-course-tests--syllabus)))
    (should (equal (car entries) '(:kind heading :level 1 :text "Continuity")))
    (should (equal (plist-get (nth 1 entries) :id) "aaa"))
    (should (= (plist-get (nth 1 entries) :level) 1))))

(ert-deftest cerebro-course-test-programme-without-chapters ()
  "A flat reading list is legal: notes then sit at level 0."
  (let ((entries (cerebro-course-parse-programme
                  "* Programme\n- [[id:aaa][One]]\n- [[id:bbb][Two]]\n")))
    (should (= (length entries) 2))
    (should (= (plist-get (car entries) :level) 0))))

(ert-deftest cerebro-course-test-programme-ignores-comments ()
  "Links inside a comment block are documentation, not chapters.
The scaffolded course.org explains the format with example links in a
`#+begin_comment' -- read literally, every new course would come with
three imaginary chapters."
  (let ((entries (cerebro-course-parse-programme "\
* Programme
#+begin_comment
For example:
- [[id:example][An example note]]
#+end_comment
- [[id:real][A real note]]
# - [[id:commented-out][Not this one either]]
")))
    (should (equal (mapcar (lambda (e) (plist-get e :id)) entries) '("real")))))

(ert-deftest cerebro-course-test-programme-can-be-renamed ()
  "The heading name is a datum, not a hardcoded string."
  (let ((entries (cerebro-course-parse-programme
                  "* Contenuto\n- [[id:aaa][One]]\n" "Contenuto")))
    (should (equal (plist-get (car entries) :id) "aaa"))))

;; -- Where a note's body starts ----------------------------------------

(ert-deftest cerebro-course-test-body-line-skips-front-matter ()
  "The include starts at the first line of real content.
Including the front matter would splice a second `#+TITLE:' into the
book -- which Org accepts, and which then wins over the book's title."
  (should (= (cerebro-course-note-body-line "\
:PROPERTIES:
:ID:       abc
:END:
#+TITLE: A note
#+DATE: [2026-08-06]
#+FILETAGS: :seed:

The body starts here.
")
             8))
  ;; No drawer, no blank line: content on line 2.
  (should (= (cerebro-course-note-body-line "#+TITLE: t\nbody\n") 2))
  ;; Front matter only: the include is empty rather than wrong.
  (should (> (cerebro-course-note-body-line "#+TITLE: t\n") 1)))

;; -- Generating the book -----------------------------------------------

(ert-deftest cerebro-course-test-book-includes-instead-of-copying ()
  "Every note becomes an #+INCLUDE with a path relative to the book."
  (let* ((entries (cerebro-course-parse-programme cerebro-course-tests--syllabus))
         (book (plist-get (cerebro-course-book-string
                           "Analysis I" entries #'cerebro-course-tests--resolve
                           "/repo/notes/courses/analysis-1")
                          :text)))
    (should (string-match-p "^#\\+TITLE: Analysis I$" book))
    (should (string-match-p
             "#\\+INCLUDE: \"\\.\\./\\.\\./math/limits\\.org\" :lines \"7-\" :minlevel 3"
             book))
    ;; The note's own title heads its section -- the link description is
    ;; only a fallback, since the note is the authority on its name.
    (should (string-match-p "^\\*\\* Limits and continuity$" book))
    ;; Chapters from the programme's own outline.
    (should (string-match-p "^\\* Continuity$" book))
    (should (string-match-p "^\\* Inner product spaces$" book))
    ;; Nothing of the note's text is copied into the book.
    (should-not (string-match-p "\\\\(" book))))

(ert-deftest cerebro-course-test-book-reports-missing-notes ()
  "A link to a note that is gone is reported *and* visible in the book."
  (let* ((entries (cerebro-course-parse-programme cerebro-course-tests--syllabus))
         (result (cerebro-course-book-string
                  "Analysis I" entries #'cerebro-course-tests--resolve
                  "/repo/notes/courses/analysis-1")))
    (should (equal (plist-get result :missing) '("ccc")))
    (should (string-match-p "MISSING NOTE: id:ccc" (plist-get result :text)))))

(ert-deftest cerebro-course-test-book-says-it-is-generated ()
  "The file warns the reader before they edit it by hand."
  (let ((book (plist-get (cerebro-course-book-string
                          "T" (cerebro-course-parse-programme
                               "* Programme\n- [[id:aaa][One]]\n")
                          #'cerebro-course-tests--resolve "/repo/notes/courses/x")
                         :text)))
    (should (string-match-p "GENERATED" book))
    (should (string-match-p "buffer-read-only" book))))

(ert-deftest cerebro-course-test-title-comes-from-the-course ()
  "`#+COURSE_TITLE:' is the one place a course is named."
  (should (equal (cerebro-course-title cerebro-course-tests--syllabus "fallback")
                 "Analysis I"))
  (should (equal (cerebro-course-title "#+TITLE: x\n" "fallback") "fallback")))

;; -- The real course in this repo --------------------------------------

(ert-deftest cerebro-course-test-repo-course-is-an-index ()
  "The demo course owns no mathematics of its own.
The model is the point: a course directory holds course.org and the
generated book.org, and every chapter is a link into notes/math/."
  (let* ((directory (expand-file-name "notes/courses/analysis-1" cerebro-root))
         (files (directory-files directory nil "\\.org\\'")))
    (should (equal (sort files #'string<) '("book.org" "course.org")))
    (let ((entries (cerebro-course-parse-programme
                    (with-temp-buffer
                      (insert-file-contents (cerebro-course-file directory))
                      (buffer-string)))))
      (should (seq-some (lambda (e) (eq (plist-get e :kind) 'note)) entries)))))

(provide 'cerebro-course-tests)
