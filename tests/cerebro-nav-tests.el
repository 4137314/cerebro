;;; cerebro-nav-tests.el --- ERT tests for moving through the archive -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-nav-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test').
;;
;; The module turns the results graph into movement, so what is worth
;; pinning is the movement itself: that "next" does not find where you
;; already are, that walking a note visits every named result in file
;; order, and that a record's recorded location resolves to a real place.
;;
;; Everything here runs in a `with-temp-buffer', which is only possible
;; because display is kept out of the movement (`cerebro-nav--reveal').
;; That separation was a bug first: `recenter' signals in a buffer nobody
;; is showing, so the walk died on its first success.

(require 'ert)
(require 'cerebro-nav)

(defconst cerebro-nav-tests--note
  "#+TITLE: t

Prose.

#+NAME: def-first
#+begin_definition
A.
#+end_definition

#+DEPENDS: def-first
#+NAME: thm-second
#+begin_theorem
B.
#+end_theorem

#+begin_proof
Because.
#+end_proof

#+NAME: cor-third
#+begin_corollary
C.
#+end_corollary
"
  "A note with three named results, in a known order.")

(defmacro cerebro-nav-tests--in-note (&rest body)
  "Run BODY in an Org buffer holding `cerebro-nav-tests--note'."
  `(with-temp-buffer
     (insert cerebro-nav-tests--note)
     (org-mode)
     (goto-char (point-min))
     ,@body))

;; -- Locations ----------------------------------------------------------

(ert-deftest cerebro-nav-test-candidate-leads-with-the-name ()
  "The completion line puts what you type near the front.
Type first (it groups), then the name (it is what you know), then the
context that tells two identically named results apart."
  ;; `case-fold-search' is t by default, and would match the heading
  ;; marker against a letter of "theorem" -- bound off so the positions
  ;; compared are the ones intended.
  (let* ((case-fold-search nil)
         (line (cerebro-nav-candidate
                '(:type "theorem" :name "thm-x" :heading "CONTEXT"
                  :file "notes/math/a.org"))))
    (should (string-match-p "\\`theorem" line))
    (should (< (string-match "thm-x" line) (string-match "CONTEXT" line)))))

(ert-deftest cerebro-nav-test-location-is-absolute ()
  "`:file' is stored relative to the repository, so jumping expands it.
A report is readable with relative paths and `find-file' is not."
  (let ((where (cerebro-nav-record-location
                '(:name "thm-x" :file "notes/math/a.org" :line 42))))
    (should (file-name-absolute-p (car where)))
    (should (string-suffix-p "notes/math/a.org" (car where)))
    (should (= (cdr where) 42)))
  ;; A record with no file has no location, rather than one pointing at
  ;; the repository root.
  (should-not (cerebro-nav-record-location '(:name "thm-x"))))

;; -- Moving inside a note -----------------------------------------------

(ert-deftest cerebro-nav-test-walks-every-result-in-order ()
  "`next' visits each named result once, in the order they appear."
  (cerebro-nav-tests--in-note
   (let (seen)
     (while (cerebro-nav--move 1)
       (push (cerebro-nav-result-at-point) seen))
     (should (equal (nreverse seen)
                    '("def-first" "thm-second" "cor-third"))))))

(ert-deftest cerebro-nav-test-next-does-not-find-where-you-are ()
  "Sitting on a `#+NAME:' and pressing `next' must move.
Searching forward from point rather than from end-of-line would match
the current line again, and the key would read as broken."
  (cerebro-nav-tests--in-note
   (cerebro-nav--move 1)
   (should (equal (cerebro-nav-result-at-point) "def-first"))
   (should (equal (cerebro-nav--move 1) "thm-second"))))

(ert-deftest cerebro-nav-test-walks-backwards-too ()
  "From the end, `previous' returns the last result and then the others."
  (cerebro-nav-tests--in-note
   (goto-char (point-max))
   (should (equal (cerebro-nav--move -1) "cor-third"))
   (should (equal (cerebro-nav--move -1) "thm-second"))))

(ert-deftest cerebro-nav-test-movement-stops-at-the-edges ()
  "Past the last result there is nothing, and that is nil, not an error."
  (cerebro-nav-tests--in-note
   (goto-char (point-max))
   (should-not (cerebro-nav--move 1))))

(ert-deftest cerebro-nav-test-result-at-point-looks-upward ()
  "Inside a block, the result you are in is the `#+NAME:' above it."
  (cerebro-nav-tests--in-note
   (search-forward "Because.")
   (should (equal (cerebro-nav-result-at-point) "thm-second")))
  ;; Above every name there is none, rather than the first one.
  (cerebro-nav-tests--in-note
   (search-forward "Prose.")
   (should-not (cerebro-nav-result-at-point))))

(ert-deftest cerebro-nav-test-movement-needs-an-org-buffer ()
  "The commands are about Org structure and say so rather than misfiring."
  (with-temp-buffer
    (fundamental-mode)
    (should-error (cerebro-nav--move 1) :type 'user-error)))

;; -- Writing a dependency ----------------------------------------------

(ert-deftest cerebro-nav-test-insert-depends-writes-the-convention ()
  "The line is `#+DEPENDS: a, b' on its own line, above point.
Order matters in this repository: `#+DEPENDS:' goes ABOVE `#+NAME:', so
it is inserted at the beginning of the current line."
  (with-temp-buffer
    (insert "#+NAME: thm-x\n")
    (goto-char (point-min))
    (cerebro-nav-insert-depends '("def-a" "thm-b"))
    (should (equal (buffer-string) "#+DEPENDS: def-a, thm-b\n#+NAME: thm-x\n"))))

(ert-deftest cerebro-nav-test-insert-depends-nothing-is-a-no-op ()
  "Choosing nothing writes nothing -- not an empty `#+DEPENDS:' line,
which the linter would then have to have an opinion about."
  (with-temp-buffer
    (insert "#+NAME: thm-x\n")
    (goto-char (point-min))
    (cerebro-nav-insert-depends nil)
    (should (equal (buffer-string) "#+NAME: thm-x\n"))))

(provide 'cerebro-nav-tests)
