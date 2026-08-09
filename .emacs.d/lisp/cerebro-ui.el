;;; cerebro-ui.el --- window discipline -*- lexical-binding: t; -*-

;; There is no file tree, and that is a decision rather than an omission.
;; A tree answers "what is in this directory?", which is not a question
;; anyone has here: the questions are "which note was that", "which
;; course", "which conjecture" -- about *kinds of writing*, not about
;; paths. The archive already knows the kinds, so they are reached by key
;; (`C-c f', cerebro-find.el) and the sidebar it replaced is gone,
;; together with the two packages that drew it.
;;
;; What is left is window discipline: cerebro produces a lot of transient
;; report buffers (`cerebro-report' in cerebro-base.el, the CLI wrappers,
;; the guix compile buffers). Left to Emacs' default they split the frame
;; wherever they like and push the note you were reading off screen. Here
;; they get one predictable bottom side window.

(require 'cerebro-org)  ;; cerebro-root, org-directory
(require 'cerebro-guix)  ;; cerebro-guix-soft-require
(require 'cerebro-theme) ;; cerebro-theme-nerd-icons-p
(require 'dired)
(require 'winner)

;; -- dired, the substrate ----------------------------------------------
;; Human-readable sizes, directories first (a course directory should not
;; be buried among fifty note files), and `dired-dwim-target' so a second
;; dired window is the default destination when moving a note.
(setq dired-listing-switches "-alh --group-directories-first"
      dired-dwim-target t
      dired-kill-when-opening-new-dired-buffer t ; no pile of stale dired buffers
      dired-auto-revert-buffer t)                ; a note created by the CLI shows up

;; -- where transient buffers go ----------------------------------------
;; One rule, matched by buffer name, for everything cerebro pops up
;; (*cerebro*, *cerebro-cli*, *cerebro-guix*, plus *Help*): a bottom side
;; window of a third of the frame that never steals the window you are
;; writing in, and that `q' buries. Side windows are also immune to
;; `other-window' cycling by accident, which is the behaviour you want
;; from a report you are only reading.
;;
;; The buffer names are matched exactly, not by prefix: *cerebro-dashboard*
;; is a place you start from and must get a full window, and the Org
;; agenda is likewise a place you work, not a report you glance at (it
;; also manages its own windows via `org-agenda-window-setup').
;;
;; Exactly is right and hand-writing the alternation was not: the list
;; said it covered "everything cerebro pops up" and left out
;; *cerebro-results* -- which is `C-c r o', `C-c r i', and both dependency
;; views, i.e. the reports actually looked at most. They opened by
;; splitting whatever window was in front, which is the behaviour the rule
;; exists to prevent. One datum per buffer now, and the regexp is built
;; from it.
(defconst cerebro-ui-side-window-buffers
  '("*cerebro*"             ; the shared report buffer (cerebro-base.el)
    "*cerebro-results*"     ; the index, dependencies, what still owes a proof
    "*cerebro-query*"       ; the org-roam graph queries
    "*cerebro-help*"        ; the documentation surface (C-c H)
    "*cerebro-mode*"        ; which of the two jobs this session is doing
    "*cerebro-preview*"     ; why is nothing rendering (C-c u P)
    "*cerebro-scroll*"      ; the scroll trace (C-c u W)
    "*cerebro-backup*"        ; a backup running
    "*cerebro-backup-status*" ; what last backed up, and when
    "*cerebro-cli*"         ; output of a `cerebro ...' subcommand
    "*cerebro-guix*"        ; the environment report
    "*cerebro-guix-build*"  ; guix materialising the profile
    "*cerebro-guix-run*"    ; a guix command's transcript
    "*cerebro-export*"      ; a note or course compiling
    "*Help*")
  "Buffers that open in the bottom side window rather than splitting.

Reports and transcripts: things you glance at and dismiss with `q'. The
alternation this replaced named four of them, so the other eight -- the
results index, the queries, the help surface, every guix transcript --
each split whichever window happened to be in front.

Two deliberate absences, and they are not oversights:

  *cerebro-dashboard*  a place you start from, not a report. Full frame.
  *cerebro-pdf*        cerebro-pdf.el displays it itself, as a side
                       window on the RIGHT, beside the note it was
                       compiled from. Listing it here would not add a
                       rule, it would *override* that one:
                       `display-buffer-alist' takes precedence over the
                       ACTION argument passed to `display-buffer', so
                       the PDF would be yanked into a third of the frame
                       at the bottom.")

(add-to-list
 'display-buffer-alist
 `(,(concat "\\`" (regexp-opt cerebro-ui-side-window-buffers) "\\'")
   (display-buffer-in-side-window)
   (side . bottom)
   (slot . 0)
   (window-height . 0.33)
   (preserve-size . (nil . t))))

;; Window layouts are now something you can lose (a sidebar, a report, a
;; compile buffer), so make them undoable. `winner-mode's own C-c
;; <left>/<right> are shadowed by org-mode (org-shiftleft/right), hence
;; the explicit keys under C-c w -- see cerebro-keys.el.
(winner-mode 1)

;; -- Where did the cursor go? ------------------------------------------
;; With side windows, a sidebar and commands that jump across files, the
;; expensive moment is not the jump but the half second of hunting for
;; point afterwards. `pulsar' answers it by briefly lighting the line
;; landed on -- motion that is over before it can distract, and only after
;; commands that actually move you somewhere.
(when (cerebro-guix-soft-require 'pulsar)
  (setq pulsar-pulse t
        pulsar-delay 0.04       ; short: this is feedback, not animation
        pulsar-iterations 8)
  ;; Data: the commands worth a pulse are the ones that move point a long
  ;; way -- cerebro's own jumps included, since they land in a file you
  ;; were not looking at.
  ;;
  ;; This list had it precisely backwards. `cerebro-results-dependencies'
  ;; and `-dependents' were in it and move point nowhere: they render a
  ;; report with `cerebro-report' and leave you where you were, so the
  ;; pulse lit the line you were already looking at. The commands that
  ;; *do* land you in another file -- the whole of cerebro-nav.el, which
  ;; exists to be "the results graph as movement" -- were absent, so the
  ;; one case the feature was bought for got nothing.
  (dolist (command '(other-window
                     winner-undo winner-redo
                     org-next-visible-heading org-previous-visible-heading
                     org-agenda-goto org-agenda-switch-to
                     ;; cerebro-nav.el: these jump, often across files.
                     cerebro-nav-result
                     cerebro-nav-next-result cerebro-nav-previous-result
                     cerebro-nav-next-unproved
                     recenter-top-bottom))
    (add-to-list 'pulsar-pulse-functions command))
  (pulsar-global-mode 1))

;; `avy' is the third way to move, next to search (C-c s) and completion
;; (C-x b): type a couple of characters you can *see* on screen and jump
;; there. It is the fastest way through a long proof, where the target has
;; no name to search for and no heading to complete.
(when (cerebro-guix-soft-require 'avy)
  (setq avy-timeout-seconds 0.3 ; how long it waits before showing the keys
        avy-all-windows t       ; including the other note in the split
        avy-style 'at-full))

;; -- small, built-in comforts ------------------------------------------
(setq use-short-answers t)          ; y/n instead of typing "yes" <RET>
(setq window-resize-pixelwise t)
(setq switch-to-buffer-obey-display-actions t) ; the rules above always win
(global-so-long-mode 1)             ; a pathological generated file can't hang Emacs

(provide 'cerebro-ui)
