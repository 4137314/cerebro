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

(provide 'cerebro-taxonomy-tests)
