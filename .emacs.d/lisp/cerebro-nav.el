;;; cerebro-nav.el --- moving through the archive while reading it -*- lexical-binding: t; -*-

;; Everything here is about the same complaint: the archive knew a great
;; deal about itself and none of it was reachable from the buffer you
;; were sitting in. `cerebro results index' could tell you where every
;; named result lives -- in a *report*, which you then read and navigated
;; to by hand. The dependency graph could say what a theorem rests on --
;; in another report. Studying a note meant leaving it.
;;
;; So: the same data, as *movement*.
;;
;;   C-c r j   jump to any result in the archive, by name
;;   C-c r n   the next named result in this note
;;   C-c r p   the previous one
;;   C-c r u   the next result that still owes a proof
;;   C-c r b   what links here (org-roam's backlink buffer)
;;   C-c r D   insert a `#+DEPENDS:' line, completing over real names
;;
;; Why this is a separate module and not part of cerebro-results.el:
;; that one is *pure* -- it parses strings and walks a graph, requires no
;; Org, and a subprocess test asserts it never loads it (invariant 4,
;; cerebro-base.el). Navigation is the opposite: it is nothing but
;; buffers, windows and point. Keeping the two apart is what lets
;; `cerebro results check' stay a 60ms shell command.

(require 'cerebro-base)    ;; cerebro-root
(require 'cerebro-results) ;; the index and the graph, already parsed
(require 'cerebro-guix)    ;; cerebro-guix-soft-require (org-roam is optional)
(require 'org)

(defgroup cerebro-nav nil
  "Moving through the archive."
  :group 'cerebro)

;; -- Pure helpers -------------------------------------------------------

(defun cerebro-nav-candidate (record)
  "One completion line for RECORD: type, name, and where it is. Pure.
The name comes first after the type because that is what you type; the
heading and file are context, and are what tell two `thm-limit-unique's
apart if the archive ever grows a second one."
  (format "%-11s %-34s %s"
          (plist-get record :type)
          (plist-get record :name)
          (or (plist-get record :heading) (plist-get record :file) "")))

(defun cerebro-nav-record-location (record)
  "Absolute (FILE . LINE) for RECORD, or nil. Pure.
`:file' is stored relative to `cerebro-root' (that is what makes a
report readable), so it is expanded here rather than at parse time."
  (when-let* ((file (plist-get record :file)))
    (cons (expand-file-name file cerebro-root)
          (or (plist-get record :line) 1))))

(defun cerebro-nav--reveal ()
  "Unfold around point and centre it, when there is a window to centre in.

`recenter' signals in a buffer that is not displayed, which is not an
edge case here: `cerebro-nav--move' is the useful half of this module
and has to work in a `with-temp-buffer' -- in a test, and in anything
that walks a note without showing it. Display is a nicety; the movement
is the function."
  (when (derived-mode-p 'org-mode)
    (org-fold-show-context 'link-search))
  (when (get-buffer-window (current-buffer))
    (recenter)))

(defun cerebro-nav--goto (record)
  "Open RECORD's file at its line, and show it."
  (if-let* ((where (cerebro-nav-record-location record)))
      (progn
        (find-file (car where))
        (goto-char (point-min))
        (forward-line (1- (cdr where)))
        (cerebro-nav--reveal)
        (message "%s %s" (plist-get record :type) (plist-get record :name)))
    (user-error "cerebro-nav: `%s' has no recorded location"
                (plist-get record :name))))

;; -- Jumping anywhere ---------------------------------------------------

;;;###autoload
(defun cerebro-nav-result (name)
  "Jump to any `#+NAME'd result in the archive, by NAME (`C-c r j').

The archive's table of contents, as a movement rather than a report.
Completion is over every result the graph knows, so this is also the
answer to \"did I already state that, and what did I call it?\" -- which
is the question that otherwise produces a second theorem with a second
name."
  (interactive
   (let* ((records (cerebro-results-scan))
          (rows (mapcar (lambda (r) (cons (cerebro-nav-candidate r) r)) records))
          (choice (completing-read "Result: " (mapcar #'car rows) nil t)))
     (list (cdr (assoc choice rows)))))
  (cerebro-nav--goto (if (stringp name)
                         (seq-find (lambda (r) (equal (plist-get r :name) name))
                                   (cerebro-results-scan))
                       name)))

;; -- Moving inside the note you are reading -----------------------------

(defconst cerebro-nav-result-regexp
  "^[ \t]*#\\+NAME:[ \t]*\\(.+\\)$"
  "How a named result begins, for in-buffer movement.
The `#+NAME:' line rather than the `#+begin_' one: that is where the
name is, it is what you want point on to edit it, and it is one line
above the block either way.")

(defun cerebro-nav--move (count)
  "Move COUNT named results forward (negative: backward). Returns the name."
  (unless (derived-mode-p 'org-mode)
    (user-error "cerebro-nav: not an Org buffer"))
  (let ((case-fold-search t)
        (found nil))
    (dotimes (_ (abs count))
      (let ((search (if (> count 0)
                        (lambda () (re-search-forward cerebro-nav-result-regexp nil t))
                      (lambda () (re-search-backward cerebro-nav-result-regexp nil t)))))
        ;; Forward from the *end* of this line, backward from its
        ;; beginning: otherwise sitting on a `#+NAME:' finds itself and
        ;; the command does nothing, which reads as a broken key.
        (save-match-data
          (if (> count 0) (end-of-line) (beginning-of-line)))
        (if (funcall search)
            (setq found (match-string-no-properties 1))
          (setq found nil))))
    (when found
      (beginning-of-line)
      (cerebro-nav--reveal))
    found))

;;;###autoload
(defun cerebro-nav-next-result (&optional count)
  "Move to the next named result in this note (`C-c r n')."
  (interactive "p")
  (if-let* ((name (cerebro-nav--move (or count 1))))
      (message "%s" name)
    (message "cerebro: no further named result")))

;;;###autoload
(defun cerebro-nav-previous-result (&optional count)
  "Move to the previous named result in this note (`C-c r p')."
  (interactive "p")
  (if-let* ((name (cerebro-nav--move (- (or count 1)))))
      (message "%s" name)
    (message "cerebro: no earlier named result")))

;;;###autoload
(defun cerebro-nav-next-unproved ()
  "Jump to the next result the archive still owes a proof (`C-c r u').

`C-c r o' lists them; this walks them. The list is the work, and a work
list you can only read is a work list you do not do."
  (interactive)
  (let* ((unproved (cerebro-results-unproved (cerebro-results-scan)))
         (here (and (buffer-file-name)
                    (file-relative-name (buffer-file-name) cerebro-root)))
         (line (line-number-at-pos))
         ;; The first one strictly after point in this file, else the
         ;; first one anywhere: walking off the end of a note continues
         ;; into the archive rather than stopping.
         (next (or (seq-find (lambda (r)
                               (and (equal (plist-get r :file) here)
                                    (> (or (plist-get r :line) 0) line)))
                             unproved)
                   (car unproved))))
    (if next
        (cerebro-nav--goto next)
      (message "cerebro: nothing owes a proof"))))

;; -- What links here ----------------------------------------------------

;;;###autoload
(defun cerebro-nav-backlinks ()
  "Show what links to this note (`C-c r b').

Org-roam's backlink buffer when the package is here; otherwise the
results graph's answer to the same question about the result at point,
which needs no database. Two different notions of \"links here\" -- the
first is about notes, the second about statements -- and having the
second is why this still does something useful outside Guix."
  (interactive)
  (cond
   ((and (cerebro-guix-soft-require 'org-roam) (fboundp 'org-roam-buffer-toggle))
    (org-roam-buffer-toggle))
   ((cerebro-nav-result-at-point)
    (cerebro-results-dependents (cerebro-nav-result-at-point)))
   (t (user-error "cerebro-nav: no org-roam, and no named result at point"))))

(defun cerebro-nav-result-at-point ()
  "The name of the nearest `#+NAME:' at or above point, or nil."
  (when (derived-mode-p 'org-mode)
    (save-excursion
      (end-of-line)
      (when (re-search-backward cerebro-nav-result-regexp nil t)
        (string-trim (match-string-no-properties 1))))))

;; -- Writing a dependency without inventing a name ----------------------

;;;###autoload
(defun cerebro-nav-insert-depends (names)
  "Insert a `#+DEPENDS:' line, completing over real result names (`C-c r D').

The convention it serves is load-bearing and unforgiving: `#+DEPENDS:'
goes ABOVE `#+NAME:', and every name in it must resolve or the linter
fails the push. Typing those names from memory is how a dangling
dependency gets written; completing them from the graph is how it does
not. Several may be chosen, one at a time, ending with an empty input."
  (interactive
   (let* ((known (cerebro-results-names (cerebro-results-scan)))
          (chosen nil)
          (more t))
     (while more
       (let ((pick (completing-read
                    (format "Depends on%s (empty to finish): "
                            (if chosen (format " [%d]" (length chosen)) ""))
                    known nil t)))
         (if (string-empty-p pick)
             (setq more nil)
           (push pick chosen)
           (setq known (delete pick known)))))
     (list (nreverse chosen))))
  (if (null names)
      (message "cerebro: nothing inserted")
    (beginning-of-line)
    (insert (format "#+DEPENDS: %s\n" (string-join names ", ")))
    (message "cerebro: depends on %s" (string-join names ", "))))

(provide 'cerebro-nav)
