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
      "C-c e" "export & PDF"
      "C-c b" "bibliography"
      "C-c B" "backups"
      "C-c M" "mode: math / dev"
      "C-c H" "docs & settings"
      "C-c f" "find a file, by kind")))

(global-set-key (kbd "C-c n f") #'org-roam-node-find)
(global-set-key (kbd "C-c n i") #'org-roam-node-insert)
(global-set-key (kbd "C-c n c") #'org-roam-capture)
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
;; ...and the same graph as *movement* rather than as a report
;; (cerebro-nav.el): jump to any result, walk the ones in this note, walk
;; the ones that still owe a proof, see what links here, and write a
;; `#+DEPENDS:' whose names are real.
(global-set-key (kbd "C-c r j") #'cerebro-nav-result)
(global-set-key (kbd "C-c r n") #'cerebro-nav-next-result)
(global-set-key (kbd "C-c r p") #'cerebro-nav-previous-result)
(global-set-key (kbd "C-c r u") #'cerebro-nav-next-unproved)
(global-set-key (kbd "C-c r b") #'cerebro-nav-backlinks)
(global-set-key (kbd "C-c r D") #'cerebro-nav-insert-depends)

;; The documentation this repository already writes, reachable from
;; inside it (cerebro-help.el). `H' for help, capitalised like the other
;; infrastructure prefixes.
(global-set-key (kbd "C-c H h") #'cerebro-help-manual)
(global-set-key (kbd "C-c H c") #'cerebro-help-conventions)
(global-set-key (kbd "C-c H b") #'cerebro-help-brief)
(global-set-key (kbd "C-c H d") #'cerebro-help-document)
(global-set-key (kbd "C-c H k") #'cerebro-help-keys)
(global-set-key (kbd "C-c H v") #'cerebro-help-configuration)
(global-set-key (kbd "C-c H m") #'cerebro-help-modules)
(global-set-key (kbd "C-c H ?") #'cerebro-menu)
;; The archive is writable; the machinery is not (cerebro-isolation.el).
;; This is the deliberate way across that line, and it says so.
(global-set-key (kbd "C-c H u") #'cerebro-isolation-unlock)
(global-set-key (kbd "C-c H i") #'cerebro-isolation-status)

(global-set-key (kbd "C-c r c") #'cerebro-results-check)        ; cycles/dangling/dups
(global-set-key (kbd "C-c r o") #'cerebro-results-open)         ; what still owes a proof

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
;; -- Reaching a file by what it is (C-c f) -----------------------------
;; There is no file tree. A tree answers "what is in this directory?",
;; which is not a question anyone has here -- the questions are about
;; *kinds of writing*, and the archive knows the kinds. Everything
;; completes over titles, never over file names, because a note in
;; notes/math/ is called `a3f19c04b2e7.org' (cerebro-hash.el).
(global-set-key (kbd "C-c f n") #'cerebro-find-note)         ; any note
(global-set-key (kbd "C-c f m") #'cerebro-find-math)         ; notes/math/
(global-set-key (kbd "C-c f j") #'cerebro-find-conjecture)   ; notes/conjectures/
(global-set-key (kbd "C-c f c") #'cerebro-find-course)       ; notes/courses/
(global-set-key (kbd "C-c f r") #'cerebro-nav-result)        ; a named result
(global-set-key (kbd "C-c f i") #'cerebro-find-issues)
(global-set-key (kbd "C-c f b") #'cerebro-find-bibliography)

(global-set-key (kbd "C-c h") #'cerebro-dashboard)    ; Home: the start page
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
(global-set-key (kbd "C-c m j") #'cerebro-math-new-conjecture)   ; -> notes/conjectures/
(global-set-key (kbd "C-c m e") #'cerebro-math-extract)          ; region -> its own note
(global-set-key (kbd "C-c m f") #'cerebro-math-find)             ; open one
;; The maturity ladder as an operation: a state nobody can change with a
;; keystroke is a state nobody updates.
(global-set-key (kbd "C-c m s") #'cerebro-math-set-maturity)     ; seed/growing/evergreen
(global-set-key (kbd "C-c m +") #'cerebro-math-promote)          ; one rung up

;; -- Export & PDF (C-c e) ----------------------------------------------
;; Compile the note and read the result beside it, without leaving Emacs
;; (cerebro-pdf.el). `C-c e r' compiles *only* the result at point through
;; the `single' profile -- the fast way to check one theorem's typesetting.
(global-set-key (kbd "C-c e e") #'cerebro-pdf-export)   ; C-u: pick a profile
(global-set-key (kbd "C-c e r") #'cerebro-pdf-export-result)
(global-set-key (kbd "C-c e v") #'cerebro-pdf-view)
(global-set-key (kbd "C-c e d") #'cerebro-pdf-toggle-theme) ; theme colours <-> printed page
(global-set-key (kbd "C-c e w") #'cerebro-pdf-watch-mode)  ; rebuild on every save
;; A course is ONE file and four documents: `c' builds one and shows it,
;; `a' builds them all and zips them (the file you hand over), `p' opens
;; one already built without rebuilding, `o' opens a course to edit.
(global-set-key (kbd "C-c e c") #'cerebro-course-export)
(global-set-key (kbd "C-c e a") #'cerebro-course-export-all)
(global-set-key (kbd "C-c e p") #'cerebro-course-preview)
(global-set-key (kbd "C-c e o") #'cerebro-course-find)  ; open a course
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
;; What you are *doing* to this note: source (the file as it is) / write
;; (the working mode) / study (rendered, centred, no timers). One key
;; cycles, two go straight to an end of the range -- and the mode is in
;; the status line, so it is never a guess. See cerebro-study.el.
(global-set-key (kbd "C-c u s") #'cerebro-study-cycle)              ; source -> write -> study
(global-set-key (kbd "C-c u S") #'cerebro-study-set)                ; ...or pick one
(global-set-key (kbd "C-c u r") #'cerebro-study-read)               ; straight to study
(global-set-key (kbd "C-c u o") #'cerebro-study-source)             ; straight to source

(global-set-key (kbd "C-c u p") #'cerebro-preview-buffer)           ; render the maths
(global-set-key (kbd "C-c u l") #'cerebro-preview-live-mode)        ; ...and un-render at point
(global-set-key (kbd "C-c u i") #'cerebro-preview-figures)          ; compile src-block figures
(global-set-key (kbd "C-c u P") #'cerebro-preview-status)           ; why is nothing rendering?
;; Formula size *relative to the prose*, live. Distinct from C-c u +/-,
;; which move the body text and take the formulas along with it: these
;; two move the formulas against it.
(global-set-key (kbd "C-c u ]") #'cerebro-preview-enlarge)
(global-set-key (kbd "C-c u [") #'cerebro-preview-shrink)
(global-set-key (kbd "C-c u R") #'cerebro-preview-rebuild-format)   ; after a TeX upgrade
;; Render the whole archive's formulas once, so reading is cache hits
;; afterwards: a warmed note opens in ~35ms instead of ~1s per fragment.
(global-set-key (kbd "C-c u w") #'cerebro-preview-warm)
;; When the window jumps while scrolling: turn this on, scroll until it
;; misbehaves, then `C-c u W' names the command that pulled it back.
(global-set-key (kbd "C-c u T") #'cerebro-scroll-trace-mode)
(global-set-key (kbd "C-c u W") #'cerebro-scroll-trace-report)

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


;; -- One prompt for the whole surface ----------------------------------
;; There are now some seventy cerebro commands behind eight prefixes.
;; which-key answers "what can follow C-c u?"; this answers the other
;; question -- "there is a command for this, what is it called?" -- by
;; listing every one of them with its key and its first line of
;; documentation, in the same completion UI as everything else.
;;
;; Built by introspection, not from a list: any command defined later
;; shows up here without being registered anywhere, which is the only
;; kind of menu that stays true.

(defun cerebro-menu-commands ()
  "Every interactive cerebro command, as symbols."
  (sort (apropos-internal "\\`cerebro-" #'commandp) #'string<))

(defun cerebro-menu-line (command)
  "COMMAND as one line: name, key binding, first line of its docstring."
  (let* ((keys (where-is-internal command nil t))
         (doc (or (car (split-string (or (documentation command) "") "\n")) "")))
    (format "%-34s %-12s %s"
            (symbol-name command)
            (if keys (key-description keys) "")
            doc)))

;;;###autoload
(defun cerebro-menu ()
  "Pick any cerebro command by name, key or description (`C-c ?').
Orderless matching means the words can come in any order: type `pdf
theme' or `note new'."
  (interactive)
  (let* ((rows (mapcar (lambda (command) (cons (cerebro-menu-line command) command))
                       (cerebro-menu-commands)))
         (choice (completing-read "cerebro: " (mapcar #'car rows) nil t)))
    (call-interactively (cdr (assoc choice rows)))))

(global-set-key (kbd "C-c ?") #'cerebro-menu)

;; -- Repeating what you just did ---------------------------------------
;; `repeat-mode' (built into Emacs 28+) lets the last key of a sequence
;; repeat the command. It matters for exactly the ones you press several
;; times in a row: growing the text on a projector, and walking a note up
;; the maturity ladder. Everything else keeps its full binding.
(defvar cerebro-repeat-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "+") #'cerebro-theme-increase-font-size)
    (define-key map (kbd "-") #'cerebro-theme-decrease-font-size)
    map)
  "Keys that repeat with a single character after `C-c u + / -'.")

(dolist (command '(cerebro-theme-increase-font-size cerebro-theme-decrease-font-size))
  (put command 'repeat-map 'cerebro-repeat-map))

(when (fboundp 'repeat-mode) (repeat-mode 1))

;; Backups: the policy is data (cerebro-backup.el), these are the two
;; things you ever do with it.
;; Backups moved to the SHIFTED prefix when citations took `C-c b'. Not
;; arbitrary: `C-c G' (the guix environment) is already the pattern here
;; -- a capital prefix is infrastructure you touch monthly, a lowercase
;; one is something you do while writing. Citing a paper is the second
;; kind; running a backup is the first.
(global-set-key (kbd "C-c B b") #'cerebro-backup)
(global-set-key (kbd "C-c B s") #'cerebro-backup-status)
(global-set-key (kbd "C-c B r") #'cerebro-backup-run)

;; -- The two jobs (C-c M) ----------------------------------------------
;; math or dev: study the archive, or maintain the machinery that holds
;; it (cerebro-mode.el). A capital prefix, like `C-c G' and `C-c B',
;; because it is infrastructure -- something you set when you sit down,
;; not something you press while writing. `C-c M t' is the whole feature
;; on one key: with exactly two modes, "the other one" is unambiguous.
;;
;; Every one of these takes a prefix argument (`C-u') to change this
;; session only, leaving the remembered mode alone.
(global-set-key (kbd "C-c M m") #'cerebro-mode-math)   ; the archive
(global-set-key (kbd "C-c M d") #'cerebro-mode-dev)    ; the machinery
(global-set-key (kbd "C-c M t") #'cerebro-mode-toggle) ; the other one
(global-set-key (kbd "C-c M s") #'cerebro-mode-status) ; what is in force, and why

;; -- Bibliography (C-c b) ----------------------------------------------
;; One bibliography for the whole archive (bib/references.bib,
;; cerebro-bib.el). These four are the whole citation workflow: cite
;; something, add something to cite, import an entry someone sent you,
;; and go read the thing.
(global-set-key (kbd "C-c b i") #'cerebro-bib-insert)  ; [cite:@key], with completion
(global-set-key (kbd "C-c b n") #'cerebro-bib-new)     ; a new entry, field by field
(global-set-key (kbd "C-c b y") #'cerebro-bib-yank)    ; import from the kill ring
(global-set-key (kbd "C-c b o") #'cerebro-bib-open)    ; open what it points at
(global-set-key (kbd "C-c b f") #'cerebro-bib-find)    ; open the bibliography

(provide 'cerebro-keys)
