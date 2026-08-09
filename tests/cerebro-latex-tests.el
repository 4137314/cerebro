;;; cerebro-latex-tests.el --- ERT tests for the parametric export pipeline -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-latex-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test'). Deliberately does not exercise an actual LaTeX
;; compile -- that is what `make ci''s profile-matrix export does, and
;; needs a real TeX install. These tests are for the orchestration
;; logic itself: profile/doctype composition, the block-stripping and
;; single-target parse-tree filters, and error handling -- all
;; reachable without Org-roam or Guix.

(require 'ert)
(require 'cerebro-latex)

(ert-deftest cerebro-latex-test-known-profiles-resolve ()
  (dolist (name '(syllabus lecture slides handbook conjecture single))
    (should (cerebro-latex--profile name))))

(ert-deftest cerebro-latex-test-there-are-only-four-documents ()
  "Four course documents plus `single', and nothing else.
The table was fourteen entries once, most of which nobody built. Adding
one back is a decision, not an accident -- which is what this test makes
it."
  (should (equal (sort (mapcar #'car cerebro-latex-profiles) #'string<)
                 '(conjecture handbook lecture single slides syllabus))))

(ert-deftest cerebro-latex-test-every-profile-composes ()
  ;; Each profile must reference a real content mode and a real doctype
  ;; -- guards against a typo in the profiles alist.
  (dolist (entry cerebro-latex-profiles)
    (let ((p (cdr entry)))
      (should (cerebro-latex--content-mode (plist-get p :content)))
      (should (cerebro-latex--doctype (plist-get p :doctype))))))

(ert-deftest cerebro-latex-test-unknown-profile-errors ()
  (should-error (cerebro-latex--profile 'no-such-profile)))

(ert-deftest cerebro-latex-test-unknown-content-mode-errors ()
  (should-error (cerebro-latex--content-mode 'no-such-mode)))

(ert-deftest cerebro-latex-test-unknown-doctype-errors ()
  (should-error (cerebro-latex--doctype 'no-such-doctype)))

(ert-deftest cerebro-latex-test-class-options-composition ()
  ;; The proofs and solutions toggles, then the doctype's own option.
  (should (equal (cerebro-latex--class-options 'article t t) "[proofs,solutions,article]"))
  (should (equal (cerebro-latex--class-options 'article nil nil) "[noproofs,nosolutions,article]"))
  (should (equal (cerebro-latex--class-options 'article t nil) "[proofs,nosolutions,article]"))
  ;; The handbook also asks its class for an analytical index.
  (should (equal (cerebro-latex--class-options 'book t t) "[proofs,solutions,book,index]"))
  (should (equal (cerebro-latex--class-options 'syllabus t t) "[proofs,solutions,syllabus]"))
  ;; beamer's :class-options is "" -- no trailing comma/empty component.
  (should (equal (cerebro-latex--class-options 'beamer t t) "[proofs,solutions]")))

(ert-deftest cerebro-latex-test-slides-turn-the-proofs-off ()
  "The deck keeps only statements, so the class must be told there are
no proofs in it -- otherwise cerebro-beamer.cls typesets a `Proof'
environment for a body that the parse-tree filter already removed."
  (let* ((profile (cerebro-latex--profile 'slides))
         (content (cerebro-latex--content-mode (plist-get profile :content)))
         (only (plist-get content :only-blocks)))
    (should-not (member "proof" only))
    (should (member "theorem" only))
    (should (plist-get content :prune-prose))))

(defmacro cerebro-latex-test--with-parsed-org (text &rest body)
  "Parse TEXT as Org and run BODY with TREE bound to the parse tree."
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,text)
     (org-mode)
     (let ((tree (org-element-parse-buffer)))
       ,@body)))

(ert-deftest cerebro-latex-test-strip-blocks-removes-only-named-types ()
  (cerebro-latex-test--with-parsed-org
      "#+begin_definition\nkeep\n#+end_definition\n\n#+begin_proof\ndrop\n#+end_proof\n"
    (let ((cerebro-latex--exclude-blocks '("proof")))
      (cerebro-latex--strip-blocks tree nil nil))
    (let ((types (org-element-map tree 'special-block
                   (lambda (b) (org-element-property :type b)))))
      (should (member "definition" types))
      (should-not (member "proof" types)))))

(ert-deftest cerebro-latex-test-strip-blocks-noop-when-nil ()
  (cerebro-latex-test--with-parsed-org
      "#+begin_proof\nkeep\n#+end_proof\n"
    (let ((cerebro-latex--exclude-blocks nil))
      (cerebro-latex--strip-blocks tree nil nil))
    (should (org-element-map tree 'special-block
              (lambda (b) (equal (org-element-property :type b) "proof"))))))

(ert-deftest cerebro-latex-test-extract-single-keeps-target-and-adjacent-proof ()
  (cerebro-latex-test--with-parsed-org
      (concat "#+begin_definition\ndrop me\n#+end_definition\n\n"
              "#+NAME: my-thm\n#+begin_theorem\nkeep\n#+end_theorem\n\n"
              "#+begin_proof\nkeep too\n#+end_proof\n\n"
              "#+begin_remark\ndrop me too\n#+end_remark\n")
    (let ((cerebro-latex--single-target "my-thm"))
      (cerebro-latex--extract-single tree nil nil))
    (let ((types (org-element-map tree 'special-block
                   (lambda (b) (org-element-property :type b)))))
      (should (equal (sort (copy-sequence types) #'string<) '("proof" "theorem"))))))

(ert-deftest cerebro-latex-test-extract-single-errors-on-missing-target ()
  (cerebro-latex-test--with-parsed-org
      "#+begin_theorem\nno name here\n#+end_theorem\n"
    (let ((cerebro-latex--single-target "does-not-exist"))
      (should-error (cerebro-latex--extract-single tree nil nil)))))

(ert-deftest cerebro-latex-test-export-requires-target-for-single ()
  (should-error
   (cerebro-latex-export-to-pdf "/nonexistent/does-not-matter.org" 'single nil)))

(ert-deftest cerebro-latex-test-keep-only-blocks ()
  ;; A problem sheet: keep only exercise blocks, drop the surrounding
  ;; theory (definition/theorem/proof) special blocks.
  (cerebro-latex-test--with-parsed-org
      (concat "#+begin_definition\ndrop\n#+end_definition\n\n"
              "#+begin_exercise\nkeep\n#+end_exercise\n\n"
              "#+begin_theorem\ndrop\n#+end_theorem\n\n"
              "#+begin_proof\ndrop\n#+end_proof\n")
    (let ((cerebro-latex--only-blocks '("exercise")))
      (cerebro-latex--keep-only-blocks tree nil nil))
    (let ((types (org-element-map tree 'special-block
                   (lambda (b) (org-element-property :type b)))))
      (should (equal types '("exercise"))))))

(ert-deftest cerebro-latex-test-keep-only-blocks-noop-when-nil ()
  (cerebro-latex-test--with-parsed-org
      "#+begin_theorem\nkeep\n#+end_theorem\n"
    (let ((cerebro-latex--only-blocks nil))
      (cerebro-latex--keep-only-blocks tree nil nil))
    (should (org-element-map tree 'special-block
              (lambda (b) (equal (org-element-property :type b) "theorem"))))))

(ert-deftest cerebro-latex-test-conjectures-are-two-column ()
  "notes/conjectures/ typesets as a two-column article -- the same
class, macros and theorem suite as everything else, with KOMA's own
`twocolumn' passed through cerebro.cls."
  (let ((options (cerebro-latex--class-options 'twocolumn t t)))
    (should (string-match-p "twocolumn" options))
    (should (string-match-p "article" options)))
  (should (equal (plist-get (cerebro-latex--doctype 'twocolumn) :class) "cerebro")))

(ert-deftest cerebro-latex-test-only-the-handbook-has-an-index ()
  "The analytical index is a property of the bound book, and the CLASS
decides whether there is one -- so a note carrying index entries still
compiles as a lecture sheet or a deck, where \\index is inert."
  (should (string-match-p "index" (cerebro-latex--class-options 'book t t)))
  (dolist (doctype '(article syllabus twocolumn beamer))
    (should-not (string-match-p "index" (cerebro-latex--class-options doctype t t)))))

(ert-deftest cerebro-latex-test-index-entries-come-from-result-names ()
  "Naming a definition is what puts it in the index -- there is no
second place to write it down."
  (should (equal (cerebro-latex-index-entry "def-supremum") "supremum"))
  (should (equal (cerebro-latex-index-entry "thm-monotone-convergence")
                 "monotone convergence"))
  (should (equal (cerebro-latex-index-entry "conj-goldbach") "goldbach"))
  ;; A name with no kind prefix, or none at all, contributes nothing
  ;; rather than an entry called after a file.
  (should-not (cerebro-latex-index-entry "supremum"))
  (should-not (cerebro-latex-index-entry nil)))

(ert-deftest cerebro-latex-test-index-marks-only-real-results ()
  "A theorem is indexed; a remark is apparatus and is not."
  (cerebro-latex-test--with-parsed-org
      (concat "#+NAME: thm-x\n#+begin_theorem\nS\n#+end_theorem\n\n"
              "#+NAME: rem-y\n#+begin_remark\nR\n#+end_remark\n")
    (cerebro-latex--index-named-results tree nil nil)
    (let ((text (org-element-interpret-data tree)))
      (should (string-match-p "\\\\index{x}" text))
      (should-not (string-match-p "\\\\index{y}" text)))))

(ert-deftest cerebro-latex-test-handbook-is-chaptered ()
  "The handbook's top level is a chapter of the programme.
Mapped to \\section instead, every result in a course book was numbered
`0.1.1' -- sections before a chapter that never comes."
  (should (equal (plist-get (cerebro-latex--doctype 'book) :class)
                 "cerebro-chaptered"))
  (should (equal (plist-get (cerebro-latex--doctype 'article) :class)
                 "cerebro")))

(ert-deftest cerebro-latex-test-prune-prose-keeps-statements-and-lists ()
  "Prose under a heading goes; a list and the blocks stay.
`:prune-prose' is what stops a slide from being a wall of text, and it
has to be surgical: the paragraph *inside* a theorem block is the
theorem."
  (cerebro-latex-test--with-parsed-org
      (concat "* Heading\n\nLoose prose that should go.\n\n"
              "- a list item that stays\n\n"
              "#+begin_theorem\nthe statement itself\n#+end_theorem\n")
    (let ((cerebro-latex--prune-prose t))
      (cerebro-latex--prune-prose-paragraphs tree nil nil))
    (let ((text (org-element-interpret-data tree)))
      (should-not (string-match-p "Loose prose" text))
      (should (string-match-p "a list item that stays" text))
      (should (string-match-p "the statement itself" text)))))

(ert-deftest cerebro-latex-test-example-blocks-are-filtered-like-blocks ()
  "`#+begin_example' is Org's own element type, not a special block --
so a profile that drops examples has to ask Org what it thinks the
element is. `lecture' excluded \"example\" for months and every
`#+begin_example' in the archive sailed straight through it."
  (cerebro-latex-test--with-parsed-org
      "#+begin_example\ndrop me\n#+end_example\n\n#+begin_definition\nkeep\n#+end_definition\n"
    (let ((cerebro-latex--exclude-blocks '("example")))
      (cerebro-latex--strip-blocks tree nil nil))
    (should-not (org-element-map tree 'example-block #'identity))
    (should (org-element-map tree 'special-block #'identity))))


;; -- Title-page metadata ------------------------------------------------

(ert-deftest cerebro-latex-test-date-is-readable-on-a-title-page ()
  "An Org timestamp becomes a date a person would write.
`[2026-07-29 Wed 13:55]' is right in a file and wrong on a title page;
anything that is not a timestamp is left alone, because a note may
legitimately say `Autumn 2026'."
  (should (equal (cerebro-latex-format-date "[2026-07-29 Wed 13:55]") "29 July 2026"))
  (should (equal (cerebro-latex-format-date "<2026-01-03 Sat>") " 3 January 2026"))
  (should (equal (cerebro-latex-format-date "Autumn 2026") "Autumn 2026"))
  ;; No date at all: today, rather than an empty title page.
  (should-not (string-empty-p (string-trim (cerebro-latex-format-date nil)))))

(ert-deftest cerebro-latex-test-every-class-in-the-family-takes-the-metadata ()
  "The \\cerebro... macros are emitted for every doctype, which is only
safe because every class in the family defines them. Adding a doctype
whose class does not is `Undefined control sequence \\cerebroauthor' --
caught by `make export-matrix', which is why the invariant is stated
here as well."
  (dolist (doctype cerebro-latex-doctypes)
    (should (member (plist-get (cdr doctype) :class)
                    '("cerebro" "cerebro-chaptered" "cerebro-beamer"))))
  (should (cerebro-latex-metadata-header "Ada" "v1" "S" "D")))

(ert-deftest cerebro-latex-test-beamer-export-cannot-overflow-a-frame ()
  "The two settings that keep a deck from colliding with itself: one
frame per note (not per chapter), and a frame that does not fit is
broken across slides instead of drawn past the edge."
  (let ((plist (cerebro-latex--beamer-plist)))
    (should (= (plist-get plist :headline-levels) 2))
    (should (equal (plist-get plist :beamer-frame-default-options)
                   "allowframebreaks"))))

(ert-deftest cerebro-latex-test-figures-are-fitted-on-a-deck-only ()
  "A page-sized tikzpicture on a 12.8cm slide is drawn over whatever
comes next; \\cerebrofit shrinks it to the frame. The same figure in the
handbook is meant to be page sized and is left alone."
  (let ((figure "\\begin{tikzpicture}\n\\draw (0,0) -- (1,1);\n\\end{tikzpicture}"))
    (should (string-match-p "cerebrofit"
                            (cerebro-latex--beamer-fit-environment figure 'beamer nil)))
    (should (equal (cerebro-latex--beamer-fit-environment figure 'latex nil) figure))))

(ert-deftest cerebro-latex-test-metadata-header-omits-what-is-empty ()
  "Only the macros there is something to say with are emitted."
  (let ((header (cerebro-latex-metadata-header "Ada Lovelace" "v1-2-g3f" "")))
    (should (string-match-p "\\\\cerebroauthor{Ada Lovelace}" header))
    (should (string-match-p "\\\\cerebroversion{v1-2-g3f}" header))
    (should-not (string-match-p "cerebrosubject" header)))
  (should (equal (cerebro-latex-metadata-header nil nil nil) "")))

(ert-deftest cerebro-latex-test-author-is-a-person ()
  "The title page carries a name, not a git account handle.
`user.name' in this repository is a forge account (`4137314'), which is
exactly the wrong thing to print on a document handed to someone."
  (should (stringp (cerebro-latex-author)))
  (should (string-match-p " " (cerebro-latex-author))))

;; -- Where a build happens ----------------------------------------------

(ert-deftest cerebro-latex-test-build-output-is-out-of-the-way ()
  "Every product of a compile lands in .build/ beside the source.
A directory of mathematics should contain mathematics: `ls notes/math/'
answering with .aux and .fls files is how a source tree stops being
readable."
  (should (equal (cerebro-latex-build-dir "/repo/notes/math/x.org")
                 "/repo/notes/math/.build"))
  (should (equal (cerebro-latex-output-file "/repo/notes/math/x.org")
                 "/repo/notes/math/.build/x.pdf"))
  (should (equal (cerebro-latex-output-file "/repo/notes/math/x.org" "log")
                 "/repo/notes/math/.build/x.log")))

;; -- `#+begin_example' is a mathematical example ------------------------

(ert-deftest cerebro-latex-test-example-blocks-become-the-environment ()
  "Org's verbatim wrapper is swapped for the theorem suite's `example'.
Without this a note's example exported as literal source -- backslashes
and all -- in a typewriter face, which is what it did until this filter
existed."
  (let ((output (cerebro-latex-example-filter
                 "\\begin{verbatim}\nLet \\(x\\) be real.\n\\end{verbatim}\n"
                 'latex nil)))
    (should (string-match-p "\\\\begin{example}" output))
    (should (string-match-p "\\\\end{example}" output))
    (should-not (string-match-p "verbatim" output))
    ;; The body is untouched: it is LaTeX now, not escaped text.
    (should (string-match-p "Let \\\\(x\\\\) be real" output)))
  ;; Both ends or neither: replacing one leaves TeX scanning for a
  ;; delimiter that no longer exists.
  (should-not (cerebro-latex-example-filter nil 'latex nil)))

(provide 'cerebro-latex-tests)
