;;; cerebro-taxonomy-tests.el --- ERT tests for the area hierarchy -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-taxonomy-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test'). cerebro-taxonomy.el is pure data + helpers, no Org,
;; so it is tested directly. The `family' helper is what cerebro-ql.el
;; uses to expand an area query, so its correctness matters.

(require 'ert)
(require 'cl-lib)
(require 'cerebro-taxonomy)

(ert-deftest cerebro-taxonomy-test-family-includes-supertag-and-members ()
  (let ((fam (cerebro-taxonomy-family "analysis")))
    (should (member "analysis" fam))            ; the supertag itself
    (should (member "functional_analysis" fam)) ; a member
    (should (member "measure_theory" fam))
    (should-not (member "group_theory" fam))))  ; a member of another area

(ert-deftest cerebro-taxonomy-test-family-unknown ()
  (should (null (cerebro-taxonomy-family "not_an_area"))))

(ert-deftest cerebro-taxonomy-test-area-of ()
  (should (equal (cerebro-taxonomy-area-of "quantum_theory") "mathematical_physics"))
  (should (equal (cerebro-taxonomy-area-of "algebra") "algebra")) ; supertag belongs to itself
  (should (null (cerebro-taxonomy-area-of "nope"))))

(ert-deftest cerebro-taxonomy-test-supertags-subset-of-all ()
  (should (member "mathematical_physics" (cerebro-taxonomy-supertags)))
  (should (member "riemannian_geometry" (cerebro-taxonomy-all-tags)))
  (should (cl-subsetp (cerebro-taxonomy-supertags)
                      (cerebro-taxonomy-all-tags) :test #'equal)))


;; -- States (ordered vocabularies) --------------------------------------

(ert-deftest cerebro-taxonomy-test-maturity-ladder-climbs-once ()
  "Promotion walks the ladder and stops at the top.
The ladder being *ordered* is the whole point: it is what lets the
tooling say \"promote\" and \"what is still at the bottom\", which a flat
tag cannot answer."
  (should (equal (cerebro-taxonomy-next-maturity nil) "seed"))
  (should (equal (cerebro-taxonomy-next-maturity "seed") "growing"))
  (should (equal (cerebro-taxonomy-next-maturity "growing") "evergreen"))
  (should-not (cerebro-taxonomy-next-maturity "evergreen")))

(ert-deftest cerebro-taxonomy-test-set-maturity-leaves-other-tags-alone ()
  "Changing the state touches the state only.
An area tag, `crypt' or `drill' are none of this operation's business --
losing one silently while promoting a note would be the worst kind of
data loss: invisible."
  (should (equal (cerebro-taxonomy-set-maturity '("seed" "analysis" "crypt") "evergreen")
                 '("evergreen" "analysis" "crypt")))
  ;; From nothing, and back to nothing.
  (should (equal (cerebro-taxonomy-set-maturity '("analysis") "seed")
                 '("seed" "analysis")))
  (should (equal (cerebro-taxonomy-set-maturity '("seed" "analysis") nil)
                 '("analysis"))))

(ert-deftest cerebro-taxonomy-test-maturity-and-statuses-are-declared-tags ()
  "Every state word is part of the controlled vocabulary.
The linter rejects any tag not in `cerebro-known-tags'; a state the
tooling writes but the linter refuses would fail on the next commit."
  (require 'cerebro-org)
  (dolist (tag cerebro-maturity-ladder)
    (should (member tag (cerebro-known-tags))))
  (dolist (status cerebro-proof-statuses)
    (should (cerebro-proof-status-p (car status)))))

(provide 'cerebro-taxonomy-tests)
