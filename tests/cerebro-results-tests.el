;;; cerebro-results-tests.el --- ERT tests for the results layer -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-results-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test'). The parsing and graph algorithms in cerebro-results.el
;; are pure (strings and alists in, results out -- no Org, no Org-roam, no
;; Guix), exactly like cerebro-graph.el, so they are exercised directly.
;; This is the safety net for the checks the linter enforces graph-wide
;; (bin/notes-lint.el): dangling dependencies, cycles, and duplicate names.
;;
;; Convention under test: #+DEPENDS goes ABOVE #+NAME, and #+NAME stays
;; directly on top of the #+begin_ line (see cerebro-results.el for why --
;; org-element detaches a #+NAME separated from its block by the
;; non-affiliated #+DEPENDS keyword, and the parser matches that so the
;; two views can never disagree).

(require 'ert)
(require 'cl-lib)
(require 'cerebro-results)

(defconst cerebro-results-tests--doc
  (concat
   "* Foundations\n"
   "#+NAME: ax-completeness\n"
   "#+begin_axiom\nEvery bounded-above set has a sup.\n#+end_axiom\n\n"
   "#+NAME: def-convergence\n"
   "#+begin_definition\nA sequence converges if ...\n#+end_definition\n\n"
   "* Theorems\n"
   "#+DEPENDS: def-convergence\n"
   "#+NAME: thm-uniqueness\n"
   "#+begin_theorem\nLimits are unique.\n#+end_theorem\n\n"
   "#+DEPENDS: def-convergence, ax-completeness\n"
   "#+NAME: thm-mct\n"
   "#+begin_theorem\nMonotone convergence.\n#+end_theorem\n\n"
   ;; An unnamed block: apparatus, not a referenceable result.
   "#+begin_proof\nOmitted.\n#+end_proof\n"
   ;; Prose mentioning a begin-line must NOT be parsed as a result.
   "Write blocks lowercase (#+begin_theorem, not #+begin_Theorem).\n")
  "A small but representative corpus string.")

(defun cerebro-results-tests--records ()
  (cerebro-results-parse-string cerebro-results-tests--doc "notes/x.org"))

(ert-deftest cerebro-results-test-parse-named-only ()
  (let ((names (cerebro-results-names (cerebro-results-tests--records))))
    (should (member "ax-completeness" names))
    (should (member "def-convergence" names))
    (should (member "thm-uniqueness" names))
    (should (member "thm-mct" names))
    (should (= 4 (length names)))))  ; the unnamed proof + prose line are ignored

(ert-deftest cerebro-results-test-parse-fields ()
  (let* ((recs (cerebro-results-tests--records))
         (mct (cl-find "thm-mct" recs :key (lambda (r) (plist-get r :name)) :test #'equal)))
    (should (equal (plist-get mct :type) "theorem"))
    (should (equal (plist-get mct :heading) "Theorems"))
    (should (equal (plist-get mct :file) "notes/x.org"))
    (should (equal (plist-get mct :deps) '("def-convergence" "ax-completeness")))))

(ert-deftest cerebro-results-test-name-must-be-adjacent ()
  ;; #+NAME above #+DEPENDS detaches the name (matching org-element), so
  ;; that result is NOT recorded -- the linter's unnamed-result advisory
  ;; then flags it. #+DEPENDS must go ABOVE #+NAME.
  (let ((bad  (cerebro-results-parse-string
               "#+NAME: thm-x\n#+DEPENDS: def-y\n#+begin_theorem\nb\n#+end_theorem\n"))
        (good (cerebro-results-parse-string
               "#+DEPENDS: def-y\n#+NAME: thm-x\n#+begin_theorem\nb\n#+end_theorem\n")))
    (should (null bad))
    (should (equal (mapcar (lambda (r) (plist-get r :name)) good) '("thm-x")))
    (should (equal (plist-get (car good) :deps) '("def-y")))))

(ert-deftest cerebro-results-test-blank-line-breaks-affiliation ()
  ;; A blank line between #+NAME and the block detaches the name, exactly
  ;; as Org detaches affiliated keywords -- so this defines no result.
  (let ((recs (cerebro-results-parse-string
               "#+NAME: thm-detached\n\n#+begin_theorem\nBody.\n#+end_theorem\n")))
    (should (null recs))))

(ert-deftest cerebro-results-test-transitive-deps-order ()
  ;; thm-mct rests on def-convergence and ax-completeness (both leaves).
  (let* ((recs (cerebro-results-tests--records))
         (deps (cerebro-results-transitive-deps recs "thm-mct")))
    (should (equal (sort (copy-sequence deps) #'string<)
                   '("ax-completeness" "def-convergence")))))

(ert-deftest cerebro-results-test-transitive-deps-multilevel ()
  ;; A -> B -> C : dependencies of A are C and B, foundations first.
  (let* ((recs (cerebro-results-parse-string
                (concat "#+NAME: c\n#+begin_axiom\nx\n#+end_axiom\n"
                        "#+DEPENDS: c\n#+NAME: b\n#+begin_lemma\nx\n#+end_lemma\n"
                        "#+DEPENDS: b\n#+NAME: a\n#+begin_theorem\nx\n#+end_theorem\n")))
         (deps (cerebro-results-transitive-deps recs "a")))
    (should (equal deps '("c" "b")))))          ; foundation (c) before b

(ert-deftest cerebro-results-test-dependents ()
  (let* ((recs (cerebro-results-tests--records))
         (deps (cerebro-results-transitive-dependents recs "def-convergence")))
    (should (equal deps '("thm-mct" "thm-uniqueness")))))  ; sorted

(ert-deftest cerebro-results-test-dangling ()
  ;; def-convergence IS defined here, so only the typo `does-not-exist'
  ;; is dangling -- a real dependency is not a false positive.
  (let ((recs (cerebro-results-parse-string
               (concat "#+NAME: def-convergence\n#+begin_definition\nd\n#+end_definition\n"
                       "#+DEPENDS: does-not-exist, def-convergence\n#+NAME: t\n"
                       "#+begin_theorem\nx\n#+end_theorem\n"))))
    (should (equal (cerebro-results-dangling recs)
                   '(("t" . "does-not-exist"))))))

(ert-deftest cerebro-results-test-dangling-both-missing ()
  (let ((recs (cerebro-results-parse-string
               "#+DEPENDS: p, q\n#+NAME: t\n#+begin_theorem\nx\n#+end_theorem\n")))
    (should (equal (cerebro-results-dangling recs) '(("t" . "p") ("t" . "q"))))))

(ert-deftest cerebro-results-test-cycles ()
  (let ((recs (cerebro-results-parse-string
               (concat "#+DEPENDS: b\n#+NAME: a\n#+begin_theorem\nx\n#+end_theorem\n"
                       "#+DEPENDS: a\n#+NAME: b\n#+begin_theorem\nx\n#+end_theorem\n"
                       "#+NAME: c\n#+begin_axiom\nx\n#+end_axiom\n"))))
    (should (equal (sort (cerebro-results-cycles recs) #'string<) '("a" "b")))
    (should-not (member "c" (cerebro-results-cycles recs)))))

(ert-deftest cerebro-results-test-self-loop-is-a-cycle ()
  (let ((recs (cerebro-results-parse-string
               "#+DEPENDS: a\n#+NAME: a\n#+begin_theorem\nx\n#+end_theorem\n")))
    (should (equal (cerebro-results-cycles recs) '("a")))))

(ert-deftest cerebro-results-test-duplicate-names ()
  (let ((recs (cerebro-results-parse-string
               (concat "#+NAME: dup\n#+begin_theorem\nx\n#+end_theorem\n"
                       "#+NAME: dup\n#+begin_lemma\ny\n#+end_lemma\n"
                       "#+NAME: uniq\n#+begin_axiom\nz\n#+end_axiom\n"))))
    (should (equal (cerebro-results-duplicate-names recs) '("dup")))))

(ert-deftest cerebro-results-test-acyclic-has-no-cycles ()
  (should (null (cerebro-results-cycles (cerebro-results-tests--records)))))


;; -- Proof status -------------------------------------------------------

(ert-deftest cerebro-results-test-status-inferred-from-an-adjacent-proof ()
  "A statement with a proof after it is proved; one without is open.
This is not a guess: `#+begin_proof' immediately after the statement is
the repo's own convention -- it is what the `single' export profile
keeps -- so reading it as the proof status only writes down what the
notes already mean."
  (let ((records (cerebro-results-parse-string "\
#+NAME: thm-with
#+begin_theorem
S.
#+end_theorem

#+begin_proof
P.
#+end_proof

#+NAME: thm-without
#+begin_theorem
S.
#+end_theorem
")))
    (should (equal (plist-get (nth 0 records) :status) "proved"))
    (should (equal (plist-get (nth 1 records) :status) "open"))))

(ert-deftest cerebro-results-test-a-nested-block-does-not-hide-the-proof ()
  "A block inside a statement must not end the statement early.

The scanner closed on the first `#+end_' of ANY type, so a quotation (or
a src block, or anything else nested) inside a theorem ended the theorem
at `#+end_quote'. The real `#+end_theorem' was then read as prose, which
cleared the record a proof could attach to, and the proof directly below
it stopped counting: the result came back `open' forever, here and on the
start page, while bin/notes-lint.el -- reading the same convention
through org-element, which gets nesting right -- went on calling it
proved. Two views of one convention, disagreeing."
  (let ((records (cerebro-results-parse-string "\
#+NAME: thm-nested
#+begin_theorem
S.
#+begin_quote
Something quoted.
#+end_quote
#+end_theorem

#+begin_proof
P.
#+end_proof
")))
    (should (= (length records) 1))
    (should (equal (plist-get (nth 0 records) :status) "proved"))))

(ert-deftest cerebro-results-test-an-unclosed-inner-block-is-survivable ()
  "An `#+end_' for an open-but-not-innermost block unwinds to it.

Otherwise one inner block somebody forgot to close swallows the rest of
the file, and every result below it disappears from the graph -- a
silent, whole-file loss, which is worse than the mis-parse it replaces."
  (let ((records (cerebro-results-parse-string "\
#+NAME: thm-a
#+begin_theorem
#+begin_quote
never closed
#+end_theorem

#+NAME: thm-b
#+begin_theorem
S.
#+end_theorem
")))
    (should (equal (mapcar (lambda (r) (plist-get r :name)) records)
                   '("thm-a" "thm-b")))))

(ert-deftest cerebro-results-test-status-can-be-declared ()
  "`#+STATUS:' wins over the inference, and rides above `#+NAME:'.
`assumed' is the case that matters: something deliberately taken for
granted looks exactly like something proved elsewhere, until it is
written down."
  (let ((records (cerebro-results-parse-string "\
#+STATUS: assumed
#+NAME: thm-riemann
#+begin_theorem
Every non-trivial zero has real part 1/2.
#+end_theorem

#+begin_proof
Not here.
#+end_proof
")))
    (should (equal (plist-get (car records) :status) "assumed"))))

(ert-deftest cerebro-results-test-definitions-have-no-proof-status ()
  "A definition is not unproved -- it is not the kind of thing proved."
  (let ((records (cerebro-results-parse-string
                  "#+NAME: def-x\n#+begin_definition\nD.\n#+end_definition\n")))
    (should-not (plist-get (car records) :status))))

(ert-deftest cerebro-results-test-prose-between-breaks-the-pair ()
  "A proof under different prose is not this statement's proof.
Otherwise every theorem in a note would be `proved' by the first proof
appearing anywhere below it."
  (let ((records (cerebro-results-parse-string "\
#+NAME: thm-a
#+begin_theorem
S.
#+end_theorem

Some prose in between.

#+begin_proof
Of something else.
#+end_proof
")))
    (should (equal (plist-get (car records) :status) "open"))))

(ert-deftest cerebro-results-test-unproved-lists-open-then-assumed ()
  "The work list is open first, assumed second, proved never."
  (let* ((records (list (list :name "a" :status "proved")
                        (list :name "b" :status "assumed")
                        (list :name "c" :status "open")))
         (unproved (cerebro-results-unproved records)))
    (should (equal (mapcar (lambda (r) (plist-get r :name)) unproved) '("c" "b")))))

;; -- The type lists are one decision, not three ------------------------

(ert-deftest cerebro-results-test-provable-types-are-real-types ()
  "A type a proof is expected for must be a type the parser records.

`cerebro-results-provable-types' held \"claim\" for a while. It is not in
`cerebro-results-types', so `cerebro-results-parse-string' never built a
record for a `#+begin_claim' and the entry could not match anything --
dead data describing a feature that did not exist (there is no `claim'
environment in latex/cerebro-theorems.sty either, so such a block would
have failed to compile). Nothing complained, because a list that is only
ever `member'-tested cannot notice an entry that is never looked up."
  (dolist (type cerebro-results-provable-types)
    (should (member type cerebro-results-types))))

(ert-deftest cerebro-results-test-provable-types-are-what-gets-a-status ()
  "The list is the one the parser actually uses to mean `owes a proof'.
Pinned end to end rather than by inspection: a provable type with no
proof parses as `open', and a non-provable one gets no status at all."
  (dolist (type cerebro-results-types)
    (let* ((text (format "#+NAME: x-1\n#+begin_%s\nS.\n#+end_%s\n" type type))
           (status (plist-get (car (cerebro-results-parse-string text)) :status)))
      (if (member type cerebro-results-provable-types)
          (should (equal status "open"))
        (should-not status)))))

(provide 'cerebro-results-tests)
