;;; cerebro-course-tests.el --- ERT tests for courses-as-index -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-course-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test').
;;
;; A course is one file, and the composer is the only thing standing
;; between it and a document that fails to compile. Three things are
;; worth pinning down, and all three are silent failures:
;;
;;   - the programme must be read as a *subtree*: a link in the
;;     description or the bibliography is not part of the course;
;;   - the include must start below the note's front matter, or the
;;     second `#+TITLE:' spliced into the middle of the document
;;     silently overrides its own title (and the note's tags, :ID: and
;;     #+HASH: land in the text);
;;   - a link to a note that no longer exists must be *reported*, not
;;     quietly dropped -- a chapter missing from a book is not something
;;     you notice by reading the LaTeX log. (Collecting them through a
;;     symbol the caller named is what broke this the first time: the
;;     file is lexically bound, so the first missing note crashed the
;;     composer instead of being reported by it.)
;;
;; The one impure step (an ID -> a file) is injected, so none of this
;; needs a note database.

(require 'ert)
(require 'cerebro-course)
(require 'cerebro-latex) ;; the outputs must name real export profiles

(defconst cerebro-course-tests--syllabus "\
#+TITLE: Analysis I -- syllabus
#+COURSE_TITLE: Analysis I
#+DATE: [2026-08-07 Fri]

* Description
Some prose, and a link that is NOT part of the programme:
[[id:not-a-chapter][Something else]]

* Programme
** Continuity
- [[id:aaa][Limits and continuity]]
** Inner product spaces
- [[id:bbb][Inner product space]]
- [[id:ccc][Cauchy--Schwarz inequality]]

* Appendices
- [[id:bbb][Inner product space]]

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

;; -- Composing the document ---------------------------------------------

(ert-deftest cerebro-course-test-composition-includes-instead-of-copying ()
  "Every note becomes an #+INCLUDE with a path relative to the composed
file. Nothing of a note's text is ever copied into a course."
  (let ((text (plist-get (cerebro-course-compose
                          cerebro-course-tests--syllabus
                          #'cerebro-course-tests--resolve
                          "/repo/notes/courses/.build")
                         :text)))
    ;; The course's own front matter travels with it -- a composed
    ;; document with no title is a book by nobody.
    (should (string-match-p "^#\\+TITLE: Analysis I -- syllabus$" text))
    (should (string-match-p "^#\\+COURSE_TITLE: Analysis I$" text))
    (should (string-match-p
             "#\\+INCLUDE: \"\\.\\./\\.\\./math/limits\\.org\" :lines \"7-\" :minlevel 3"
             text))
    ;; The note's own title heads its section -- the link description is
    ;; only a fallback, since the note is the authority on its name.
    (should (string-match-p "^\\*\\* Limits and continuity$" text))
    ;; Chapters from the programme's own outline.
    (should (string-match-p "^\\* Continuity$" text))
    (should (string-match-p "^\\* Inner product spaces$" text))
    ;; Nothing of the note's text is copied in.
    (should-not (string-match-p "\\\\(" text))))

(ert-deftest cerebro-course-test-appendices-are-lettered ()
  "An `* Appendices' section is composed after \\appendix, so those
chapters are lettered rather than numbered -- and it is the COURSE that
says so, not any note."
  (let ((text (plist-get (cerebro-course-compose
                          cerebro-course-tests--syllabus
                          #'cerebro-course-tests--resolve
                          "/repo/notes/courses/.build")
                         :text)))
    (should (string-match-p "#\\+LATEX: .appendix" text))
    ;; ...and after the programme, not before it.
    (should (< (string-match "\\* Continuity" text)
               (string-match "#\\+LATEX: .appendix" text))))
  ;; A course with no appendices emits no \appendix at all.
  (let ((text (plist-get (cerebro-course-compose
                          "#+TITLE: T\n* Programme\n- [[id:aaa][One]]\n"
                          #'cerebro-course-tests--resolve "/repo/x")
                         :text)))
    (should-not (string-match-p "appendix" text))))

(ert-deftest cerebro-course-test-composition-reports-missing-notes ()
  "A link to a note that is gone is reported *and* visible in the text."
  (let ((result (cerebro-course-compose
                 cerebro-course-tests--syllabus
                 #'cerebro-course-tests--resolve
                 "/repo/notes/courses/.build")))
    (should (equal (plist-get result :missing) '("ccc")))
    (should (string-match-p "MISSING NOTE: id:ccc" (plist-get result :text)))))

(ert-deftest cerebro-course-test-composition-says-it-is-derived ()
  "The composed file warns whoever opens it in a build directory."
  (let ((text (plist-get (cerebro-course-compose
                          "#+TITLE: T\n* Programme\n- [[id:aaa][One]]\n"
                          #'cerebro-course-tests--resolve "/repo/x")
                         :text)))
    (should (string-match-p "COMPOSED" text))
    (should (string-match-p "buffer-read-only" text))))

(ert-deftest cerebro-course-test-only-the-syllabus-is-the-file-itself ()
  "The syllabus IS the course file -- two pages a person wrote. Every
other profile compiles the composition of it."
  (let ((course "/repo/notes/courses/analysis-A.org"))
    (should (equal (cerebro-course-composed-file course 'handbook)
                   "/repo/notes/courses/.build/analysis-A-handbook.org"))
    ;; And a build never nests: the composed file's own build directory
    ;; is the one it already sits in.
    (should (equal (cerebro-latex-build-dir
                    "/repo/notes/courses/.build/analysis-A-handbook.org")
                   "/repo/notes/courses/.build"))))

(ert-deftest cerebro-course-test-title-comes-from-the-course ()
  "`#+COURSE_TITLE:' is the one place a course is named."
  (should (equal (cerebro-course-title cerebro-course-tests--syllabus "fallback")
                 "Analysis I"))
  (should (equal (cerebro-course-title "#+TITLE: x\n" "fallback") "fallback")))

;; -- The real course in this repo --------------------------------------

(ert-deftest cerebro-course-test-repo-course-is-one-file ()
  "The real course owns no mathematics of its own, and is ONE file.
The model is the point: notes/courses/<slug>.org indexes notes/math/,
and there is no second, generated file to keep in step with it."
  (let ((course (expand-file-name "notes/courses/analysis-A.org" cerebro-root)))
    (should (file-readable-p course))
    (should (cerebro-course-file-p course))
    (should-not (file-directory-p
                 (expand-file-name "notes/courses/analysis-A" cerebro-root)))
    (let ((text (with-temp-buffer (insert-file-contents course) (buffer-string))))
      (should (seq-some (lambda (e) (eq (plist-get e :kind) 'note))
                        (cerebro-course-parse-programme text)))
      ;; A syllabus of topics to study: no examination apparatus.
      (should-not (string-match-p "(?i)assessment" text)))))

(ert-deftest cerebro-course-test-the-readme-is-not-a-course ()
  "Being in notes/courses/ does not make a file a course.

notes/courses/README.org is this repository explaining the directory.
It answered yes to `cerebro-course-file-p', which put it in the `C-c e
o' picker and let `C-c e c' offer to build four documents out of it --
the first of which, the syllabus, would have compiled, because a
syllabus is just the course file typeset."
  (let ((readme (expand-file-name "notes/courses/README.org" cerebro-root)))
    (should (file-readable-p readme))
    (should-not (cerebro-course-file-p readme)))
  ;; A composed build product is not a course either.
  (should-not (cerebro-course-file-p
               (expand-file-name "notes/courses/.build/analysis-A-handbook.org"
                                 cerebro-root)))
  (should (cerebro-course-file-p
           (expand-file-name "notes/courses/analysis-A.org" cerebro-root))))

(ert-deftest cerebro-course-test-a-course-has-four-documents ()
  "One per audience: what the course is, what I say, what they see,
what they keep. The table is also what bin/cerebro-course-export
iterates, so a fifth entry here without one there is a document Emacs
offers to build and the CLI cannot."
  (should (equal (mapcar #'car cerebro-course-outputs)
                 '(syllabus lecture slides handbook)))
  ;; Every one of them names a real export profile, and each says what
  ;; it is for -- that string is what `C-c e c' shows.
  (dolist (row cerebro-course-outputs)
    (should (cerebro-latex--profile (car row)))
    (should (stringp (plist-get (cdr row) :what)))))

(provide 'cerebro-course-tests)
