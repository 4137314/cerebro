;;; cerebro-graph-view.el --- the note graph, drawn and shown in Emacs -*- lexical-binding: t; -*-

;; `C-c q h' and friends answer questions about the graph as *lists* (the
;; hubs, the orphans, what cites what). Sometimes the question is shaped
;; like a picture instead: where are the clusters, what is this note's
;; neighbourhood, is that corner of the archive connected to anything.
;;
;; This draws it. The pipeline is three plain steps, each a tool that will
;; still exist in twenty years:
;;
;;   org-roam's SQLite  ->  DOT  ->  graphviz  ->  SVG  ->  an Emacs buffer
;;
;; and the last step needs nothing but Emacs: it is built with RSVG here
;; (`system-configuration-features'), so the picture is an image in a
;; buffer, not a browser.
;;
;; That is a deliberate choice against the usual answer, org-roam-ui,
;; which is a web application: it needs a JavaScript build, a websocket, a
;; local HTTP server and a browser -- and to show it *inside* Emacs, an
;; Emacs compiled with xwidgets. At this pin that combination cannot
;; exist: Emacs 30.2 requires WebKitGTK < 2.41.92 for xwidgets and Guix
;; ships 2.50.3, so `--with-xwidgets' fails at configure time (checked --
;; the error is "xwidgets requested but WebKitGTK+ ... not found"). None
;; of that is a loss here: what a graph view is *for* is answering a
;; question about your own notes, and DOT does that offline, in one
;; screenful, with no daemon running.
;;
;; The DOT generation is a pure function of rows (id, title, links), so it
;; is unit-tested without a database -- the same shape as
;; cerebro-graph.el, which already computes hubs and orphans from rows.

(require 'cerebro-org)   ;; cerebro-root, cerebro-report
(require 'cerebro-graph) ;; the pure row-counting layer
(require 'seq)

(defgroup cerebro-graph-view nil
  "Drawing the note graph."
  :group 'cerebro)

(defcustom cerebro-graph-view-program "dot"
  "The graphviz engine used to lay the graph out.
`dot' is hierarchical (good for a dependency-shaped archive); `neato'
and `sfdp' are force-directed and read better for a large, loosely
connected graph."
  :type 'string
  :group 'cerebro-graph-view)

(defcustom cerebro-graph-view-max-nodes 120
  "Stop drawing above this many notes.
A graph of a thousand nodes is a grey cloud: past this size the useful
question is not \"show me everything\" but \"show me around this note\"
(`cerebro-graph-view-local')."
  :type 'integer
  :group 'cerebro-graph-view)

;; -- DOT (pure) ---------------------------------------------------------

(defun cerebro-graph-view--quote (string)
  "STRING as a DOT string literal."
  (format "\"%s\"" (replace-regexp-in-string "\"" "\\\\\"" (or string ""))))

(defun cerebro-graph-view-dot (nodes edges &optional colors highlight)
  "A DOT digraph of NODES and EDGES.

NODES is a list of (ID . TITLE); EDGES a list of (FROM . TO) over those
ids. COLORS is a plist (:bg :fg :accent :dim) so the drawing can be made
in the colours of the theme in force -- a picture that comes out white in
a dark frame is the same defect this config fixed for LaTeX previews.
HIGHLIGHT is an id to draw as the centre of attention.

Pure: no database, no process, no buffer."
  (let* ((colors (or colors '(:bg "#ffffff" :fg "#000000" :accent "#3465a4" :dim "#888888")))
         (known (mapcar #'car nodes)))
    (concat
     "digraph cerebro {\n"
     "  graph [rankdir=LR, splines=spline, overlap=false, "
     (format "bgcolor=%s, fontname=\"sans\"];\n" (cerebro-graph-view--quote (plist-get colors :bg)))
     (format "  node [shape=box, style=\"rounded,filled\", fontname=\"sans\", fontsize=11, penwidth=0.8, fillcolor=%s, color=%s, fontcolor=%s];\n"
             (cerebro-graph-view--quote (plist-get colors :bg))
             (cerebro-graph-view--quote (plist-get colors :dim))
             (cerebro-graph-view--quote (plist-get colors :fg)))
     (format "  edge [color=%s, arrowsize=0.6, penwidth=0.7];\n"
             (cerebro-graph-view--quote (plist-get colors :dim)))
     (mapconcat
      (lambda (node)
        (format "  %s [label=%s%s];\n"
                (cerebro-graph-view--quote (car node))
                (cerebro-graph-view--quote (cdr node))
                (if (equal (car node) highlight)
                    (format ", color=%s, penwidth=2.4, fontcolor=%s"
                            (cerebro-graph-view--quote (plist-get colors :accent))
                            (cerebro-graph-view--quote (plist-get colors :accent)))
                  "")))
      nodes "")
     ;; An edge to a note outside the drawn set would make graphviz invent
     ;; a node for it, labelled with a raw UUID.
     (mapconcat
      (lambda (edge)
        (when (and (member (car edge) known) (member (cdr edge) known))
          (format "  %s -> %s;\n"
                  (cerebro-graph-view--quote (car edge))
                  (cerebro-graph-view--quote (cdr edge)))))
      edges "")
     "}\n")))

(defun cerebro-graph-view-neighbourhood (nodes edges id depth)
  "The subgraph within DEPTH steps of ID, as (NODES . EDGES).
Links count in both directions: \"what is near this note\" is not a
question about which way you happened to write the link."
  (let ((frontier (list id))
        (seen (list id)))
    (dotimes (_ (max 0 depth))
      (let (next)
        (dolist (edge edges)
          (when (member (car edge) frontier) (push (cdr edge) next))
          (when (member (cdr edge) frontier) (push (car edge) next)))
        (setq next (seq-remove (lambda (n) (member n seen)) (seq-uniq next)))
        (setq seen (append seen next)
              frontier next)))
    (cons (seq-filter (lambda (node) (member (car node) seen)) nodes)
          (seq-filter (lambda (edge)
                        (and (member (car edge) seen) (member (cdr edge) seen)))
                      edges))))

;; -- The data (org-roam) ------------------------------------------------

(defun cerebro-graph-view--rows ()
  "Every note and link in the org-roam database, as (NODES . EDGES).
Needs org-roam: the database is what knows the link structure. The rest
of this module is pure, so what cannot be tested here is only the query."
  (unless (fboundp 'org-roam-db-query)
    (user-error "cerebro-graph-view: needs org-roam (M-x cerebro-guix-status)"))
  (let ((nodes (org-roam-db-query [:select [id title] :from nodes]))
        (links (org-roam-db-query [:select [source dest] :from links
                                   :where (= type "id")])))
    (cons (mapcar (lambda (row) (cons (nth 0 row) (nth 1 row))) nodes)
          (mapcar (lambda (row) (cons (nth 0 row) (nth 1 row))) links))))

(defun cerebro-graph-view-colour (value fallback)
  "VALUE if graphviz can understand it as a colour, else FALLBACK.
On a terminal frame `face-attribute' answers `unspecified-bg' -- not a
colour, and graphviz\='s reaction is a warning on stderr and a picture
in some other palette. Pure, so the guard is testable."
  (if (and (stringp value) (color-defined-p value)) value fallback))

(defun cerebro-graph-view--colors ()
  "The drawing colours, taken from the theme in force."
  (list :bg (cerebro-graph-view-colour (face-attribute 'default :background nil t) "#ffffff")
        :fg (cerebro-graph-view-colour (face-attribute 'default :foreground nil t) "#000000")
        :accent (cerebro-graph-view-colour (face-attribute 'link :foreground nil t) "#3465a4")
        :dim (cerebro-graph-view-colour (face-attribute 'shadow :foreground nil t) "#888888")))

;; -- Rendering ----------------------------------------------------------

(defun cerebro-graph-view--render (dot)
  "Run graphviz over DOT and return the SVG, or signal what is missing."
  (unless (executable-find cerebro-graph-view-program)
    (user-error "cerebro-graph-view: %s is not on PATH (graphviz is in guix.scm)"
                cerebro-graph-view-program))
  (with-temp-buffer
    (let ((exit (call-process-region dot nil cerebro-graph-view-program
                                     nil t nil "-Tsvg")))
      (unless (eq exit 0)
        (error "cerebro-graph-view: %s failed: %s"
               cerebro-graph-view-program (string-trim (buffer-string))))
      (buffer-string))))

(defun cerebro-graph-view--show (svg title)
  "Show SVG in a buffer called TITLE."
  (let ((buffer (get-buffer-create "*cerebro-graph*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "%s\n\n" title))
        (if (image-type-available-p 'svg)
            (insert-image (create-image svg 'svg t :scale 1.0))
          ;; No SVG support: keep the drawing rather than the error --
          ;; the file is still a picture, just one for another program.
          (let ((file (expand-file-name "cerebro-graph.svg" temporary-file-directory)))
            (with-temp-file file (insert svg))
            (insert (format "This Emacs cannot display SVG; wrote %s\n" file)))))
      (goto-char (point-min))
      (special-mode))
    (display-buffer buffer)
    buffer))

;;;###autoload
(defun cerebro-graph-view (&optional engine)
  "Draw the whole note graph and show it (`C-c q g').
With a prefix argument, ask which graphviz engine to lay it out with."
  (interactive
   (list (when current-prefix-arg
           (completing-read "Engine: " '("dot" "neato" "sfdp" "circo" "twopi") nil t))))
  (let* ((cerebro-graph-view-program (or engine cerebro-graph-view-program))
         (rows (cerebro-graph-view--rows))
         (nodes (car rows))
         (edges (cdr rows)))
    (when (> (length nodes) cerebro-graph-view-max-nodes)
      (user-error "cerebro-graph-view: %d notes is past `cerebro-graph-view-max-nodes' -- try C-c q G (around one note)"
                  (length nodes)))
    (cerebro-graph-view--show
     (cerebro-graph-view--render
      (cerebro-graph-view-dot nodes edges (cerebro-graph-view--colors)))
     (format "cerebro graph -- %d notes, %d links (%s)"
             (length nodes) (length edges) cerebro-graph-view-program))))

;;;###autoload
(defun cerebro-graph-view-local (depth)
  "Draw the neighbourhood of the note in this buffer (`C-c q G').
DEPTH is how many links out to follow (2 by default): the answer to
\"what does this note sit between?\", which is the question a picture is
actually good at."
  (interactive (list (if current-prefix-arg
                         (read-number "Depth: " 2)
                       2)))
  (let* ((id (or (org-entry-get (point-min) "ID")
                 (user-error "cerebro-graph-view: this buffer is not a note with an :ID:")))
         (rows (cerebro-graph-view--rows))
         (near (cerebro-graph-view-neighbourhood (car rows) (cdr rows) id depth)))
    (cerebro-graph-view--show
     (cerebro-graph-view--render
      (cerebro-graph-view-dot (car near) (cdr near) (cerebro-graph-view--colors) id))
     (format "cerebro graph -- %s, %d steps out (%d notes)"
             (or (cdr (assoc id (car rows))) "this note") depth (length (car near))))))

(provide 'cerebro-graph-view)
