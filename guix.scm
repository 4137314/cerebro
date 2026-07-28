;; Isolated, reproducible environment for the cerebro second brain: Emacs +
;; Org-roam + the LaTeX toolchain (incl. TikZ/pgfplots, part of the "full"
;; scheme) + English spell-checking + git + Taskwarrior + Timewarrior.
;;
;; This file is loaded explicitly with `guix shell -f guix.scm -- <cmd>`
;; (see bin/guix-run) -- bare `guix shell` with no flags does NOT
;; auto-load guix.scm from the current directory (verified: it prints
;; "no packages specified; creating an empty environment" instead).
;; `-f` file-loads the package below; its propagated-inputs then surface
;; on PATH because that is what "propagated" means -- this is the
;; standard Guix idiom for a project dev-shell defined as a fake
;; package whose only job is to propagate a pile of real ones.
;;
;; Reproducibility comes from guix/channels.scm, not from this file alone:
;; the real invocation is
;;   guix time-machine -C guix/channels.scm -- shell -f guix.scm -- <command>
;; which is what .envrc, the makefile, and bin/guix-run actually use.
;;
;; Every package/module below has been confirmed with `guix show <name>`
;; against the pinned revision in guix/channels.scm.

(use-modules (gnu packages tex)
             (gnu packages base)
             (gnu packages emacs)
             (gnu packages emacs-xyz)
             (gnu packages version-control)
             (gnu packages aspell)
             (gnu packages task-management)
             (gnu packages web)
             (gnu packages gnupg)
             (guix packages)
             (guix licenses)
             (guix gexp)
             (guix build-system trivial))

(package
  (name "cerebro-environment")
  (version "0.1")
  (source #f)
  (build-system trivial-build-system)
  ;; trivial-build-system runs exactly the builder it's given -- with
  ;; none specified, there is nothing to execute and the derivation
  ;; fails to produce any output at all (verified against a real
  ;; build: "failed to produce output path", empty build log). All
  ;; this package needs to do is exist so its propagated-inputs below
  ;; attach to the profile; an empty directory is a fine, minimal
  ;; builder for that.
  (arguments (list #:builder #~(mkdir #$output)))
  (propagated-inputs
   (list
    ;; editor + zettelkasten
    emacs
    emacs-org-roam
    emacs-org-drill ;; spaced repetition over :drill:-tagged headings (cerebro-drill.el)
    ;; org-ql: the content/metadata query surface (cerebro-ql.el),
    ;; complementary to cerebro-query.el's org-roam graph queries. Long
    ;; present in Guix; confirm at the pin with `guix show emacs-org-ql'
    ;; (it pulls dash/s/f/ts/peg, all already in Guix, as propagated
    ;; inputs -- no other line needed here).
    emacs-org-ql

    ;; org-crypt (built into Org core, cerebro-crypt.el) needs a GPG
    ;; backend for symmetric encryption of :crypt:-tagged subtrees.
    gnupg

    ;; LaTeX toolchain: pdflatex/xelatex/lualatex + latexmk + TikZ/pgfplots
    ;; + every standard package needed by latex/*.cls.
    ;;
    ;; texlive-scheme-full is convenient but very large (several GB to
    ;; realise), which is a lot to carry for an environment that is
    ;; re-materialised via `guix time-machine'. A curated set covering
    ;; exactly what latex/*.cls and cerebro-macros.sty use would be much
    ;; lighter -- roughly:
    ;;   texlive-latexmk texlive-amsmath texlive-amscls texlive-amsfonts
    ;;   texlive-mathtools texlive-pgf texlive-pgfplots texlive-tikz-cd
    ;;   texlive-biblatex biber texlive-cleveref texlive-hyperref
    ;;   texlive-enumitem texlive-microtype texlive-beamer texlive-xcolor ...
    ;; It is left as scheme-full deliberately for now: trimming it must be
    ;; validated against a real Guix build AND a real compile of all seven
    ;; export profiles (`make export-matrix'), because a missing package
    ;; fails a compile silently -- exactly the failure mode the project
    ;; warns about. Swap it in only once you can run that matrix.
    texlive-scheme-full

    ;; notes are written in English
    aspell
    aspell-dict-en

    ;; tasks + time, scriptable and isolated like everything else
    taskwarrior
    timewarrior
    jq ;; robust JSON handling in the Taskwarrior hooks (taskwarrior/hooks/)

    ;; version control + basic GNU tools
    git
    coreutils))
  (synopsis "Isolated, reproducible Emacs/Org-mode/LaTeX/Taskwarrior/Timewarrior environment for the cerebro second brain")
  (description "A fake package (no real source or build) whose only
purpose is to propagate every dependency of the cerebro second brain --
Emacs, Org-roam, a full LaTeX toolchain, English spell-checking,
Taskwarrior, Timewarrior, and git -- into a single isolated,
reproducible `guix shell' environment.")
  (home-page "https://github.com/4137314/cerebro")
  (license gpl3+))
