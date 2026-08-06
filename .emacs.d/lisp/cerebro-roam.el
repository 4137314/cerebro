;;; cerebro-roam.el --- org-roam zettelkasten setup -*- lexical-binding: t; -*-

;; Requires emacs-org-roam from guix.scm -- not available outside the
;; guix environment (there is no MELPA/straight.el fallback, on purpose).

(require 'cerebro-org)
(require 'org-roam)
(require 'org-roam-dailies)

;; org-roam-directory / org-roam-db-location are set in cerebro-org.el,
;; shared with bin/notes-lint.el and cerebro-query.el.

;; Navigating a lifelong database means the node picker has to show more
;; than titles: append each node's tags (maturity, area, functional), so
;; `org-roam-node-find' is a filterable map of the whole corpus, not just
;; a list of names.
(setq org-roam-node-display-template
      (concat "${title:*} " (propertize "${tags:40}" 'face 'org-tag)))

;; Offer node completion in ordinary buffer text too (not only after
;; `[['), so linking concepts together is frictionless while writing.
(setq org-roam-completion-everywhere t)

;; book.org is a generated aggregator (bin/cerebro-course), not a concept
;; note -- keep it out of the graph so it never shows up as a node or
;; pollutes backlink/hub counts.
(setq org-roam-file-exclude-regexp '("book\\.org\\'"))

;; Daily notes live in the existing notes/daily/ tree; one lightweight
;; template. `C-c n d' opens today's (see cerebro-keys.el).
(setq org-roam-dailies-directory "daily/")
(setq org-roam-dailies-capture-templates
      '(("d" "default" entry "* %?"
         :target (file+head "%<%Y-%m-%d>.org"
                            "#+TITLE: %<%Y-%m-%d>\n#+FILETAGS: :daily:\n"))))

;; Every capture is born classified: a `:seed:' maturity tag (the
;; workflow starts here and matures toward `:evergreen:') and an empty
;; `#+MSC:' line ready for a classification. Filling the MSC in later is
;; what the linter's advisory nudge and `make query Q=by-msc' encourage.
;; Captures land in notes/math/ (`cerebro-math-directory'), like every
;; other way of making a note here -- the org-roam target is relative to
;; `org-roam-directory', hence a plain subdirectory name rather than the
;; absolute path. Kept as one constant so the three templates below cannot
;; drift apart from each other.
(defconst cerebro-roam--math-subdir
  (file-name-as-directory
   (file-relative-name cerebro-math-directory org-directory))
  "Capture subdirectory for concept notes, relative to the roam root.")

(defconst cerebro-roam--head
  "#+TITLE: ${title}\n#+DATE: %U\n#+FILETAGS: :seed:\n#+MSC: \n\n"
  "Shared front matter for every org-roam capture template.")

(setq org-roam-capture-templates
      `(("n" "note" plain "%?"
         :target (file+head ,(concat cerebro-roam--math-subdir "%<%Y%m%d%H%M%S>-${slug}.org")
                            ,cerebro-roam--head)
         :unnarrowed t)
        ("d" "definition" plain
         "#+begin_definition\n%?\n#+end_definition\n"
         :target (file+head ,(concat cerebro-roam--math-subdir "%<%Y%m%d%H%M%S>-${slug}.org")
                            ,cerebro-roam--head)
         :unnarrowed t)
        ("t" "theorem" plain
         "#+begin_theorem\n%?\n#+end_theorem\n\n#+begin_proof\n\n#+end_proof\n"
         :target (file+head ,(concat cerebro-roam--math-subdir "%<%Y%m%d%H%M%S>-${slug}.org")
                            ,cerebro-roam--head)
         :unnarrowed t)
        ;; org-drill (cerebro-drill.el) drills headings tagged :drill:,
        ;; heading = prompt, body = answer -- an `entry', not `plain',
        ;; template, so capture actually creates that heading structure.
        ("f" "flashcard" entry
         "* %^{Question}                                                     :drill:\n%?"
         :target (file+head ,(concat cerebro-roam--math-subdir "%<%Y%m%d%H%M%S>-${slug}.org")
                            ,cerebro-roam--head)
         :unnarrowed t)))

;; Turn on autosync last, after directory/location (cerebro-org.el) and
;; the settings above are all in place.
(org-roam-db-autosync-mode 1)

(provide 'cerebro-roam)
