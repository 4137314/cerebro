;;; cerebro-graph.el --- pure graph computations over node/link rows -*- lexical-binding: t; -*-

;; The counting/joining behind cerebro-query.el, factored out as pure
;; functions: they take plain rows (exactly the shape cerebro-query's
;; org-roam-db-query fetchers return -- nodes as (id title file), links
;; as (source dest)) and return sorted result rows. No org-roam, no I/O,
;; no display buffers.
;;
;; The point of the split is testability: cerebro-query.el has to
;; `(require 'org-roam)', which is only available inside the guix
;; environment, so its logic could never be unit-tested on its own.
;; This module requires nothing beyond cl-lib, so tests/cerebro-graph-tests.el
;; exercises the hub/orphan/co-citation logic directly, without Org-roam
;; or Guix (see `make test').

(require 'cl-lib)

(defun cerebro-graph-orphans (nodes links)
  "Subset of NODES with no incoming and no outgoing link.
NODES is a list of (id title file); LINKS a list of (source dest).
Rows are returned in NODES order."
  (let ((connected (make-hash-table :test 'equal)))
    (dolist (l links)
      (puthash (nth 0 l) t connected)
      (puthash (nth 1 l) t connected))
    (seq-filter (lambda (n) (not (gethash (nth 0 n) connected))) nodes)))

(defun cerebro-graph-backlink-counts (links valid-ids)
  "How many LINKS point to each destination id, counting only
destinations present in VALID-IDS (a hash-table keyed by id -- i.e.
links to ids that are not real nodes are ignored). Return a fresh
hash-table mapping id -> count."
  (let ((counts (make-hash-table :test 'equal)))
    (dolist (l links)
      (let ((dest (nth 1 l)))
        (when (gethash dest valid-ids)
          (puthash dest (1+ (gethash dest counts 0)) counts))))
    counts))

(defun cerebro-graph-co-citation-pairs (links min-common)
  "Id pairs never linked to each other directly, but both linked from
at least MIN-COMMON of the same source nodes. LINKS is a list of
(source dest). Return a list of (count id-a id-b), id-a `string<' id-b,
sorted by COUNT descending."
  (let ((by-source (make-hash-table :test 'equal))
        (direct (make-hash-table :test 'equal))
        (pair-counts (make-hash-table :test 'equal)))
    (dolist (l links)
      (cl-pushnew (nth 1 l) (gethash (nth 0 l) by-source) :test #'equal)
      (puthash (cons (nth 0 l) (nth 1 l)) t direct))
    (maphash
     (lambda (_source dests)
       (let ((remaining dests))
         (while remaining
           (let ((a (car remaining)))
             (dolist (b (cdr remaining))
               (unless (or (gethash (cons a b) direct) (gethash (cons b a) direct))
                 (let ((key (if (string< a b) (cons a b) (cons b a))))
                   (puthash key (1+ (gethash key pair-counts 0)) pair-counts))))
             (setq remaining (cdr remaining))))))
     by-source)
    (let (rows)
      (maphash (lambda (k v)
                 (when (>= v min-common)
                   (push (list v (car k) (cdr k)) rows)))
               pair-counts)
      (sort rows (lambda (a b) (> (car a) (car b)))))))

(provide 'cerebro-graph)
