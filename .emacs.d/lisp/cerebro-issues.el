;;; cerebro-issues.el --- personal, non-proprietary issue tracking -*- lexical-binding: t; -*-

;; Issues are plain Org headings in issues/issues.org (TODO/DOING/DONE +
;; a :PROPERTIES: drawer with :ID:/:CREATED: + tags), already picked up
;; by org-agenda-files in cerebro-org.el. The format needs no dedicated
;; Emacs support because it IS just Org; this file only adds a thin
;; convenience on top. Scripted creation lives in bin/cerebro-issue.

(require 'cerebro-org)

(defun cerebro-issues-file ()
  (expand-file-name "issues/issues.org" cerebro-root))

(defun cerebro-issues-open ()
  "Open the issue tracker."
  (interactive)
  (find-file (cerebro-issues-file)))

(provide 'cerebro-issues)
