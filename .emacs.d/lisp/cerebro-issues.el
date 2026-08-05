;;; cerebro-issues.el --- personal, non-proprietary issue tracking -*- lexical-binding: t; -*-

;; Issues are plain Org headings in issues/issues.org (TODO/DOING/DONE +
;; a :PROPERTIES: drawer with :ID:/:CREATED: + tags), already picked up
;; by org-agenda-files in cerebro-org.el. The format needs no dedicated
;; Emacs support because it IS just Org; this file only adds a thin
;; convenience on top. Scripted creation lives in bin/cerebro-issue.

(require 'cerebro-org)
(require 'org-capture)

(defun cerebro-issues-file ()
  (expand-file-name "issues/issues.org" cerebro-root))

(defun cerebro-issues-open ()
  "Open the issue tracker."
  (interactive)
  (find-file (cerebro-issues-file)))

;; `C-c c' (org-capture, bound in cerebro-keys.el) had no templates, so it
;; fell back to Org's built-in default -- which files into
;; `org-default-notes-file' (a stray ~/.notes), NOT the issue tracker.
;; Register an issue template so capture lands where it should, in exactly
;; the heading shape bin/cerebro-issue appends (TODO + :ID:/:CREATED:
;; drawer) -- so an issue looks identical whether it was created from the
;; shell or from inside Emacs. `%^g' prompts for tags, `%a' leaves a link
;; back to wherever you invoked capture from, and `%?' is where the cursor
;; lands to type the body. `(file ...)' appends it as a new top-level
;; entry, like the script.
(add-to-list
 'org-capture-templates
 `("i" "Issue (issues/issues.org)" entry
   (file ,(cerebro-issues-file))
   ,(concat "* TODO %^{Issue title} %^g\n"
            ":PROPERTIES:\n:ID: %<%Y%m%dT%H%M%S>\n:CREATED: %U\n:END:\n"
            "%?\n%a")
   :empty-lines-before 1)
 t)

(provide 'cerebro-issues)
