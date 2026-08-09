;;; cerebro-drill.el --- spaced repetition for definitions/theorems -*- lexical-binding: t; -*-

;; emacs-org-drill, from guix.scm -- not available outside the guix
;; environment (no MELPA/straight.el fallback, on purpose, as with
;; org-roam). Tag a heading :drill: (declared in cerebro-org.el's
;; org-tag-alist) and its content becomes a flashcard; `M-x org-drill'
;; quizzes you over every :drill: heading in org-drill-scope. Uses the
;; existing tag taxonomy (e.g. combine :drill: with :hard:) instead of
;; inventing a second one.

(require 'cerebro-org)
(require 'org-drill)

;; Reuse org-agenda-files (cerebro-org.el) rather than defining a second
;; list of "where the notes are". Since org-agenda-files is now built from
;; `cerebro-note-directories' (every subdirectory of notes/, not just the
;; top level), 'agenda genuinely covers the whole nested tree --
;; notes/courses/ and notes/conjectures/ included -- which a plain 'directory
;; scope (files next to the current buffer only) would miss.
(setq org-drill-scope 'agenda)

(provide 'cerebro-drill)
