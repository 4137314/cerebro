;;; cerebro-vc.el --- git for a repository you write prose into -*- lexical-binding: t; -*-

;; The second brain *is* a git repository: notes, the issue tracker, the
;; LaTeX classes and the environment pin are all versioned, and the
;; project's own gates are git hooks (githooks/pre-commit parses the
;; staged Org, post-commit runs `make test', pre-push runs `make lint' +
;; the export matrix). Committing is therefore a daily, in-editor
;; operation, not an occasional trip to a terminal -- which is exactly
;; what Magit is for, and why it earns its place in guix.scm.
;;
;; Two things matter more here than in a code repository:
;;
;;   1. Buffers must be saved before staging. A half-typed note that is
;;      still only in a buffer is invisible to `git add', and the commit
;;      that "obviously" contained it silently doesn't.
;;   2. The hooks' output must be visible. `make test' running in
;;      post-commit is the project's safety net; Magit shows it in its
;;      process buffer, so a failing gate is something you *see*.
;;
;; Loaded soft, like every other guix.scm package: without magit this
;; module is a no-op and `C-x v ...' (built-in VC) still works.

(require 'cerebro-org)  ;; cerebro-root
(require 'cerebro-guix) ;; cerebro-guix-soft-require

(when (cerebro-guix-soft-require 'magit)
  ;; Save note buffers before any git operation reads the worktree --
  ;; see (1) above. `dontask' rather than t: being prompted "save 4
  ;; buffers?" every single time trains you to answer without reading.
  (setq magit-save-repository-buffers 'dontask)

  ;; Word-level diffs inside the hunk you are looking at: prose diffs are
  ;; unreadable line-by-line when a paragraph is re-wrapped.
  (setq magit-diff-refine-hunk t)

  ;; Commit messages are prose too -- wrap them like Org, and flag a
  ;; summary line that has grown into a paragraph.
  (add-hook 'git-commit-setup-hook #'turn-on-auto-fill)

  ;; `C-x g' is Magit's own global binding; cerebro adds `C-c g' next to
  ;; the other one-key project commands (cerebro-keys.el).
  (setq magit-repository-directories `((,cerebro-root . 0))))

(provide 'cerebro-vc)
