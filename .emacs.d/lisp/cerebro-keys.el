;;; cerebro-keys.el --- minimal keybindings -*- lexical-binding: t; -*-

;; One place for every cerebro binding, so the whole surface is readable
;; in one file. Commands from optional modules are bound unconditionally
;; on purpose: a key that reports a void command in the degraded,
;; outside-guix mode is better than a key that silently changed meaning.
;; The exception is consult, which *replaces* standard keys (C-x b, M-y,
;; M-g g) and is therefore bound in cerebro-complete.el, where its
;; availability is known.

;; which-key ships in Emacs core since 30: after a prefix, it lists what
;; can follow. With this many prefixes (C-c n/v/q/r/d/G/w) that is the
;; difference between a config you remember and one you re-read. The
;; labels below are what it shows for each of them.
(when (fboundp 'which-key-mode)
  (which-key-mode 1)
  (when (fboundp 'which-key-add-key-based-replacements)
    (which-key-add-key-based-replacements
      "C-c n" "roam (notes)"
      "C-c v" "org-ql views"
      "C-c q" "graph queries"
      "C-c r" "results graph"
      "C-c d" "cerebro CLI"
      "C-c G" "guix environment"
      "C-c w" "window layout"
      "C-c u" "look & feel"
      "C-c m" "make a note"
      "C-c e" "export & PDF")))

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
;; ...and the graph as a picture: `g' the whole thing, `G' the
;; neighbourhood of this note (cerebro-graph-view.el).
(global-set-key (kbd "C-c q g") #'cerebro-graph-view)
(global-set-key (kbd "C-c q G") #'cerebro-graph-view-local)

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

;; -- The workspace: start page, tree, search, git ----------------------
;; Single keys, because these are the ones pressed dozens of times a day.
;; All four are free in org-mode (checked: org binds C-c C-x ... and
;; C-c <arrows>, not these).
(global-set-key (kbd "C-c h") #'cerebro-dashboard)    ; Home: the start page
(global-set-key (kbd "C-c t") #'cerebro-ui-toggle-tree) ; Tree: C-u = whole repo
(global-set-key (kbd "C-c s") #'cerebro-search-notes) ; Search the note text
(global-set-key (kbd "C-c g") #'magit-status)         ; Git (magit's own C-x g too)

;; -- Making a note (C-c m) ---------------------------------------------
;; The unit here is one result per note, so making one has to cost a
;; keystroke: `C-c m t' and you are typing a theorem, in a file you never
;; named, already carrying an :ID:, a `:seed:' tag and a `#+NAME:' the
;; results graph can cite (cerebro-math.el). `C-c m e' is the other half:
;; a statement you already wrote becomes its own note, with a link left
;; where it was.
(global-set-key (kbd "C-c m n") #'cerebro-math-new)              ; asks which kind
(global-set-key (kbd "C-c m t") #'cerebro-math-new-theorem)
(global-set-key (kbd "C-c m d") #'cerebro-math-new-definition)
(global-set-key (kbd "C-c m l") #'cerebro-math-new-lemma)
(global-set-key (kbd "C-c m p") #'cerebro-math-new-proposition)
(global-set-key (kbd "C-c m c") #'cerebro-math-new-corollary)
(global-set-key (kbd "C-c m x") #'cerebro-math-new-example)
(global-set-key (kbd "C-c m r") #'cerebro-math-new-remark)
(global-set-key (kbd "C-c m e") #'cerebro-math-extract)          ; region -> its own note
(global-set-key (kbd "C-c m f") #'cerebro-math-find)             ; open one

;; -- Export & PDF (C-c e) ----------------------------------------------
;; Compile the note and read the result beside it, without leaving Emacs
;; (cerebro-pdf.el). `C-c e r' compiles *only* the result at point through
;; the `single' profile -- the fast way to check one theorem's typesetting.
(global-set-key (kbd "C-c e e") #'cerebro-pdf-export)   ; C-u: pick a profile
(global-set-key (kbd "C-c e r") #'cerebro-pdf-export-result)
(global-set-key (kbd "C-c e v") #'cerebro-pdf-view)
(global-set-key (kbd "C-c e d") #'cerebro-pdf-toggle-theme) ; theme colours <-> printed page
(global-set-key (kbd "C-c e b") #'cerebro-course-build-book-here) ; rebuild this course's book
;; A course is one source and seven documents: `c' builds one and shows
;; it, `a' builds them all and zips them (the file you hand over), `p'
;; opens one already built without rebuilding anything.
(global-set-key (kbd "C-c e c") #'cerebro-course-export)
(global-set-key (kbd "C-c e a") #'cerebro-course-export-all)
(global-set-key (kbd "C-c e p") #'cerebro-course-preview)
(global-set-key (kbd "C-c e s") #'cerebro-pdf-status)   ; why is there no PDF?

;; -- Look & feel (C-c u) -----------------------------------------------
;; Everything that changes how the editor *looks or reads* rather than
;; what it knows: the two theme variants, the body size, the reading
;; column, the status line, and the in-buffer rendering of formulas. One
;; prefix, so which-key can list the whole surface after `C-c u'.
;;
;; `u' as in "user interface": C-c t/s/g/h (tree, search, git, home) are
;; the things you *do*, this prefix is the room you do them in.
(global-set-key (kbd "C-c u t") #'cerebro-theme-toggle)             ; dark <-> light
(global-set-key (kbd "C-c u +") #'cerebro-theme-increase-font-size) ; the projector keys
(global-set-key (kbd "C-c u -") #'cerebro-theme-decrease-font-size)
(global-set-key (kbd "C-c u 0") #'cerebro-theme-set-font-size)      ; ...or name a size
(global-set-key (kbd "C-c u c") #'cerebro-theme-choose)             ; pick a look by name
(global-set-key (kbd "C-c u b") #'cerebro-code-breadcrumb-mode)     ; context header line
(global-set-key (kbd "C-c u f") #'cerebro-focus-mode)               ; centred column
(global-set-key (kbd "C-c u m") #'cerebro-modeline-mode)            ; status line off/on
(global-set-key (kbd "C-c u p") #'cerebro-preview-buffer)           ; render the maths
(global-set-key (kbd "C-c u l") #'cerebro-preview-live-mode)        ; ...and un-render at point
(global-set-key (kbd "C-c u i") #'cerebro-preview-figures)          ; compile src-block figures
(global-set-key (kbd "C-c u P") #'cerebro-preview-status)           ; why is nothing rendering?

;; Jump to anything visible on screen by typing what you can see. The
;; third way to move, next to `C-c s' (search the text) and `C-x b'
;; (complete a name) -- and the only one that needs no name at all.
(global-set-key (kbd "C-c j") #'avy-goto-char-timer)

;; Window layouts, now that there are sidebars and side windows to lose.
;; winner-mode's own C-c <left>/<right> are shadowed inside Org buffers
;; (org-shiftleft/right), so bind it somewhere Org does not claim.
(global-set-key (kbd "C-c w u") #'winner-undo)
(global-set-key (kbd "C-c w r") #'winner-redo)

;; cerebro-guix.el: the pinned environment, from inside Emacs.
(global-set-key (kbd "C-c G s") #'cerebro-guix-status)        ; what am I running in?
(global-set-key (kbd "C-c G m") #'cerebro-guix-find-manifest) ; guix.scm
(global-set-key (kbd "C-c G c") #'cerebro-guix-find-channels) ; the pin
(global-set-key (kbd "C-c G b") #'cerebro-guix-build)         ; materialise it
(global-set-key (kbd "C-c G r") #'cerebro-guix-run)           ; run a command in it
(global-set-key (kbd "C-c G R") #'cerebro-guix-repin)         ; re-pin the channels

(provide 'cerebro-keys)
