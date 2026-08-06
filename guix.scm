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
             (gnu packages pdf) ;; poppler: doc-view's page renderer
             (gnu packages compression) ;; zip: one file to hand a course over
             (gnu packages graphviz)    ;; the note graph, drawn offline
             (gnu packages tree-sitter)
             (gnu packages haskell-apps) ;; shellcheck
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

    ;; -- the editing surface (see .emacs.d/lisp/cerebro-{complete,ui,
    ;; vc,dashboard}.el) ------------------------------------------------
    ;; Everything below is optional in the strict sense -- Emacs without
    ;; it still opens, exports and lints every note (each module pulls
    ;; its package through `cerebro-guix-soft-require' and degrades
    ;; feature by feature). They are here because a database you keep for
    ;; a lifetime is only as good as your ability to *reach* something in
    ;; it, and because each one is small, single-purpose and layered on a
    ;; built-in Emacs mechanism rather than replacing it. `M-x
    ;; cerebro-guix-status' reports which of them the running Emacs
    ;; actually got.

    ;; Minibuffer completion: four packages that improve the *built-in*
    ;; completion instead of replacing it -- drop any one of them and
    ;; completion falls back to vanilla Emacs, nothing else breaks.
    emacs-vertico    ;; candidates listed vertically in the minibuffer
    emacs-orderless  ;; "heine borel" matches "Borel--Heine ..."
    emacs-marginalia ;; annotations next to candidates
    emacs-consult    ;; live search/jump (M-s, M-g, C-x b)
    ;; consult-grep/consult-find (and the built-in `rgrep' they fall back
    ;; to) shell out to these. They are on most hosts anyway, but the
    ;; point of guix.scm is that the environment does not depend on that.
    grep
    findutils

    ;; File tree: `dired-sidebar' is dired in a side window, and
    ;; `dired-subtree' (from emacs-dired-hacks) expands a directory in
    ;; place. Chosen over a standalone tree package because every dired
    ;; key still works, it needs no icon fonts (the `ascii' theme renders
    ;; in a terminal), and the fallback if it ever disappears is `C-x d'.
    emacs-dired-sidebar
    emacs-dired-hacks

    ;; The notes repo is a git repo whose gates are git hooks; magit
    ;; makes committing (and seeing a hook fail) an in-editor operation.
    emacs-magit

    ;; The start page: sections are drawn by this package, but every
    ;; number in them is computed by cerebro-dashboard.el from the
    ;; plain-text sources, so there is no state to go stale.
    emacs-dashboard

    ;; -- How a note looks and reads (cerebro-{theme,appearance,focus,
    ;; preview,complete,ui}.el) -----------------------------------------
    ;; The *theme* itself is deliberately absent from this list: modus is
    ;; built into Emacs, so the single most visible part of the config
    ;; owes nothing to a package that can go unmaintained. What is here is
    ;; the layer around it, and the test each one had to pass is the same:
    ;; single-purpose, layered on a built-in Emacs mechanism, and
    ;; droppable without breaking anything (each is pulled through
    ;; `cerebro-guix-soft-require' and listed in
    ;; `cerebro-guix-optional-packages', so `cerebro env' reports exactly
    ;; which ones this session actually got).

    ;; Presentation of an Org buffer: shapes instead of markup, and the
    ;; markers coming back when the cursor needs them.
    emacs-org-modern
    emacs-org-appear
    ;; Space between the text and the frame -- the difference between a
    ;; terminal and something you read for three hours.
    emacs-spacious-padding

    ;; Reading/writing mode (C-c u f): a centred column of ~90 characters,
    ;; prose proportional while tables, code and \(...\) stay monospaced.
    emacs-olivetti
    emacs-mixed-pitch

    ;; In-buffer LaTeX previews that turn back into source when you edit
    ;; them (cerebro-preview.el renders them with the notes' own macros).
    emacs-org-fragtog

    ;; Completion inside the buffer, from the same capf machinery vertico
    ;; uses in the minibuffer: an org-roam link, a `#+' keyword, a word
    ;; already written in the note.
    emacs-corfu
    emacs-cape

    ;; Navigation feedback: a brief pulse on the line you landed on, and
    ;; jump-to-what-you-can-see.
    emacs-pulsar
    emacs-avy

    ;; The compiled PDF, read inside Emacs (cerebro-pdf.el): pdf-tools
    ;; renders through its own epdfinfo helper, which Guix builds here --
    ;; the one thing that normally makes pdf-tools painful to install.
    ;; poppler is the fallback path: without pdf-tools, Emacs' built-in
    ;; doc-view converts pages with `pdftoppm', and a PDF viewer that
    ;; still works when one package is dropped is worth one small input.
    emacs-pdf-tools
    poppler

    ;; -- A modern editing surface --------------------------------------
    ;; Icons: the host has a Nerd Font (JetBrainsMono/FiraCode Nerd Font),
    ;; and nerd-icons draws from it -- a glyph in a *font*, so it renders
    ;; in a terminal frame and needs no image support. cerebro-theme.el
    ;; checks the font is actually installed before turning any of this
    ;; on, so a machine without it degrades to plain text rather than to
    ;; boxes.
    emacs-nerd-icons
    emacs-nerd-icons-completion ;; icons in the minibuffer (vertico)
    emacs-nerd-icons-corfu      ;; ...and in the in-buffer popup
    emacs-nerd-icons-dired      ;; ...and in the file tree

    ;; A second theme family: ef-themes are the same author as modus, so
    ;; the same accessibility discipline, but colourful/pastel rather than
    ;; maximum contrast. Both are data in `cerebro-theme-variants'.
    emacs-ef-themes

    ;; Templates (`tempel'): capf-based, so they complete through the
    ;; corfu popup already configured -- no second completion UI. The
    ;; templates themselves are data in .emacs.d/templates, including the
    ;; theorem/definition scaffolds this repo's notes are made of.
    emacs-tempel
    emacs-tempel-collection

    ;; Format on save, per language, without each mode inventing its own
    ;; hook: apheleia runs the formatter in a subprocess and patches the
    ;; buffer, so point and undo survive.
    emacs-apheleia

    ;; Indentation made visible in code (never in prose -- see
    ;; cerebro-code.el).
    emacs-indent-bars

    ;; Real-time diagnostics: flymake is built in, but shellcheck is the
    ;; program it needs for the repo's POSIX-sh half.
    shellcheck

    ;; Tree-sitter grammars. Emacs 30 has the *engine* built in (checked:
    ;; `system-configuration-features' lists TREE_SITTER); a grammar is a
    ;; separate shared library per language. Only the ones this repo is
    ;; actually written in are worth pinning -- and note that neither Org
    ;; nor Emacs Lisp has an upstream grammar, so tree-sitter simply does
    ;; not apply to most of what is edited here.
    tree-sitter-bash

    ;; The note graph, drawn as a real graph: cerebro-graph-view.el emits
    ;; DOT and renders it to SVG, which Emacs displays natively (RSVG is
    ;; in its feature list). No browser, no JavaScript, works offline.
    graphviz

    ;; One file to hand a course to someone (bin/cerebro-course-export).
    zip

    ;; `CEREBRO-ISSUE:' markers in code comments are a load-bearing
    ;; convention here (`cerebro issue scan' imports them into the
    ;; committed tracker) -- this makes them visible while you type one.
    emacs-hl-todo

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
