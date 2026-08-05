;;; cerebro-issues.el --- batch issue lifecycle over issues/issues.org -*- lexical-binding: t; -*-

;; Usage: emacs --batch -l bin/cerebro-issues.el -- <cmd> [arg]
;;   list [open|all|done]   list issues (default: open = TODO + DOING)
;;   show   <id|query>      print one issue in full
;;   close  <id|query>      set state DONE   (logs a CLOSED timestamp)
;;   start  <id|query>      set state DOING
;;   reopen <id|query>      set state TODO
;;   report                 counts by state and by tag
;;
;; The issue tracker is just Org (issues/issues.org, git-committed), so
;; every operation here is a plain Org edit done through org-mode itself --
;; state changes go through `org-todo', so `org-log-done' (cerebro-org.el)
;; records the CLOSED timestamp exactly as it would interactively. No
;; Org-roam, no Guix: this runs on the bare Emacs too. The scriptable
;; counterpart of `C-c a i' / `C-c c i' inside Emacs; the `cerebro' CLI
;; dispatches `cerebro issue ...' here (creation stays in the faster
;; POSIX-sh bin/cerebro-issue).

(let* ((here (file-name-directory (or load-file-name buffer-file-name)))
       (lisp-dir (expand-file-name "../.emacs.d/lisp" here)))
  (add-to-list 'load-path lisp-dir))
(require 'cerebro-org)    ; org-todo-keywords, org-log-done, cerebro-root
(require 'cerebro-issues) ; cerebro-issues-file

(defun cerebro-issues-cli--file ()
  "The issue file to operate on: $CEREBRO_ISSUES_FILE when set (so you can
script against any Org file, and the tests can use a throwaway), otherwise
the tracked issues/issues.org."
  (or (getenv "CEREBRO_ISSUES_FILE") (cerebro-issues-file)))

(defun cerebro-issues-cli--buffer ()
  (find-file-noselect (cerebro-issues-cli--file)))

(defun cerebro-issues-cli--entries ()
  "Every top-level issue as a plist (:id :todo :priority :title :tags :point)."
  (with-current-buffer (cerebro-issues-cli--buffer)
    (org-with-wide-buffer
     (goto-char (point-min))
     (let (out)
       (org-map-entries
        (lambda ()
          (let ((c (org-heading-components)))
            (push (list :id (org-entry-get nil "ID")
                        :todo (nth 2 c)
                        :priority (and (nth 3 c) (char-to-string (nth 3 c)))
                        :title (nth 4 c)
                        :tags (org-get-tags nil t)
                        :point (point))
                  out))))
       (nreverse out)))))

(defun cerebro-issues-cli--match (query)
  "Issues matching QUERY: exact ID, ID prefix, or case-insensitive title
substring. Returns a list of entry plists."
  (let ((q (downcase query)))
    (seq-filter
     (lambda (e)
       (let ((id (or (plist-get e :id) ""))
             (title (downcase (or (plist-get e :title) ""))))
         (or (equal id query)
             (string-prefix-p query id)
             (string-match-p (regexp-quote q) title))))
     (cerebro-issues-cli--entries))))

(defun cerebro-issues-cli--one (query)
  "Exactly one issue matching QUERY, or signal a helpful error."
  (let ((matches (cerebro-issues-cli--match query)))
    (cond
     ((null matches) (error "no issue matches `%s'" query))
     ((cdr matches)
      (error "`%s' is ambiguous (%d issues): %s" query (length matches)
             (mapconcat (lambda (e) (format "%s %s" (plist-get e :id)
                                            (plist-get e :title)))
                        matches "; ")))
     (t (car matches)))))

(defun cerebro-issues-cli--fmt (e)
  (format "%-8s %-3s %-15s %s%s"
          (or (plist-get e :todo) "-")
          (if (plist-get e :priority) (format "[#%s]" (plist-get e :priority)) "")
          (or (plist-get e :id) "(no id)")
          (or (plist-get e :title) "")
          (if (plist-get e :tags) (format "  :%s:" (mapconcat #'identity (plist-get e :tags) ":")) "")))

(defun cerebro-issues-cli-list (&optional which tag)
  (let* ((which (or which "open"))
         (all (cerebro-issues-cli--entries))
         (rows (pcase which
                 ("all" all)
                 ("done" (seq-filter (lambda (e) (member (plist-get e :todo) '("DONE" "CANCELLED"))) all))
                 (_ (seq-filter (lambda (e) (member (plist-get e :todo) '("TODO" "DOING"))) all))))
         (rows (if (and tag (not (string-empty-p tag)))
                   (seq-filter (lambda (e) (member tag (plist-get e :tags))) rows)
                 rows)))
    (if rows
        (dolist (e rows) (princ (cerebro-issues-cli--fmt e)) (terpri))
      (princ (format "(no %s issues%s)\n" which (if tag (format " tagged %s" tag) ""))))))

(defun cerebro-issues-cli--prio-rank (e)
  "0/1/2 for priority A/B/C, 3 for none -- lower sorts first."
  (pcase (plist-get e :priority) ("A" 0) ("B" 1) ("C" 2) (_ 3)))

(defun cerebro-issues-cli-next ()
  "Print the single most urgent open issue: highest priority, DOING
before TODO, oldest first -- \"what should I work on now\"."
  (let* ((open (seq-filter (lambda (e) (member (plist-get e :todo) '("TODO" "DOING")))
                           (cerebro-issues-cli--entries)))
         (sorted (sort open
                       (lambda (a b)
                         (let ((ra (cerebro-issues-cli--prio-rank a))
                               (rb (cerebro-issues-cli--prio-rank b)))
                           (cond ((/= ra rb) (< ra rb))
                                 ((not (equal (plist-get a :todo) (plist-get b :todo)))
                                  (equal (plist-get a :todo) "DOING"))
                                 (t (string< (or (plist-get a :id) "") (or (plist-get b :id) "")))))))))
    (if sorted (progn (princ (cerebro-issues-cli--fmt (car sorted))) (terpri))
      (princ "(no open issues)\n"))))

(defun cerebro-issues-cli-note (query text)
  "Append a timestamped progress note TEXT to the issue matching QUERY.
Plain Org: a `- [timestamp] text' line at the end of the entry, so the
issue keeps a committed work log."
  (let ((e (cerebro-issues-cli--one query)))
    (with-current-buffer (cerebro-issues-cli--buffer)
      (org-with-wide-buffer
       (goto-char (plist-get e :point))
       (org-end-of-subtree t t)
       (unless (bolp) (insert "\n"))
       (insert (format "- [%s] %s\n" (format-time-string "%Y-%m-%d %a %H:%M") text))
       (save-buffer)))
    (princ (format "noted on %s: %s\n" (plist-get e :id) (plist-get e :title)))))

(defun cerebro-issues-cli-show (query)
  (let ((e (cerebro-issues-cli--one query)))
    (with-current-buffer (cerebro-issues-cli--buffer)
      (org-with-wide-buffer
       (goto-char (plist-get e :point))
       (princ (buffer-substring-no-properties
               (point) (save-excursion (org-end-of-subtree t t) (point))))))))

(defun cerebro-issues-cli-set (query state)
  (let ((e (cerebro-issues-cli--one query)))
    (with-current-buffer (cerebro-issues-cli--buffer)
      (org-with-wide-buffer
       (goto-char (plist-get e :point))
       (org-todo state)
       (save-buffer))
      (princ (format "%s -> %s: %s\n" (plist-get e :id) state (plist-get e :title))))))

(defun cerebro-issues-cli-report ()
  (let ((all (cerebro-issues-cli--entries))
        (states (make-hash-table :test 'equal))
        (tags (make-hash-table :test 'equal)))
    (dolist (e all)
      (puthash (or (plist-get e :todo) "-") (1+ (gethash (or (plist-get e :todo) "-") states 0)) states)
      (dolist (tag (plist-get e :tags)) (puthash tag (1+ (gethash tag tags 0)) tags)))
    (princ (format "Issues: %d total\n\nBy state:\n" (length all)))
    (dolist (s '("TODO" "DOING" "DONE" "CANCELLED"))
      (when (gethash s states) (princ (format "  %-10s %d\n" s (gethash s states)))))
    (princ "\nBy tag:\n")
    (let (pairs) (maphash (lambda (k v) (push (cons k v) pairs)) tags)
         (dolist (p (sort pairs (lambda (a b) (> (cdr a) (cdr b)))))
           (princ (format "  %-15s %d\n" (car p) (cdr p)))))))

(let* ((args (delete "--" (copy-sequence command-line-args-left)))
       (cmd (or (car args) "list"))
       (arg (cadr args)))
  (condition-case err
      (progn
        (pcase cmd
          ("list"   (cerebro-issues-cli-list arg (nth 2 args)))
          ("show"   (cerebro-issues-cli-show (or arg (error "show needs an <id|query>"))))
          ("close"  (cerebro-issues-cli-set (or arg (error "close needs an <id|query>")) "DONE"))
          ("start"  (cerebro-issues-cli-set (or arg (error "start needs an <id|query>")) "DOING"))
          ("reopen" (cerebro-issues-cli-set (or arg (error "reopen needs an <id|query>")) "TODO"))
          ("note"   (cerebro-issues-cli-note (or arg (error "note needs an <id|query>"))
                                             (or (nth 2 args) (error "note needs text"))))
          ("next"   (cerebro-issues-cli-next))
          ("report" (cerebro-issues-cli-report))
          (_ (error "unknown issue command `%s' (know: list show close start reopen note next report)" cmd)))
        (kill-emacs 0))
    (error (message "cerebro issue: %s" (error-message-string err)) (kill-emacs 1))))
