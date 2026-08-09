;;; cerebro-session.el --- file & session hygiene -*- lexical-binding: t; -*-

;; Everything here is Emacs core (no new guix package, like
;; cerebro-appearance.el): the point is to keep a plain-text, git-versioned
;; notes repo *clean and self-consistent* as it is edited day to day.
;;
;; Three concerns, all funnelled into one gitignored `var/' directory so
;; the tree never accumulates stray state:
;;
;;   1. Customize writes to its own file, never into the versioned init.el.
;;      By default `M-x customize', an interactive `load-theme', a saved
;;      safe-local-variable, etc. append a `custom-set-variables' block to
;;      `user-init-file' -- here a *tracked* file. Redirect that to a
;;      gitignored custom.el so hand-written config and machine-written
;;      config never fight over init.el.
;;   2. Backups (foo~), auto-saves (#foo#) and lock files (.#foo) stay out
;;      of notes/. By default Emacs drops all three next to the file being
;;      edited -- untracked litter in every notes directory (and .#foo lock
;;      symlinks next to a :crypt: file are exactly the kind of noise a
;;      single-user second brain doesn't want). Redirect them under var/.
;;   3. A little harmless persistence -- recent files, minibuffer history,
;;      and cursor position per file -- so reopening the database feels
;;      continuous across sessions. All three are built into Emacs.

(require 'cerebro-base) ;; for `cerebro-root' -- which is where it lives
(require 'recentf)
(require 'savehist)
(require 'saveplace)

(defvar cerebro-var-dir
  (expand-file-name ".emacs.d/var/" cerebro-root)
  "Repo-local, gitignored directory for Emacs' own generated state.
Kept out of source control (see .gitignore): everything under here --
custom.el, backups/, auto-saves/, and the recentf/savehist/save-place
files -- is rebuildable machine state, not part of the second brain.")

(make-directory (expand-file-name "backups" cerebro-var-dir) t)
(make-directory (expand-file-name "auto-saves" cerebro-var-dir) t)

;; -- 1. Customize out of the tracked init.el ---------------------------
(setq custom-file (expand-file-name "custom.el" cerebro-var-dir))
(when (file-exists-p custom-file)
  (load custom-file nil t))

;; -- 2. Backups / auto-saves / lock files out of the notes tree --------
(setq backup-directory-alist
      `((".*" . ,(expand-file-name "backups" cerebro-var-dir))))
(setq auto-save-file-name-transforms
      ;; The trailing t uniquifies, so two same-named notes in different
      ;; course dirs don't collide on one auto-save file.
      `((".*" ,(expand-file-name "auto-saves/" cerebro-var-dir) t)))
(setq auto-save-list-file-prefix
      (expand-file-name "auto-saves/.saves-" cerebro-var-dir))
(setq backup-by-copying t      ; don't clobber a note's inode / break a hard link
      version-control t        ; keep numbered backups
      delete-old-versions t    ; ...but prune them automatically
      kept-new-versions 6
      kept-old-versions 2)

;; Lock files (.#foo, a symlink alongside the file) guard against two
;; Emacsen editing the same buffer at once -- not a case that arises for a
;; single-user notes repo driven by one daemon, and org-crypt already
;; disables auto-save for :crypt: subtrees (cerebro-crypt.el). Skip the
;; symlink noise. Re-enable with `(setq create-lockfiles t)' if you ever
;; run more than one independent Emacs against these notes.
(setq create-lockfiles nil)

;; -- 3. Session persistence (all built-in) -----------------------------
(setq recentf-save-file (expand-file-name "recentf" cerebro-var-dir))
(setq recentf-max-saved-items 200)
(recentf-mode 1)

(setq savehist-file (expand-file-name "history" cerebro-var-dir))
(savehist-mode 1)

(setq save-place-file (expand-file-name "places" cerebro-var-dir))
(save-place-mode 1)

(provide 'cerebro-session)
