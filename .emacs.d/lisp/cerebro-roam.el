;;; cerebro-roam.el --- org-roam zettelkasten setup -*- lexical-binding: t; -*-

;; Requires emacs-org-roam from guix.scm -- not available outside the
;; guix environment (there is no MELPA/straight.el fallback, on purpose).

(require 'cerebro-org)
(require 'org-roam)

(setq org-roam-directory org-directory)
(setq org-roam-db-location (expand-file-name ".org-roam.db" cerebro-root))

(org-roam-db-autosync-mode 1)

(setq org-roam-capture-templates
      '(("n" "note" plain "%?"
         :target (file+head "%<%Y%m%d%H%M%S>-${slug}.org"
                             "#+TITLE: ${title}\n#+DATE: %U\n\n")
         :unnarrowed t)
        ("d" "definition" plain
         "#+begin_definition\n%?\n#+end_definition\n"
         :target (file+head "%<%Y%m%d%H%M%S>-${slug}.org"
                             "#+TITLE: ${title}\n#+DATE: %U\n\n")
         :unnarrowed t)
        ("t" "theorem" plain
         "#+begin_theorem\n%?\n#+end_theorem\n\n#+begin_proof\n\n#+end_proof\n"
         :target (file+head "%<%Y%m%d%H%M%S>-${slug}.org"
                             "#+TITLE: ${title}\n#+DATE: %U\n\n")
         :unnarrowed t)))

(provide 'cerebro-roam)
