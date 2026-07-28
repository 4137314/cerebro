;;; cerebro-msc-tests.el --- ERT tests for the MSC2020 module -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-msc-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test'). cerebro-msc.el is pure Emacs Lisp -- no Org-roam,
;; no Guix -- so its validation/parsing logic is tested directly here.

(require 'ert)
(require 'cerebro-msc)

(ert-deftest cerebro-msc-test-class-of ()
  (should (equal (cerebro-msc-class-of "47A75") "47"))
  (should (equal (cerebro-msc-class-of "47") "47"))
  (should (null (cerebro-msc-class-of "4")))
  (should (null (cerebro-msc-class-of nil))))

(ert-deftest cerebro-msc-test-class-name ()
  (should (equal (cerebro-msc-class-name "47A75") "Operator theory"))
  (should (equal (cerebro-msc-class-name "46") "Functional analysis"))
  (should (equal (cerebro-msc-class-name "81Q10") "Quantum theory"))
  ;; 99 is not a real MSC class.
  (should (null (cerebro-msc-class-name "99Z99"))))

(ert-deftest cerebro-msc-test-valid-codes ()
  (dolist (c '("47A75" "35Q41" "46-XX" "46-06" "46Axx" "47A2x" "81Q10"))
    (should (cerebro-msc-valid-code-p c))))

(ert-deftest cerebro-msc-test-invalid-codes ()
  (dolist (c '(""            ; empty
               "4A75"        ; one-digit class
               "47a75"       ; lowercase leading letter
               "47A7"        ; too short
               "99A10"       ; well-formed but 99 is not a real class
               "hello"       ; nonsense
               "46 XX"))     ; space, not the dash form
    (should-not (cerebro-msc-valid-code-p c))))

(ert-deftest cerebro-msc-test-parse ()
  (should (equal (cerebro-msc-parse "47A75, 46C05,35Q41")
                 '("47A75" "46C05" "35Q41")))
  (should (equal (cerebro-msc-parse "  47A75   46-XX ")
                 '("47A75" "46-XX")))
  (should (null (cerebro-msc-parse "")))
  (should (null (cerebro-msc-parse nil))))

(ert-deftest cerebro-msc-test-primary-and-invalid ()
  (let ((codes (cerebro-msc-parse "47A75, 99Z99, 46C05")))
    (should (equal (cerebro-msc-primary codes) "47A75"))
    (should (equal (cerebro-msc-invalid codes) '("99Z99")))))

(ert-deftest cerebro-msc-test-classes-well-formed ()
  ;; Every hard-coded class code is exactly two digits, and names are
  ;; non-empty -- guards against a typo in the big table above.
  (dolist (entry cerebro-msc-classes)
    (should (string-match-p "\\`[0-9][0-9]\\'" (car entry)))
    (should (> (length (cdr entry)) 0))))

(provide 'cerebro-msc-tests)
