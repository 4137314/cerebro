;;; cerebro-keys.el --- minimal keybindings -*- lexical-binding: t; -*-

(global-set-key (kbd "C-c n f") #'org-roam-node-find)
(global-set-key (kbd "C-c n i") #'org-roam-node-insert)
(global-set-key (kbd "C-c n c") #'org-roam-capture)
(global-set-key (kbd "C-c a")   #'org-agenda)
(global-set-key (kbd "C-c c")   #'org-capture)
(global-set-key (kbd "C-c i")   #'cerebro-issues-open)

(global-set-key (kbd "C-c q o") #'cerebro-query-orphans)
(global-set-key (kbd "C-c q h") #'cerebro-query-hubs)
(global-set-key (kbd "C-c q s") #'cerebro-query-stale-hubs)
(global-set-key (kbd "C-c q c") #'cerebro-query-co-citation)
(global-set-key (kbd "C-c q t") #'cerebro-query-by-tag)

(provide 'cerebro-keys)
