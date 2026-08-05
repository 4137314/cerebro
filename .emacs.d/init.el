;;; init.el --- cerebro Emacs entry point -*- lexical-binding: t; -*-

;; Thin loader on purpose: the real modules live in lisp/ as ordinary,
;; independently loadable .el files, not a tangled literate config -- so
;; startup has no build step that can silently go stale.
;;
;; Every optional package this loads (org-roam, org-ql, org-drill) comes
;; from guix.scm and is already on `load-path' by the time Emacs starts
;; inside the guix environment. Nothing here calls
;; package-install/straight.el/MELPA at runtime: isolation is only real if
;; the package set never depends on the network. See guix.scm and README.org.

(add-to-list 'load-path (expand-file-name "lisp" (file-name-directory load-file-name)))

;; -- Core modules ------------------------------------------------------
;; Pure Elisp on top of Emacs core only (org, ox-latex, org-clock,
;; org-crypt, ...). No guix-only package is pulled in here, so these load
;; anywhere -- and a failure in one is a *real* bug, not a missing
;; dependency, so they are required unguarded (loudly). `cerebro-session'
;; goes first so backups/lock-files are redirected before any note is
;; touched.
(require 'cerebro-org)
(require 'cerebro-session)
(require 'cerebro-latex)
(require 'cerebro-results) ; logical-dependency graph over named results
(require 'cerebro-agenda)  ; agenda views (morning review, issues)
(require 'cerebro-time)
(require 'cerebro-issues)
(require 'cerebro-cli)      ; drive the `cerebro' CLI from Emacs
(require 'cerebro-crypt)
(require 'cerebro-appearance)

;; -- Optional modules --------------------------------------------------
;; Each of these pulls a guix-only Emacs package (org-roam, org-ql,
;; org-drill) with no MELPA/straight.el fallback, on purpose. Inside
;; `make shell' (the normal launch path) every one is present and this
;; loop is a plain sequence of successful requires.
;;
;; Outside the guix environment those packages are simply absent -- and a
;; second brain "meant to last" should degrade rather than refuse to
;; start. So load them best-effort: a missing one is collected and
;; reported once, and the pure half (agenda, capture, the LaTeX export
;; pipeline, the taxonomy) keeps working. This is not a network fallback
;; -- nothing is fetched -- only a promise that one absent Guix package
;; never bricks the editor.
(defvar cerebro-unavailable-modules nil
  "Alist of (MODULE . MESSAGE) for optional modules that failed to load,
normally because their guix.scm package isn't on `load-path' (i.e. Emacs
was started outside the guix environment). Empty on the normal path.")

(dolist (module '(cerebro-roam cerebro-ql cerebro-query cerebro-drill))
  (condition-case err
      (require module)
    (error (push (cons module (error-message-string err))
                 cerebro-unavailable-modules))))

(when cerebro-unavailable-modules
  (display-warning
   'cerebro
   (format (concat "Running without: %s.\n"
                   "These need their org-roam/org-ql/org-drill packages, which come from\n"
                   "guix.scm -- launch inside the pinned environment (`make shell', the\n"
                   "`cerebro' launcher, or `direnv allow') to enable them. The rest of the\n"
                   "config (agenda, capture, LaTeX export, taxonomy) is running normally.")
           (mapconcat (lambda (m) (symbol-name (car m)))
                      (reverse cerebro-unavailable-modules) ", "))
   :warning))

;; Keys last: it only references command *symbols*, so binding a key to a
;; command from an optional module that didn't load is harmless (the key
;; simply reports a void command if pressed in the degraded, outside-guix
;; mode).
(require 'cerebro-keys)
