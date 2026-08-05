;;; cerebro-keys.el --- minimal keybindings -*- lexical-binding: t; -*-

(global-set-key (kbd "C-c n f") #'org-roam-node-find)
(global-set-key (kbd "C-c n i") #'org-roam-node-insert)
(global-set-key (kbd "C-c n c") #'org-roam-capture)
(global-set-key (kbd "C-c n d") #'org-roam-dailies-goto-today)
(global-set-key (kbd "C-c a")   #'org-agenda)
(global-set-key (kbd "C-c c")   #'org-capture)
(global-set-key (kbd "C-c i")   #'cerebro-issues-open)

;; org-ql (cerebro-ql.el): content/metadata queries + saved views,
;; complementary to the org-roam graph queries under C-c q.
(global-set-key (kbd "C-c v v") #'org-ql-view)     ; pick a saved cerebro view
(global-set-key (kbd "C-c v s") #'org-ql-search)   ; ad-hoc org-ql search
(global-set-key (kbd "C-c v a") #'cerebro-ql-area) ; every entry in an area

(global-set-key (kbd "C-c q o") #'cerebro-query-orphans)
(global-set-key (kbd "C-c q h") #'cerebro-query-hubs)
(global-set-key (kbd "C-c q s") #'cerebro-query-stale-hubs)
(global-set-key (kbd "C-c q c") #'cerebro-query-co-citation)
(global-set-key (kbd "C-c q t") #'cerebro-query-by-tag)
(global-set-key (kbd "C-c q m") #'cerebro-query-by-msc)

;; cerebro-results.el: the logical-dependency layer over #+NAMEd results
;; (theorems/definitions/...). Distinct from the org-roam graph (C-c q):
;; that is "how notes cite each other"; this is "on what does this result
;; logically rest". Works with or without the guix env (it's pure Elisp).
(global-set-key (kbd "C-c r i") #'cerebro-results-index)        ; global index
(global-set-key (kbd "C-c r d") #'cerebro-results-dependencies) ; what it rests on
(global-set-key (kbd "C-c r r") #'cerebro-results-dependents)   ; what rests on it
(global-set-key (kbd "C-c r c") #'cerebro-results-check)        ; cycles/dangling/dups

;; cerebro-cli.el: drive the `cerebro' CLI from Emacs, so the same
;; scriptable operation is one keybinding away. `C-c d' = "do" (dispatch).
;; Remap freely -- every command is a plain M-x too.
(global-set-key (kbd "C-c d SPC") #'cerebro-cli)          ; any `cerebro ...' line
(global-set-key (kbd "C-c d i")   #'cerebro-issue-list)
(global-set-key (kbd "C-c d I")   #'cerebro-issue-new)
(global-set-key (kbd "C-c d c")   #'cerebro-issue-close)
(global-set-key (kbd "C-c d N")   #'cerebro-issue-note)
(global-set-key (kbd "C-c d x")   #'cerebro-issue-next)   ; neXt: what to work on
(global-set-key (kbd "C-c d S")   #'cerebro-issue-scan)
(global-set-key (kbd "C-c d R")   #'cerebro-issue-report)
(global-set-key (kbd "C-c d n")   #'cerebro-note-new)
(global-set-key (kbd "C-c d f")   #'cerebro-note-find)
(global-set-key (kbd "C-c d a")   #'cerebro-today)        ; morning review
(global-set-key (kbd "C-c d s")   #'cerebro-stats)
(global-set-key (kbd "C-c d l")   #'cerebro-lint)
(global-set-key (kbd "C-c d t")   #'cerebro-time-report)
(global-set-key (kbd "C-c d k")   #'cerebro-task-report)

(provide 'cerebro-keys)
