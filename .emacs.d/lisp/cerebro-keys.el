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

(provide 'cerebro-keys)
