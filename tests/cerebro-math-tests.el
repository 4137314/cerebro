;;; cerebro-math-tests.el --- ERT tests for note creation -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-math-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test').
;;
;; These commands write files into the permanent archive, so what they
;; generate has to satisfy the note conventions *by construction* -- the
;; whole point of generating a note rather than typing one is that the
;; things that "fail silently" (CLAUDE.md) cannot be got wrong:
;;
;;   - `#+NAME:' sits directly above its `#+begin_' line, with nothing in
;;     between (anything there detaches the name and breaks the `single'
;;     export without an error);
;;   - the name carries the prefix the results layer reads (`thm-'...);
;;   - the block is an environment the LaTeX theorem suite actually
;;     defines -- a `#+begin_claim' would export to an undefined
;;     environment and fail the compile;
;;   - a note with no title is still a *valid, unique* note, because
;;     naming things later is the whole reason the quick capture exists.
;;
;; Everything here is pure string work: no file is created.

(require 'ert)
(require 'cerebro-math)

;; -- Slugs --------------------------------------------------------------

(ert-deftest cerebro-math-test-slug ()
  "Titles become the kebab-case slugs the rest of the repo uses."
  (should (equal (cerebro-math-slug "Uniqueness of limits") "uniqueness-of-limits"))
  (should (equal (cerebro-math-slug "Cauchy--Schwarz inequality!")
                 "cauchy-schwarz-inequality"))
  (should (equal (cerebro-math-slug "  Hilbert   space  ") "hilbert-space"))
  ;; Nothing usable is nil, not the empty string: the caller switches on
  ;; it to decide between a name and a hash.
  (should-not (cerebro-math-slug ""))
  (should-not (cerebro-math-slug "   "))
  (should-not (cerebro-math-slug "!!!")))

;; -- File names ---------------------------------------------------------

(ert-deftest cerebro-math-test-file-name-from-title ()
  "A titled note gets the timestamp-slug name used everywhere else."
  (let ((time (encode-time 0 30 9 6 8 2026)))
    (should (equal (cerebro-math-file-name "Uniqueness of limits"
                                           "6EDB4C0A-1111-2222-3333-444455556666" time)
                   "20260806093000-uniqueness-of-limits.org"))))

(ert-deftest cerebro-math-test-file-name-falls-back-to-the-id ()
  "An untitled note is named from its own ID, and is still unique.
This is what lets you capture an idea before you know what it is called:
the note exists, is linkable by :ID:, and can be renamed -- or never
renamed, since nothing resolves a note by file name."
  (let* ((time (encode-time 0 30 9 6 8 2026))
         (name (cerebro-math-file-name "" "6EDB4C0A-1111-2222-3333-444455556666" time)))
    (should (equal name "20260806093000-6edb4c0a.org"))
    ;; Different notes made in the same second still differ.
    (should-not (equal name (cerebro-math-file-name
                             "" "99999999-1111-2222-3333-444455556666" time)))))

;; -- Result names -------------------------------------------------------

(ert-deftest cerebro-math-test-result-name-prefixes ()
  "The `#+NAME' carries the prefix the results layer and readers expect."
  (should (equal (cerebro-math-result-name 'theorem "Heine Borel") "thm-heine-borel"))
  (should (equal (cerebro-math-result-name 'definition "Compact set") "def-compact-set"))
  (should (equal (cerebro-math-result-name 'lemma "Zorn") "lem-zorn"))
  ;; A plain note is not a result: no name, so it never appears in the
  ;; dependency graph as something citable.
  (should-not (cerebro-math-result-name 'note "Some thoughts"))
  ;; ...and neither does an untitled one, which has nothing to be called.
  (should-not (cerebro-math-result-name 'theorem "")))

;; -- The generated note -------------------------------------------------

(ert-deftest cerebro-math-test-note-is-born-classified ()
  "Every note comes with the front matter the graph and linter expect."
  (let ((note (cerebro-math-note-string 'theorem "Uniqueness of limits" "abc-123")))
    (should (string-match-p "^:PROPERTIES:\n:ID:       abc-123\n:END:" note))
    (should (string-match-p "^#\\+TITLE: Uniqueness of limits$" note))
    (should (string-match-p "^#\\+FILETAGS: :seed:$" note))
    (should (string-match-p "^#\\+MSC: *$" note))))

(ert-deftest cerebro-math-test-note-name-touches-its-block ()
  "`#+NAME:' is on the line directly above `#+begin_' -- the silent one.
Org only attaches an affiliated keyword to what immediately follows it;
one blank line in between and the block loses its name, with no error and
no visible difference until the `single' export finds nothing to keep."
  (let ((note (cerebro-math-note-string 'theorem "Heine Borel" "id")))
    (should (string-match-p "^#\\+NAME: thm-heine-borel\n#\\+begin_theorem$" note))))

(ert-deftest cerebro-math-test-note-blocks-match-the-kind ()
  "Statements that get proved come with a proof block; the others do not."
  (should (string-match-p "#\\+begin_proof"
                          (cerebro-math-note-string 'theorem "T" "id")))
  (should (string-match-p "#\\+begin_proof"
                          (cerebro-math-note-string 'lemma "L" "id")))
  (should-not (string-match-p "#\\+begin_proof"
                              (cerebro-math-note-string 'definition "D" "id")))
  (should-not (string-match-p "#\\+begin_proof"
                              (cerebro-math-note-string 'remark "R" "id"))))

(ert-deftest cerebro-math-test-untitled-note-is-still-valid ()
  "A note captured without a title is a complete note, just unnamed."
  (let ((note (cerebro-math-note-string 'theorem "" "id")))
    (should (string-match-p "^#\\+TITLE: untitled$" note))
    (should (string-match-p "#\\+begin_theorem" note))
    ;; No `#+NAME:' line at all -- better than a name like `thm-' that
    ;; would collide with the next untitled theorem in the results graph.
    (should-not (string-match-p "#\\+NAME:" note))))

(ert-deftest cerebro-math-test-note-carries-the-body ()
  "An extracted statement lands inside the block, not next to it."
  (let ((note (cerebro-math-note-string 'definition "Convex set" "id"
                                        "A set \\(C\\) is convex when...")))
    (should (string-match-p
             "#\\+begin_definition\nA set \\\\(C\\\\) is convex when\\.\\.\\.\n#\\+end_definition"
             note))))

(ert-deftest cerebro-math-test-note-has-no-naked-dollar ()
  "Nothing generated here can trip the linter's `$' rule."
  (dolist (kind (mapcar #'car cerebro-math-kinds))
    (should-not (string-match-p "\\$" (cerebro-math-note-string kind "T" "id")))))

;; -- The table itself ---------------------------------------------------

(ert-deftest cerebro-math-test-kinds-are-consistent ()
  "Distinct keys and distinct name prefixes: a collision would silently
bind two kinds to one key, or give two kinds of result the same prefix."
  (let ((keys (delq nil (mapcar (lambda (row) (plist-get (cdr row) :key))
                                cerebro-math-kinds)))
        (prefixes (delq nil (mapcar (lambda (row) (plist-get (cdr row) :prefix))
                                    cerebro-math-kinds))))
    (should (equal keys (seq-uniq keys)))
    (should (equal prefixes (seq-uniq prefixes)))))

(ert-deftest cerebro-math-test-blocks-exist-in-the-latex-suite ()
  "Every block this module writes is an environment the classes define.
The generated note compiles or it does not: a `#+begin_claim' would
export to \\begin{claim} and fail LaTeX, and the failure would arrive at
export time, in a note written weeks earlier."
  (let* ((sty (expand-file-name "latex/cerebro-theorems.sty" cerebro-root))
         (contents (with-temp-buffer (insert-file-contents sty) (buffer-string))))
    (dolist (row cerebro-math-kinds)
      (when-let* ((block (plist-get (cdr row) :block)))
        (should (string-match-p (format "newtheorem\\*?{%s}" block) contents))))))

(provide 'cerebro-math-tests)
