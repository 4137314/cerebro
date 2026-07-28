;;; cerebro-graph-tests.el --- ERT tests for the pure graph logic -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-graph-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test', which loads this alongside cerebro-latex-tests.el).
;;
;; cerebro-graph.el is the counting/joining behind cerebro-query.el with
;; the org-roam I/O removed, precisely so it can be tested on synthetic
;; rows here -- no Org-roam, no Guix, no SQLite database needed.

(require 'ert)
(require 'cerebro-graph)

(ert-deftest cerebro-graph-test-orphans ()
  ;; c is linked to by nobody and links to nobody -> the only orphan.
  (let ((nodes '(("a" "A" "a.org") ("b" "B" "b.org") ("c" "C" "c.org")))
        (links '(("a" "b"))))
    (should (equal (mapcar #'car (cerebro-graph-orphans nodes links))
                   '("c")))))

(ert-deftest cerebro-graph-test-orphans-empty-graph ()
  ;; No links at all -> every node is an orphan, order preserved.
  (let ((nodes '(("a" "A" "a.org") ("b" "B" "b.org"))))
    (should (equal (cerebro-graph-orphans nodes '()) nodes))))

(ert-deftest cerebro-graph-test-backlink-counts ()
  (let ((valid (make-hash-table :test 'equal)))
    (dolist (id '("a" "b" "c")) (puthash id t valid))
    (let ((counts (cerebro-graph-backlink-counts
                   '(("a" "b") ("c" "b") ("a" "c") ("a" "z")) valid)))
      (should (= (gethash "b" counts) 2))
      (should (= (gethash "c" counts) 1))
      ;; "z" is not a real node -> a link to it is not counted.
      (should (null (gethash "z" counts))))))

(ert-deftest cerebro-graph-test-co-citation-basic ()
  ;; s1 and s2 both cite a and b; a,b never linked to each other.
  (let ((links '(("s1" "a") ("s1" "b") ("s2" "a") ("s2" "b"))))
    (should (equal (cerebro-graph-co-citation-pairs links 2)
                   '((2 "a" "b"))))))

(ert-deftest cerebro-graph-test-co-citation-min-common ()
  (let ((links '(("s1" "a") ("s1" "b"))))
    ;; one shared source is below the threshold of 2 ...
    (should (null (cerebro-graph-co-citation-pairs links 2)))
    ;; ... but meets a threshold of 1.
    (should (equal (cerebro-graph-co-citation-pairs links 1)
                   '((1 "a" "b"))))))

(ert-deftest cerebro-graph-test-co-citation-excludes-direct ()
  ;; a and b are co-cited by s1 and s2, but also linked directly (a->b);
  ;; a directly-linked pair is never reported as a co-citation.
  (let ((links '(("s1" "a") ("s1" "b") ("s2" "a") ("s2" "b") ("a" "b"))))
    (should (null (cerebro-graph-co-citation-pairs links 2)))))

(ert-deftest cerebro-graph-test-co-citation-canonical-order ()
  ;; The pair is always (string< a b), regardless of citing order.
  (let ((links '(("s1" "z") ("s1" "a") ("s2" "z") ("s2" "a"))))
    (should (equal (cerebro-graph-co-citation-pairs links 2)
                   '((2 "a" "z"))))))

(provide 'cerebro-graph-tests)
