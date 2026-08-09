;;; cerebro-cli.el --- drive the `cerebro' CLI from inside Emacs -*- lexical-binding: t; -*-

;; The whole workflow is scriptable through the `cerebro' dispatcher
;; (bin/cerebro). These are thin Emacs wrappers over it, so there is ONE
;; implementation of each operation -- reachable identically from the shell
;; and from a keybinding -- and the two can never drift. Bound under
;; `C-c d' (see cerebro-keys.el); everything is also one M-x away.
;;
;; Two run modes, matching how the CLI itself is split (see bin/cerebro):
;; the pure-Emacs/POSIX operations (issue, note, results, stats) run
;; synchronously in a read-only buffer; the ones that go through
;; bin/guix-run (time, task, lint, query) run asynchronously, so Emacs
;; never blocks while the pinned environment materialises.

(require 'cerebro-base) ;; cerebro-root -- and nothing else, so no Org

(defvar cerebro-cli-program
  (expand-file-name "bin/cerebro" cerebro-root)
  "Path to the `cerebro' CLI dispatcher (bin/cerebro).")

(defun cerebro-cli--run (args &optional buffer-name)
  "Run `cerebro ARGS' (a list of strings) synchronously; show its output
in BUFFER-NAME (default *cerebro-cli*), read-only. For the fast,
pure-Emacs subcommands only -- never for a guix-backed one."
  (let ((buf (get-buffer-create (or buffer-name "*cerebro-cli*"))))
    (with-current-buffer buf
      (let ((inhibit-read-only t) (default-directory cerebro-root))
        (erase-buffer)
        (insert (format "$ cerebro %s\n\n" (mapconcat #'identity args " ")))
        (apply #'call-process cerebro-cli-program nil buf nil args)
        (goto-char (point-min))
        (special-mode)))
    (display-buffer buf)))

(defun cerebro-cli--run-async (args)
  "Run `cerebro ARGS' asynchronously (for guix-backed subcommands, which
may take a while to materialise the environment)."
  (let ((default-directory cerebro-root))
    (async-shell-command
     (concat (shell-quote-argument cerebro-cli-program) " "
             (mapconcat #'shell-quote-argument args " "))
     "*cerebro-cli*")))

;;;###autoload
(defun cerebro-cli (command)
  "Run an arbitrary `cerebro' COMMAND line, read from the minibuffer,
asynchronously (safe for both fast and slow subcommands)."
  (interactive (list (read-string "cerebro ")))
  (cerebro-cli--run-async (split-string-and-unquote command)))

;; -- Issues ------------------------------------------------------------

(defun cerebro-cli--revert-issues ()
  "Refresh the issues.org buffer if it is visited, after a CLI edit."
  (let ((buf (find-buffer-visiting (expand-file-name "issues/issues.org" cerebro-root))))
    (when buf (with-current-buffer buf (revert-buffer t t t)))))

(defconst cerebro-cli-issue-id-regexp
  "\\([0-9]\\{8\\}T[0-9]\\{6\\}\\|[0-9a-f]\\{8\\}-[0-9a-f-]\\{27\\}\\)"
  "How an issue ID is recognised inside a line of `cerebro issue list'.
Two shapes, because the tracker has had two: an Org timestamp id
\(20260807T120000) and a uuid. Matching by *shape* rather than by column
is what lets the listing format change without breaking the picker.")

(defun cerebro-cli-issue-id (line)
  "The issue ID in LINE, or nil. Pure.

Split out from the picker so the one piece of parsing in this module is
testable without a CLI, a database or a minibuffer -- the module is
otherwise deliberately all I/O (invariant 4)."
  (when (and (stringp line) (string-match cerebro-cli-issue-id-regexp line))
    (match-string 1 line)))

(defun cerebro-cli--read-issue (prompt)
  "Completing-read an issue, returning its :ID:. Candidates come from
`cerebro issue list all'; the ID is extracted by shape.

`--all-modes' on purpose: the macro-mode filters what you are *shown to
work on* (`C-c d i', the start page), never what you may act on. These
commands close, start, reopen and annotate a *named* issue, and an issue
you can name is one you can close whichever mode you are in."
  (let* ((lines (with-temp-buffer
                  (let ((default-directory cerebro-root))
                    (call-process cerebro-cli-program nil t nil
                                  "issue" "list" "all" "--all-modes"))
                  (split-string (buffer-string) "\n" t)))
         (choice (completing-read prompt lines nil t)))
    (or (cerebro-cli-issue-id choice)
        (user-error "could not find an id in `%s'" choice))))

;;;###autoload
(defun cerebro-issue-list () "List open issues." (interactive) (cerebro-cli--run '("issue" "list")))
;;;###autoload
(defun cerebro-issue-report () "Issue counts by state and tag." (interactive) (cerebro-cli--run '("issue" "report")))
;;;###autoload
(defun cerebro-issue-next () "Show the single most urgent open issue." (interactive) (cerebro-cli--run '("issue" "next")))
;;;###autoload
(defun cerebro-issue-scan () "Create issues from CEREBRO-ISSUE: markers in the source."
  (interactive) (cerebro-cli--run '("issue" "scan")) (cerebro-cli--revert-issues))

;;;###autoload
(defun cerebro-issue-note (id text)
  "Append a timestamped progress note TEXT to the chosen issue."
  (interactive (list (cerebro-cli--read-issue "Note on issue: ")
                     (read-string "Note: ")))
  (cerebro-cli--run (list "issue" "note" id text))
  (cerebro-cli--revert-issues))

;;;###autoload
(defun cerebro-issue-new (title &optional tags)
  "Create an issue TITLE (optionally space/comma TAGS) from Emacs."
  (interactive "sIssue title: \nsTags (optional): ")
  (cerebro-cli--run (append (list "issue" "new" title)
                            (and tags (not (string-empty-p tags))
                                 (split-string tags "[ ,]+" t))))
  (cerebro-cli--revert-issues))

(defmacro cerebro-cli--defissue-state (name state prompt)
  "Define an interactive command NAME setting a chosen issue to STATE."
  `(progn
     ;;;###autoload
     (defun ,name (id)
       ,(format "Set the chosen issue to %s." state)
       (interactive (list (cerebro-cli--read-issue ,prompt)))
       (cerebro-cli--run (list "issue" ,(downcase state) id))
       (cerebro-cli--revert-issues))))

(cerebro-cli--defissue-state cerebro-issue-close  "close"  "Close issue: ")
(cerebro-cli--defissue-state cerebro-issue-start  "start"  "Start issue: ")
(cerebro-cli--defissue-state cerebro-issue-reopen "reopen" "Reopen issue: ")

;; -- Notes -------------------------------------------------------------

;;;###autoload
(defun cerebro-note-new (title &optional tags msc)
  "Create a note TITLE (optional comma TAGS and MSC) and open it."
  (interactive "sNote title: \nsTags (comma, optional): \nsMSC (optional): ")
  (let* ((default-directory cerebro-root)
         (out (with-temp-buffer
                (apply #'call-process cerebro-cli-program nil t nil
                       (append (list "note" "new" title)
                               (and tags (not (string-empty-p tags)) (list tags))
                               (and msc (not (string-empty-p msc)) (list msc))))
                (string-trim (buffer-string)))))
    (when (string-match "created \\(.*\\)\\'" out)
      (find-file (expand-file-name (match-string 1 out) cerebro-root)))
    (message "%s" out)))

;;;###autoload
(defun cerebro-note-find (query) "Search notes for QUERY." (interactive "sFind notes: ")
  (cerebro-cli--run (list "note" "find" query)))

;; -- Reports (fast: stats; async: guix-backed) -------------------------

;;;###autoload
(defun cerebro-today () "The morning-review agenda in a buffer (fast, offline)." (interactive) (cerebro-cli--run '("today")))
;;;###autoload
(defun cerebro-stats () "Notes/rigor/classification dashboard." (interactive) (cerebro-cli--run '("stats")))
;;;###autoload
(defun cerebro-lint () "Run the note consistency checks (guix)." (interactive) (cerebro-cli--run-async '("lint")))
;;;###autoload
(defun cerebro-time-report () "Timewarrior weekly summary (guix)." (interactive) (cerebro-cli--run-async '("time" "week")))
;;;###autoload
(defun cerebro-task-report () "Taskwarrior +cerebro tasks (guix)." (interactive) (cerebro-cli--run-async '("task")))

(provide 'cerebro-cli)
