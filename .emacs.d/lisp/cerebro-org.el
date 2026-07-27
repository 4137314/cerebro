;;; cerebro-org.el --- base Org-mode setup -*- lexical-binding: t; -*-

(require 'org)
(require 'org-agenda)
(require 'ispell)

(defvar cerebro-root
  (expand-file-name "../.." (file-name-directory (or load-file-name buffer-file-name)))
  "Root of the cerebro repository.")

(setq org-directory (expand-file-name "notes" cerebro-root))

(setq org-agenda-files
      (list org-directory
            (expand-file-name "issues/issues.org" cerebro-root)))

;; Content is written in English: point flyspell/ispell at the English
;; dictionary shipped by guix.scm (aspell + aspell-dict-en).
(setq ispell-dictionary "en_US")

(setq org-todo-keywords
      '((sequence "TODO(t)" "DOING(g)" "|" "DONE(d)" "CANCELLED(c)")))

(setq org-log-done 'time)
(setq org-startup-indented t)
(setq org-hide-emphasis-markers t)

(provide 'cerebro-org)
