;;; cerebro-graph-view-tests.el --- ERT tests for the drawn graph -*- lexical-binding: t; -*-

;; Usage: emacs --batch -L .emacs.d/lisp -l tests/cerebro-graph-view-tests.el \
;;          -f ert-run-tests-batch-and-exit
;; (see `make test').
;;
;; The DOT is generated from rows, so it can be checked without a
;; database, without graphviz and without a display. Three properties
;; matter, and each has a failure you would otherwise only see as a
;; strange picture:
;;
;;   - an edge to a note outside the drawn set must be dropped, or
;;     graphviz invents a node labelled with a raw UUID;
;;   - titles and ids must be quoted, since both can contain characters
;;     DOT reads as syntax;
;;   - the neighbourhood must follow links *both* ways -- "what is near
;;     this note" is not a question about which direction you happened to
;;     write the link in.

(require 'ert)
(require 'cerebro-graph-view)

(defconst cerebro-graph-view-tests--nodes
  '(("a" . "Limits") ("b" . "Continuity") ("c" . "Compactness") ("d" . "Far away")))

(defconst cerebro-graph-view-tests--edges
  '(("a" . "b") ("b" . "c")))

;; -- DOT ----------------------------------------------------------------

(ert-deftest cerebro-graph-view-test-dot-has-nodes-and-edges ()
  "Every node is declared with its title; every edge is drawn."
  (let ((dot (cerebro-graph-view-dot cerebro-graph-view-tests--nodes
                                     cerebro-graph-view-tests--edges)))
    (should (string-prefix-p "digraph cerebro {" dot))
    (should (string-match-p "\"a\" \\[label=\"Limits\"" dot))
    (should (string-match-p "\"a\" -> \"b\";" dot))
    (should (string-suffix-p "}\n" dot))))

(ert-deftest cerebro-graph-view-test-dot-drops-dangling-edges ()
  "A link to a note that is not being drawn is left out.
Otherwise graphviz creates the missing node itself, labelled with the
id -- a UUID floating in the picture, which looks like a bug in the
notes rather than in the drawing."
  (let ((dot (cerebro-graph-view-dot
              '(("a" . "Limits"))
              '(("a" . "elsewhere") ("elsewhere" . "a")))))
    (should-not (string-match-p "elsewhere" dot))))

(ert-deftest cerebro-graph-view-test-dot-quotes-titles ()
  "A quotation mark in a title cannot break out of the DOT string."
  (let ((dot (cerebro-graph-view-dot '(("a" . "The \"good\" case")) nil)))
    (should (string-match-p "label=\"The \\\\\"good\\\\\" case\"" dot))))

(ert-deftest cerebro-graph-view-test-dot-highlights-one-node ()
  "The note the drawing is *about* is drawn differently from the rest."
  (let ((dot (cerebro-graph-view-dot cerebro-graph-view-tests--nodes
                                     cerebro-graph-view-tests--edges
                                     nil "b")))
    (should (string-match-p "\"b\" \\[label=\"Continuity\", color=" dot))
    (should-not (string-match-p "\"a\" \\[label=\"Limits\", color=" dot))))

(ert-deftest cerebro-graph-view-test-dot-uses-the-given-colours ()
  "The picture is drawn in the palette it is handed.
A graph rendered in default black-on-white next to a dark buffer is the
same defect this config fixed for LaTeX previews."
  (let ((dot (cerebro-graph-view-dot '(("a" . "x")) nil
                                     '(:bg "#101010" :fg "#eeeeee"
                                       :accent "#88aaff" :dim "#666666"))))
    (should (string-match-p "bgcolor=\"#101010\"" dot))
    (should (string-match-p "fontcolor=\"#eeeeee\"" dot))))

;; -- Neighbourhoods -----------------------------------------------------

(ert-deftest cerebro-graph-view-test-neighbourhood-follows-both-directions ()
  "One step from `b' reaches what it cites and what cites it."
  (let ((near (cerebro-graph-view-neighbourhood
               cerebro-graph-view-tests--nodes cerebro-graph-view-tests--edges "b" 1)))
    (should (equal (sort (mapcar #'car (car near)) #'string<) '("a" "b" "c")))
    ;; ...and not the unconnected note.
    (should-not (assoc "d" (car near)))))

(ert-deftest cerebro-graph-view-test-neighbourhood-depth ()
  "Depth is how many links out: 0 is the note alone, 2 reaches further."
  (let ((zero (cerebro-graph-view-neighbourhood
               cerebro-graph-view-tests--nodes cerebro-graph-view-tests--edges "a" 0))
        (two (cerebro-graph-view-neighbourhood
              cerebro-graph-view-tests--nodes cerebro-graph-view-tests--edges "a" 2)))
    (should (equal (mapcar #'car (car zero)) '("a")))
    (should (equal (sort (mapcar #'car (car two)) #'string<) '("a" "b" "c")))))

(ert-deftest cerebro-graph-view-test-neighbourhood-keeps-only-inner-edges ()
  "Edges leaving the neighbourhood are dropped with their nodes."
  (let ((near (cerebro-graph-view-neighbourhood
               cerebro-graph-view-tests--nodes cerebro-graph-view-tests--edges "a" 1)))
    (should (equal (cdr near) '(("a" . "b"))))))

(provide 'cerebro-graph-view-tests)
