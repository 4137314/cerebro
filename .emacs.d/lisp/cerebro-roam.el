;;; cerebro-roam.el --- org-roam zettelkasten setup -*- lexical-binding: t; -*-

;; Requires emacs-org-roam from guix.scm -- not available outside the
;; guix environment (there is no MELPA/straight.el fallback, on purpose).

(require 'cerebro-org)
(require 'org-roam)

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

;; Composed course documents are written into a `.build/' directory
;; beside their source (cerebro-course.el): they are a *view* of notes
;; that are already in the graph, so indexing them would double every
;; node's backlink count and add a "course" node nobody links to. Derived
;; files are not nodes.
(setq org-roam-file-exclude-regexp '("/\\.build/"))

;; No journal. This is a second brain for *mathematics*: the unit is a
;; result, not a day, and a dated file is the one kind of note nothing
;; ever links to. What a journal was reached for -- "what was I doing?"
;; -- is answered better by `cerebro today' (the agenda), the issue
;; tracker, and Timewarrior, each of which already knows.

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

;; The file a capture lands in is named by the clock and then *renamed*,
;; on its first save, to the digest of its own metadata
;; (cerebro-hash.el). org-capture needs a concrete path up front and
;; cannot compute a digest of a note that does not exist yet, so this is
;; a placeholder with exactly one job: be unique for the second it is
;; used. Nothing ever reads it -- by the time the capture is finalised the
;; file is called what every other note in notes/math/ is called.
(defconst cerebro-roam--target
  (concat cerebro-roam--math-subdir "%<%Y%m%d%H%M%S>.org")
  "Where a capture lands before cerebro-hash.el names it properly.")

(setq org-roam-capture-templates
      `(("n" "note" plain "%?"
         :target (file+head ,cerebro-roam--target
                            ,cerebro-roam--head)
         :unnarrowed t)
        ("d" "definition" plain
         "#+begin_definition\n%?\n#+end_definition\n"
         :target (file+head ,cerebro-roam--target
                            ,cerebro-roam--head)
         :unnarrowed t)
        ("t" "theorem" plain
         "#+begin_theorem\n%?\n#+end_theorem\n\n#+begin_proof\n\n#+end_proof\n"
         :target (file+head ,cerebro-roam--target
                            ,cerebro-roam--head)
         :unnarrowed t)
        ;; org-drill (cerebro-drill.el) drills headings tagged :drill:,
        ;; heading = prompt, body = answer -- an `entry', not `plain',
        ;; template, so capture actually creates that heading structure.
        ("f" "flashcard" entry
         "* %^{Question}                                                     :drill:\n%?"
         :target (file+head ,cerebro-roam--target
                            ,cerebro-roam--head)
         :unnarrowed t)))

;; Turn on autosync last, after directory/location (cerebro-org.el) and
;; the settings above are all in place.
(org-roam-db-autosync-mode 1)

(provide 'cerebro-roam)
