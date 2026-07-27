;; Isolated, reproducible environment for the cerebro second brain: Emacs +
;; Org-roam + the LaTeX toolchain + English spell-checking + git.
;;
;; `guix shell` with no arguments, run from this directory, picks this file
;; up automatically because it is named guix.scm -- that is intentional
;; (see makefile and README.org), not something to "fix" into a manifest.
;;
;; Reproducibility comes from guix/channels.scm, not from this file alone:
;; the real invocation is
;;   guix time-machine -C guix/channels.scm -- shell -- <command>
;; which is what .envrc and the makefile actually use.
;;
;; NOTE: authored without a working Guix install (guix is not installed on
;; the machine this was written on), so none of this has been build-tested.
;; Guix periodically reorganizes package modules (texlive-* in particular
;; has been restructured more than once); if a name below fails to
;; resolve, run `guix search <name>` or `guix show <name>` to find its
;; current module and fix the corresponding use-modules line.
;; taskwarrior/timewarrior are deliberately NOT in this list: they are
;; general system tools, installed at the OS level (see README.org), not
;; part of the isolated note-authoring toolchain.

(use-modules (gnu packages tex)
             (gnu packages base)
             (gnu packages emacs)
             (gnu packages emacs-xyz)
             (gnu packages version-control)
             (gnu packages aspell)
             (guix packages)
             (guix build-system trivial))

(package
  (name "cerebro-environment")
  (version "0.1")
  (source #f)
  (build-system trivial-build-system)
  (propagated-inputs
   (list
    ;; editor + zettelkasten
    emacs
    emacs-org-roam

    ;; LaTeX toolchain: pdflatex/xelatex/lualatex + latexmk + base packages.
    ;; Highest-risk line in this file -- see NOTE above.
    texlive-scheme-full

    ;; notes are written in English
    aspell
    aspell-dict-en

    ;; version control + basic GNU tools
    git
    coreutils))
  (synopsis "Isolated, reproducible Emacs/Org-mode/LaTeX environment for the cerebro second brain"))
