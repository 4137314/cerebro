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

(provide 'cerebro-results-tests)
