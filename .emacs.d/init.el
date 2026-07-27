;;; init.el --- cerebro Emacs entry point -*- lexical-binding: t; -*-

;; Thin loader on purpose: the real modules live in lisp/ as ordinary,
;; independently loadable .el files, not a tangled literate config -- so
;; startup has no build step that can silently go stale.
;;
;; Every package this loads (org-roam, ...) comes from guix.scm and is
;; already on `load-path' by the time Emacs starts inside the guix
;; environment. Nothing here calls package-install/straight.el/MELPA at
;; runtime: isolation is only real if the package set never depends on
;; the network. See guix.scm and README.org.

(add-to-list 'load-path (expand-file-name "lisp" (file-name-directory load-file-name)))

(require 'cerebro-org)
(require 'cerebro-roam)
(require 'cerebro-latex)
(require 'cerebro-time)
(require 'cerebro-issues)
(require 'cerebro-keys)
