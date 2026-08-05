# CLAUDE.md — orientation for a fresh Claude Code session

This file is read automatically at the start of a session. It tells you
what **cerebro** is, the invariants you must not break, how to verify your
work, and **where to find what to do next**. The human-facing manual is
[README.org](README.org); this is the operational brief.

## What this is

cerebro is a personal, lifelong **second brain for pure mathematics**:
rigorous notes in Org-mode/Org-roam, compiled to LaTeX/PDF through a
**parametric** pipeline, in an environment **isolated and pinned with GNU
Guix**. Design values, in order: plain text, GNU tools, KISS, things that
are still understandable years from now. Read [README.org](README.org)
"Principles" before making design decisions.

## Where to start: the backlog is committed

The project's own to-do list lives in git as Org, so a fresh clone (and a
fresh you) knows the plan:

- **[issues/issues.org](issues/issues.org)** — the roadmap and open work,
  as plain `TODO`/`DOING`/`DONE` Org headings with tags/priorities. This
  is the shared, reproducible task state. **Read it first** to see what is
  planned and why.
- Inside Emacs: `C-c a i` (open issues by priority), `C-c i` (open the
  file), `C-c c i` (capture a new issue). From the shell:
  `bin/cerebro-issue "title" [tags...]`.
- Personal time tracking is **local, not committed**: Taskwarrior/
  Timewarrior (`~/.task`, `~/.timewarrior`). To time-track work on an
  issue, `org-clock-in` on its heading — `cerebro-time.el` mirrors that
  into `timew` automatically. Do not try to commit Taskwarrior state.

## The `cerebro` CLI — everything is scriptable

One git-style dispatcher, `bin/cerebro`, exposes the whole workflow from
the terminal (and Emacs binds `C-c d ...` straight onto it via
`cerebro-cli.el`, so there is one implementation per operation):

```
cerebro help                              # every subcommand
cerebro issue new "t" [-p A] [tags] | list [open|all|done] [tag]
cerebro issue show|close|start|reopen <id> | note <id> "t" | next | scan | report
cerebro note  new "t" [tags] [msc] | find QUERY | list
cerebro today                             # morning-review agenda (offline)
cerebro results [index|check|deps|dependents] [NAME]
cerebro query <hubs|orphans|by-tag|...>   # org-roam graph (needs guix)
cerebro lint | stats | doctor
cerebro time [today|week|month] | time start [tags]|stop | task [args] | sync
cerebro export FILE PROFILE [TARGET]
```

`cerebro issue scan` imports `CEREBRO-ISSUE: <title>` markers from code
comments into the tracker (idempotent, append-only) -- a clean way to turn
a "fix this later" you notice while editing into a committed issue.

Fast pure-Emacs/POSIX subcommands (`issue`, `note`, `results`, `stats`)
run on the tools on PATH; only `query`/`lint`/`time`/`task`/`export` go
through `bin/guix-run`. Prefer these over ad-hoc edits when you operate on
issues or notes — the issue lifecycle goes through org-mode, so `close`
logs a CLOSED timestamp and everything stays committed in `issues/`.

## How to verify your work (do this before proposing a change is done)

The full Guix toolchain is the reproducible target, but in this
environment **Emacs and the LaTeX toolchain are already on `PATH`**, so
you can run the real checks directly and fast:

```sh
# ERT + shell tests (pure Elisp; no Guix needed):
emacs --batch -L .emacs.d/lisp \
  -l tests/cerebro-latex-tests.el -l tests/cerebro-graph-tests.el \
  -l tests/cerebro-msc-tests.el -l tests/cerebro-taxonomy-tests.el \
  -l tests/cerebro-org-tests.el -l tests/cerebro-results-tests.el \
  -f ert-run-tests-batch-and-exit
sh tests/run-shell-tests.sh

# Note consistency (the pre-push gate):
emacs --batch -l bin/notes-lint.el --

# Compile a note through the real pipeline (any PROFILE):
TEXINPUTS="$PWD/latex:" BIBINPUTS="$PWD/bib:" \
  emacs --batch -l bin/org-export-latex.el -- --profile=full notes/example.org
make clean-latex
```

`make test`, `make lint`, `make export-matrix`, `make ci` are the same
things wrapped in `bin/guix-run`. **Beware:** `bin/guix-run` will try to
materialise the full pinned Guix profile (several GB, incl.
`texlive-scheme-full`) on first use and can take a long time — for quick
iteration call the on-`PATH` `emacs`/`latexmk` directly as above, and use
the `make` targets (Guix) for a final, reproducible check.

**LaTeX compiles are strict:** `org-latex-pdf-process` runs `latexmk
-halt-on-error`, so a real LaTeX error *fails* the export instead of
shipping a malformed PDF. If an export fails, read the `.log` for the
first `^!` line.

## Invariants — do not break these

1. **No runtime network / no new MELPA-style deps.** Every Emacs package
   comes from [guix.scm](guix.scm); nothing is fetched at startup. Adding
   a dependency means adding it to `guix.scm` (and re-pinning), not
   `package-install`.
2. **One source of truth per domain.** Notes in Org/Org-roam; tasks in
   Taskwarrior; time in Timewarrior; the roadmap in `issues/issues.org`.
   Bridges between them are explicit, **one-way** scripts, never sync.
3. **Data, not code paths.** Tag taxonomy, export profiles, LaTeX theorem
   environments, MSC classes, the results graph — all are *data* read by a
   few general mechanisms. Add a profile/area/tag by adding one datum, not
   a bespoke branch.
4. **Modules are independently loadable.** `init.el` loads *core* modules
   loudly and *optional* (Guix-only: org-roam/org-ql/org-drill) modules
   best-effort. Keep pure logic in modules that need no Guix package
   (`cerebro-graph.el`, `cerebro-msc.el`, `cerebro-taxonomy.el`,
   `cerebro-results.el`), so it is unit-testable and works outside Guix.
5. **Keep it verified.** Any new pure logic gets ERT tests wired into
   `make test`. Any LaTeX/macro/class change is compile-checked across the
   affected profiles. Keep [README.org](README.org) in sync — an
   out-of-date doc is treated as a bug here.

## Note-authoring conventions that FAIL SILENTLY (know these cold)

These are load-bearing; getting them wrong breaks compilation or the graph
quietly. The linter now catches most of them.

- **Inline math is `\(...\)`, display is `\[...\]` — never bare `$...$`.**
  A `$` next to punctuation (`$x$--$y$`) silently mis-parses in Org into a
  literal dollar that fails to compile. `bin/notes-lint.el` rejects any
  naked `$`.
- **Name a result** you may cite/depend on with a **globally unique**
  kebab-case `#+NAME` (`thm-...`, `def-...`, `lem-...`, `prop-...`,
  `ax-...`) placed **directly above** its `#+begin_` line.
- **`#+DEPENDS:` goes ABOVE `#+NAME:`** (it lists the `#+NAME`s a result
  rests on). It is not an Org affiliated keyword, so putting it *between*
  `#+NAME` and the block detaches the name (breaking the `single` export).
  `make results` / `C-c r` query this logical-dependency graph; the linter
  rejects a dangling or cyclic dependency and a duplicate name.
- **Never** set `#+LATEX_CLASS`, `#+LATEX_CLASS_OPTIONS`, or
  `#+EXCLUDE_TAGS` in a note — the export profile controls all three, and
  a file-local setting silently wins.
- Special block names are **lowercase** (`#+begin_theorem`). Meta-comments
  go in a `#+begin_comment` block, not plain prose. Display equations stay
  on one line starting with `\[`.
- See [notes/example.org](notes/example.org) (the exemplar, exercised by
  every export profile) and [notes/TAGS.org](notes/TAGS.org).

## Module / repo map (short)

- `.emacs.d/init.el` + `.emacs.d/lisp/cerebro-*.el` — the config
  (org/roam/latex/results/query/ql/drill/crypt/time/session/keys, ...).
- `latex/cerebro*.cls`, `cerebro-macros.sty`, `cerebro-theorems.sty` —
  the parametric class family + shared notation + shared theorem suite.
- `.emacs.d/lisp/cerebro-latex.el` — the profile → (content × doctype)
  export composition; `bin/org-export-latex.el` is its batch entry.
- `bin/` — doctor, exporter, linter, query/results/stats/issue/course
  tools, guix/emacs wrappers.
- `githooks/` — pre-commit (fast parse), post-commit (`make test`),
  pre-push (`make lint` + `make export-matrix`).
- `tests/` — ERT (pure logic) + a POSIX-sh script.

## Contributing workflow (also how the human will, from Emacs)

1. Branch off `main` (never commit straight to `main` without asking).
2. Make the change data-driven and heavily commented in the house style
   ("why", not "what").
3. `make test` + `make lint` (or the on-`PATH` equivalents above); compile
   the affected profiles for any LaTeX change.
4. Update `README.org` and this file if behaviour/conventions changed.
5. Commit only when asked; end commit messages with the required
   `Co-Authored-By` trailer.
