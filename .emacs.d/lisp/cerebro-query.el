;;; cerebro-query.el --- query the Org-roam graph for non-obvious structure -*- lexical-binding: t; -*-

;; "Pattern nascosti", concretely and locally: structural graph queries
;; against Org-roam's own SQLite database (`org-roam-db-query', its
;; public, documented raw-query escape hatch) -- not embeddings, not a
;; cloud service, not anything that would break "isolato". Every query
;; here fetches plain rows (`nodes', `links', `tags' -- schema
;; confirmed with sqlite3 against a real generated database, not
;; assumed) and does the counting/joining in Elisp rather than in SQL,
;; which is fine at the scale of one person's notes and a lot easier to
;; get right than emacsql's join syntax.

(require 'cl-lib)
(require 'cerebro-org)
(require 'org-roam)

(defun cerebro-query--nodes ()
  "Every node as a list of (id title file)."
  (org-roam-db-query [:select [id title file] :from nodes]))

(defun cerebro-query--id-links ()
  "Every `id'-type link as a list of (source dest)."
  (org-roam-db-query [:select [source dest] :from links :where (= type "id")]))

(defun cerebro-query--titles-table (nodes)
  (let ((h (make-hash-table :test 'equal)))
    (dolist (n nodes) (puthash (nth 0 n) (nth 1 n) h))
    h))

(defun cerebro-query--files-table (nodes)
  (let ((h (make-hash-table :test 'equal)))
    (dolist (n nodes) (puthash (nth 0 n) (nth 2 n) h))
    h))

(defun cerebro-query--mtimes-table ()
  (let ((h (make-hash-table :test 'equal)))
    (dolist (f (org-roam-db-query [:select [file mtime] :from files]))
      (puthash (nth 0 f) (nth 1 f) h))
    h))

(defun cerebro-query--report (title rows format-row)
  "Show ROWS (already sorted/filtered) in a simple `*cerebro-query*'
buffer, TITLE as a heading, FORMAT-ROW turning one row into a line."
  (let ((buf (get-buffer-create "*cerebro-query*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "%s\n%s\n\n" title (make-string (length title) ?=)))
        (if (not rows)
            (insert "(nothing found)\n")
          (dolist (r rows) (insert (funcall format-row r) "\n"))))
      (goto-char (point-min)))
    (display-buffer buf)))

;;;###autoload
(defun cerebro-query-orphans ()
  "Nodes with no incoming and no outgoing links -- not connected to
the rest of the graph at all yet."
  (interactive)
  (let* ((nodes (cerebro-query--nodes))
         (connected (make-hash-table :test 'equal)))
    (dolist (l (cerebro-query--id-links))
      (puthash (nth 0 l) t connected)
      (puthash (nth 1 l) t connected))
    (cerebro-query--report
     "Orphans (no links in or out)"
     (seq-filter (lambda (n) (not (gethash (nth 0 n) connected))) nodes)
     (lambda (n) (format "%s  [%s]" (nth 1 n) (nth 2 n))))))

;;;###autoload
(defun cerebro-query-hubs ()
  "Nodes ranked by how many other (existing) nodes link to them --
your load-bearing concepts."
  (interactive)
  (let* ((nodes (cerebro-query--nodes))
         (titles (cerebro-query--titles-table nodes))
         (counts (make-hash-table :test 'equal)))
    (dolist (l (cerebro-query--id-links))
      (let ((dest (nth 1 l)))
        (when (gethash dest titles)
          (puthash dest (1+ (gethash dest counts 0)) counts))))
    (let (rows)
      (maphash (lambda (id n) (push (list n (gethash id titles)) rows)) counts)
      (setq rows (sort rows (lambda (a b) (> (car a) (car b)))))
      (cerebro-query--report
       "Hubs (ranked by backlink count)" rows
       (lambda (r) (format "%3d  %s" (car r) (cadr r)))))))

;;;###autoload
(defun cerebro-query-stale-hubs (&optional days min-backlinks)
  "Hubs (>= MIN-BACKLINKS, default 2) whose file hasn't been touched
in DAYS (default 30) -- foundational but neglected."
  (interactive)
  (let* ((days (or days 30))
         (min-backlinks (or min-backlinks 2))
         (cutoff (time-subtract (current-time) (days-to-time days)))
         (nodes (cerebro-query--nodes))
         (titles (cerebro-query--titles-table nodes))
         (files (cerebro-query--files-table nodes))
         (mtimes (cerebro-query--mtimes-table))
         (counts (make-hash-table :test 'equal)))
    (dolist (l (cerebro-query--id-links))
      (let ((dest (nth 1 l)))
        (when (gethash dest titles)
          (puthash dest (1+ (gethash dest counts 0)) counts))))
    (let (rows)
      (maphash
       (lambda (id n)
         (when (>= n min-backlinks)
           (let* ((file (gethash id files))
                  (mtime (gethash file mtimes)))
             (when (and mtime (time-less-p mtime cutoff))
               (push (list n (gethash id titles) file) rows)))))
       counts)
      (setq rows (sort rows (lambda (a b) (> (car a) (car b)))))
      (cerebro-query--report
       (format "Stale hubs (>=%d backlinks, untouched >%d days)" min-backlinks days)
       rows
       (lambda (r) (format "%3d  %s  (%s)" (nth 0 r) (nth 1 r) (nth 2 r)))))))

;;;###autoload
(defun cerebro-query-co-citation (&optional min-common)
  "Node pairs never linked to each other directly, but both linked
from many of the same third nodes (>= MIN-COMMON, default 2) -- a
structural similarity the backlink view of either node, on its own,
won't show you."
  (interactive)
  (let* ((min-common (or min-common 2))
         (nodes (cerebro-query--nodes))
         (titles (cerebro-query--titles-table nodes))
         (by-source (make-hash-table :test 'equal))
         (direct (make-hash-table :test 'equal))
         (pair-counts (make-hash-table :test 'equal)))
    (dolist (l (cerebro-query--id-links))
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
                   (push (list v (gethash (car k) titles) (gethash (cdr k) titles)) rows)))
               pair-counts)
      (setq rows (sort rows (lambda (a b) (> (car a) (car b)))))
      (cerebro-query--report
       (format "Co-citation (>=%d shared citing nodes, never linked directly)" min-common)
       rows
       (lambda (r) (format "%3d  %s  <->  %s" (nth 0 r) (nth 1 r) (nth 2 r)))))))

;;;###autoload
(defun cerebro-query-by-tag (tag)
  "Nodes tagged TAG."
  (interactive (list (completing-read "Tag: " (cerebro-known-tags) nil t)))
  (let* ((nodes (cerebro-query--nodes))
         (titles (cerebro-query--titles-table nodes))
         (matches (seq-filter
                   (lambda (row) (equal (nth 1 row) tag))
                   (org-roam-db-query [:select [node-id tag] :from tags]))))
    (cerebro-query--report
     (format "Nodes tagged `%s'" tag) matches
     (lambda (r) (format "%s" (gethash (nth 0 r) titles))))))

(provide 'cerebro-query)
