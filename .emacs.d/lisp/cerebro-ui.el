;;; cerebro-ui.el --- file tree, window discipline, key discovery -*- lexical-binding: t; -*-

;; The notes tree is a real, browsable filesystem (notes/, notes/courses/,
;; notes/daily/, issues/, latex/) and reading it as a *tree* is often the
;; fastest way to find your bearings -- especially for a course, where the
;; directory layout carries meaning the org-roam graph doesn't.
;;
;; The sidebar here is `dired-sidebar', which is not a new file manager:
;; it is ordinary `dired' pinned in a side window, plus `dired-subtree' to
;; expand a directory *in place* instead of replacing the listing. That
;; choice is deliberate over a heavier tree package (treemacs & co.):
;; every key you already know in dired works in it, it needs no icon
;; fonts (see the `ascii' theme below -- it renders identically in a
;; terminal), and if the package ever disappears the fallback is `C-x d',
;; which will still exist in twenty years.
;;
;; The second half of this file is window discipline: cerebro produces a
;; lot of transient report buffers (`cerebro-report' in cerebro-org.el,
;; the CLI wrappers, the guix compile buffers). Left to Emacs' default
;; they split the frame wherever they like and push the note you were
;; reading off screen. Here they get one predictable bottom side window.
;;
;; Loaded through `cerebro-guix-soft-require': outside the pinned
;; environment the window rules and the dired settings still apply, only
;; the sidebar command reports that its package is missing.

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

(when (cerebro-guix-soft-require 'dired-subtree)
  ;; TAB expands/collapses a directory inline -- this is what turns dired
  ;; into a tree, in the sidebar *and* in any ordinary dired buffer.
  (define-key dired-mode-map (kbd "TAB") #'dired-subtree-toggle)
  (define-key dired-mode-map (kbd "<backtab>") #'dired-subtree-cycle))

;; -- the sidebar -------------------------------------------------------
;; File-type icons in the tree and in any dired buffer, from the Nerd
;; Font (glyphs, not images -- so this works in a terminal frame too).
(when (and (cerebro-guix-soft-require 'nerd-icons-dired)
           (cerebro-theme-nerd-icons-p))
  (add-hook 'dired-mode-hook #'nerd-icons-dired-mode))

(when (cerebro-guix-soft-require 'dired-sidebar)
  (setq dired-sidebar-theme 'ascii ; +/- markers: no icon font, works in -nw
        dired-sidebar-width 32
        dired-sidebar-use-custom-font nil
        ;; NOT `dired-sidebar-should-follow-file': it re-roots the sidebar
        ;; on a timer to `dired-sidebar-get-dir-to-show', which for a file
        ;; buffer is the *project* root -- i.e. always this repository. It
        ;; therefore silently undoes the `notes/' rooting a second after
        ;; the toggle, and makes the `C-u' prefix below (whole repo) mean
        ;; nothing, since both end up at the repo. Verified on screen:
        ;; `C-c t' came up showing bin/, guix.scm, README.org. A tree
        ;; whose root is what you asked for is worth more than one that
        ;; scrolls itself; `g' in the sidebar refreshes it.
        dired-sidebar-should-follow-file nil
        dired-sidebar-refresh-on-special-commands t
        ;; Keep the sidebar out of `delete-other-windows' (C-x 1): losing
        ;; the tree every time you maximise a note is pure friction.
        dired-sidebar-no-delete-other-windows t)
  (add-hook 'dired-sidebar-mode-hook
            (lambda ()
              ;; Permissions/owner/size are noise in a navigation pane.
              (dired-hide-details-mode 1)
              (setq-local truncate-lines t))))

;;;###autoload
(defun cerebro-ui-toggle-tree (&optional whole-repo)
  "Toggle the file-tree sidebar, rooted at the notes tree.
With a prefix argument (WHOLE-REPO), root it at the repository instead --
notes/ is where you live day to day, but latex/, bin/ and issues/ are
sometimes what you actually want to browse."
  (interactive "P")
  (unless (fboundp 'dired-sidebar-toggle-sidebar)
    (user-error "dired-sidebar is missing -- see M-x cerebro-guix-status"))
  (dired-sidebar-toggle-sidebar (if whole-repo cerebro-root org-directory)))

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
(add-to-list
 'display-buffer-alist
 '("\\`\\*\\(cerebro\\|cerebro-cli\\|cerebro-guix\\|Help\\)\\*\\'"
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
  (dolist (command '(other-window
                     winner-undo winner-redo
                     org-next-visible-heading org-previous-visible-heading
                     org-agenda-goto org-agenda-switch-to
                     cerebro-results-dependencies cerebro-results-dependents
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
