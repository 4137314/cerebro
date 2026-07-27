;;; cerebro-time.el --- bridge org-clock and timewarrior -*- lexical-binding: t; -*-

;; One-way, explicit bridge, on purpose: org-clock stays the source of
;; truth inside Emacs; clocking in/out also mirrors a `timew start/stop'
;; call, so timewarrior's own scriptable reporting (timew summary, timew
;; day, ...) sees cerebro time too, independent of Emacs being open.
;; No attempt at bidirectional sync -- that is a well-known way to end up
;; with two disagreeing sources of truth.

(require 'org-clock)

(defun cerebro-time--tags-for-heading ()
  "Timewarrior tags for the heading currently being clocked: its own
title, plus its Org tags."
  (cons (org-get-heading t t t t) (org-get-tags)))

(defun cerebro-time-clock-in ()
  "Mirror `org-clock-in' into timewarrior, if it is installed."
  (when (executable-find "timew")
    (apply #'call-process "timew" nil 0 nil "start"
           (cerebro-time--tags-for-heading))))

(defun cerebro-time-clock-out ()
  "Mirror `org-clock-out' into timewarrior, if it is installed."
  (when (executable-find "timew")
    (call-process "timew" nil 0 nil "stop")))

(add-hook 'org-clock-in-hook #'cerebro-time-clock-in)
(add-hook 'org-clock-out-hook #'cerebro-time-clock-out)

(provide 'cerebro-time)
