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
cerebro mode [math|dev] | cerebro math | cerebro dev   # the two macro-modes
cerebro issue new "t" [-p A] [tags] | list [open|all|done] [tag] [--all-modes]
cerebro issue show|close|start|reopen <id> | note <id> "t" | next | scan | report
cerebro note  new "t" [tags] [msc] | find QUERY | list | rehash
cerebro today                             # morning-review agenda (offline)
cerebro results [index|check|open|deps|dependents] [NAME]
cerebro query <hubs|orphans|by-tag|...>   # org-roam graph (needs guix)
cerebro lint | stats | doctor
cerebro time [today|week|month] | time start [tags]|stop | task [args] | sync
cerebro export FILE PROFILE [TARGET]      # PROFILE is required:
                    # syllabus|lecture|slides|handbook|conjecture|single
cerebro env                               what the pinned profile gives the editor
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

`make check` (byte-compile gate + tests + lint) is the whole fast gate
and takes **~25 s here**, because nothing in it goes through
`bin/guix-run` any more: every step is pure Elisp, and inside `make
shell` the Emacs on `PATH` *is* the pinned one. Use it. The equivalent
direct commands, when you want one piece of it:

```sh
# ERT + shell tests (pure Elisp; no Guix needed). The suite is globbed --
# a new tests/cerebro-x-tests.el is picked up with no list to update:
emacs --batch -L .emacs.d/lisp $(printf -- '-l %s ' tests/cerebro-*-tests.el) \
  -f ert-run-tests-batch-and-exit
sh tests/run-shell-tests.sh

# Byte-compile gate: the modules that claim to depend on nothing must
# compile with zero warnings (bin/cerebro-compile.el; `--all' also
# reports the rest, which is informational, never fatal):
emacs --batch -l bin/cerebro-compile.el --

# Note consistency (the pre-push gate):
emacs --batch -l bin/notes-lint.el --

# Compile a note through the real pipeline (any PROFILE):
TEXINPUTS="$PWD/latex:" BIBINPUTS="$PWD/bib:" \
  emacs --batch -l bin/org-export-latex.el -- --profile=handbook notes/README.org
make clean-latex

# All four documents of a course, from its ONE file:
bin/cerebro-course-export notes/courses/analysis-A.org
```

`make compile`, `make test`, `make lint` and `make check` are those same
things, and they **no longer go through `bin/guix-run` at all**: they are
pure Elisp, they load nothing from `guix.scm`, and inside `make shell` /
the `cerebro` launcher / direnv the Emacs on `PATH` is already the pinned
one. Outside it they used to pay one `guix time-machine` (~90 s) *each* —
`make check` was 3 m 37 s for about ten seconds of work, on the path of
every push. `CEREBRO_GUIX_FORCE=1` puts any of them back through the
pinned profile deliberately — use it after editing `guix.scm`.

The steps that genuinely need the profile (`export`, `query`, `stats`,
`garden`, `export-matrix`, `ci`) still go through it, and `make
export-matrix` now materialises it **once** for the whole matrix by
re-entering `make` inside it, rather than once per compile.

`make help` is **derived** from the targets' own `##` comments, and a
shell test asserts every `.PHONY` target appears in it — so a new target
documents itself or fails the suite. The ERT suite is likewise globbed
from `tests/cerebro-*-tests.el`: there is no list to update.

**The LaTeX matrix is on no hook.** `make export-matrix` (6 profiles
against `notes/README.org`, then all four documents of `analysis-A`) is
minutes; run it after touching `latex/`, the export profiles or the
course generator, or `make ci` for everything.

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
   `cerebro-results.el`, `cerebro-hash.el`), so it is unit-testable and
   works outside Guix. **"Pure" means it does not load Org either** —
   they take their paths from `cerebro-base.el`, never from
   `cerebro-org.el`, which pulls org + org-agenda + org-id + org-refile +
   ispell (~340 ms). That regression is one `require` away and looks
   like nothing, so a subprocess test
   (`cerebro-base-test-pure-modules-do-not-load-org`) holds the line.

   **There are three tiers, and two of them are data in `cerebro-base.el`:**

   | tier | may use | list | gate |
   |---|---|---|---|
   | pure | Emacs core only | `cerebro-pure-modules` (8) | `make compile` (warnings = errors) + subprocess test |
   | Org-free | + Guix packages, display | `cerebro-org-free-modules` (20) | subprocess test |
   | the rest | + Org | — | — |

   Pure ⊂ Org-free, and a test pins the nesting. Before this was
   written down, `cerebro-guix.el` — the module every *optional* package
   goes through, and therefore a dependency of fourteen others —
   required `cerebro-org` for three symbols that all live in
   `cerebro-base`, with a comment naming them right beside the wrong
   `require`. The whole presentation layer (theme, modeline, focus) was
   loading an agenda and a spell-checker to draw itself.

   **Ask what a module *configures*, not just what symbols it uses.**
   `cerebro-latex`, `cerebro-course` and `cerebro-preview` reference
   nothing from `cerebro-org.el` and must still require it:
   `org-use-sub-superscripts` decides how a subscript is typeset and
   `org-id-locations-file` is how the course composer resolves every
   `id:` link. Dropping those requires would not fail — it would
   quietly change a PDF.
5. **Keep it verified.** Any new pure logic gets ERT tests — dropping
   `tests/cerebro-x-tests.el` in is enough, `make test` globs them. A
   module that claims to be pure goes in `cerebro-pure-modules`
   (cerebro-base.el), which is *the* list: the "loads no Org" test and
   the `make compile` warnings-are-errors gate both read it. Any
   LaTeX/macro/class change is compile-checked across the affected
   profiles. Keep [README.org](README.org) in sync — an out-of-date doc
   is treated as a bug here.

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
- **There are no examples and no exercises**, and the linter enforces it:
  `#+begin_example`, `#+begin_exercise`, `#+begin_hint` and
  `#+begin_solution` are **hard errors** in `bin/notes-lint.el`, so a note
  using one does not push. An example is a particular object, and a
  particular object is the one thing a note cannot be reused as — it
  cannot be cited, it cannot be depended on. A would-be example with real
  content *is* a proposition: state it as one and name it. One with none
  is prose. An exercise is a proof you decided not to write down.
  (Code goes in `#+begin_src`, a quotation in `#+begin_quote`.)
  `cerebro-latex.el` still maps a transcoded `example` block onto the
  theorem suite's `example` environment, and `lecture` still excludes
  those types — belt and braces for a note that predates the rule, not
  permission to write one. See [notes/README.org](notes/README.org),
  which is the authoritative statement of this.
- **A note in `notes/math/` has no name in its file name.** It is called
  `<12 hex>.org`, the SHA-256 digest of its own front matter
  (`cerebro-hash.el`), recorded in the file as `#+HASH:` and recomputed
  on every save — so editing the title, tags or `#+MSC:` *renames the
  file*, and editing the mathematics does not. Nothing resolves a note by
  path (links are `id:`), the linter reports drift, and `cerebro note
  rehash` repairs a whole directory idempotently. Find a note by title
  (`C-c m f`, `cerebro note find`), never by `ls`.
- **Every LaTeX build lands in `.build/` beside the source, PDF
  included** (`cerebro-latex-output-file` is the one function that knows
  this). Course documents are collected into `out/`. Both gitignored.
- **A course is ONE file**, `notes/courses/<slug>.org`: metadata, prose,
  and a `* Programme` of `id:` links into `notes/math/`. Never put a
  lecture note in `notes/courses/`. There is no `book.org` any more: the
  lecture notes / slides / handbook are *composed* from the programme at
  export time into `.build/` (gitignored), so nothing is generated into
  the repository and nothing has to be regenerated before compiling. An
  optional `* Appendices` section is composed after `\appendix`.
- **There is no journal.** `notes/daily/` and org-roam-dailies are gone:
  the unit here is a result, not a day. `notes/conjectures/` is the other
  note directory — mine, unproved, `C-c m j`, typeset two-column by the
  `conjecture` profile — and `cerebro-hash.el` owns the file names in
  both.
- **One bibliography, `bib/references.bib`** (`cerebro-bib-file`, defined
  in cerebro-org.el because the exporter, the editor and the linter all
  need the same answer). `C-c b i` cites with completion, `C-c b n` adds
  an entry and generates its key, `C-c b y` imports one. **`cerebro lint`
  fails on a `[cite:@key]` the file does not define** — that check is
  what makes the rest trustworthy.
- **A result's proof status is inferred, and `#+STATUS:` overrides it.**
  A statement with `#+begin_proof` directly after it is `proved`; another
  provable type without one is `open`; `#+STATUS: assumed` goes *above*
  `#+NAME:` (like `#+DEPENDS:`) and wins. `C-c r o` / `cerebro results
  open` is the list of what the archive owes. **Which block types owe a
  proof is one list** — `cerebro-results-provable-types` — and
  `bin/notes-lint.el` reads it rather than repeating it, so a type added
  to the graph cannot silently escape the push gate. A test pins it as a
  subset of `cerebro-results-types`: it once held a `claim` that no
  parser recorded and no LaTeX class defined.
- **Outside math, `_` is a literal underscore, not a subscript.** Org is
  set to `org-use-sub-superscripts '{}` (cerebro-org.el), so only `x_{1}`
  subscripts — because every formula here is inside `\(...\)`/`\[...\]`
  (which Org passes through verbatim), while prose is full of tag names
  and `#+begin_` markers that must stay literal on screen *and* in the
  PDF. Write subscripts inside the math, braced.
- **There are exactly four course profiles**, one per audience —
  `syllabus` (what the course is), `lecture` (what I say at the board:
  statements and proofs, no asides), `slides` (what the room sees:
  statements only, prose pruned), `handbook` (what the student keeps:
  everything, plus appendices and an auto-built index) — plus
  `conjecture` (notes/conjectures/, two-column) and `single` (one
  `#+NAME`'d result). Adding one is a decision, and a test asserts the
  list.
- **The index is derived, never written.** Every `#+NAME`'d result
  contributes `\index{...}` on a doctype that has an index (the handbook
  only; the class makes `\index` inert elsewhere). `#+INDEX: term` still
  works for what a name cannot say.
- See [notes/README.org](notes/README.org): the map of `notes/`, the tag
  taxonomy, *and* the compilable exemplar `make export-matrix` runs
  every profile against. It replaced `notes/example.org` and
  `notes/TAGS.org`, which said three things in three files nobody opened
  together.

## Module / repo map (short)

- `.emacs.d/init.el` + `.emacs.d/lisp/cerebro-*.el` — the config
  (org/roam/latex/results/query/ql/drill/crypt/time/session/keys, ...).
- `.emacs.d/lisp/cerebro-guix.el` — the environment made observable from
  inside Emacs (`C-c G s` / `cerebro env`), and
  **`cerebro-guix-soft-require`: the one way a module may pull a
  guix.scm Emacs package**. Use it for anything optional — it records a
  missing package as a datum instead of breaking the module (invariant 4)
  and adds it to `cerebro-guix-optional-packages`, the single list the
  status report, the dashboard census and the startup warning all read.
- `.emacs.d/lisp/cerebro-{complete,ui,vc,dashboard}.el` — the editing
  surface built on that: minibuffer + in-buffer completion (vertico/
  orderless/marginalia/consult, corfu/cape), window rules + jump
  feedback (pulsar/avy), magit, and the start page. No file tree: see
  `cerebro-find.el`.
  All soft-loaded, so they degrade outside Guix.
- `.emacs.d/lisp/cerebro-base.el` — **where things are, with nothing
  loaded to say so**: `cerebro-root`, the notes directories, the
  bibliography path, `cerebro-note-files` and the shared report buffer.
  Requires no Org. Everything a *file path* is lives here; everything an
  *Org buffer* is stays in `cerebro-org.el`. This is what makes the
  invariant-4 modules actually cheap — `cerebro results check` went from
  384 ms of loading for 33 ms of work to 60 ms of loading.
  It also owns the two **layer lists** (`cerebro-pure-modules`,
  `cerebro-org-free-modules`) that make invariant 4 checkable rather
  than advisory. `cerebro-org.el` itself defines only two symbols —
  `cerebro-known-tags` and `cerebro-interactive-note-buffer-p`;
  everything else it does is *configure Org*, which is why a module
  should require it for what it sets, not for what it defines.
- `.emacs.d/lisp/cerebro-dashboard.el` — the start page (`C-c h`).
  Titled `κέρεβρο` (the name in Greek, blue via the `link` face so it
  survives a theme toggle); sections marked with the planetary signs,
  each with an **ASCII fallback** because a missing glyph draws a box;
  and a **key panel** built from `cerebro-dashboard-key-rows` — data,
  with a test asserting every advertised key is really bound and every
  line fits `cerebro-dashboard-label-width` (dashboard centres by
  padding to the widest line, so one long line moves the page).
- `.emacs.d/lisp/cerebro-mode.el` — **which of the two jobs this session
  is doing**, as one binary setting: `math` (study the archive, write
  mathematics, compile documents — the machinery is read-only, a note
  opens in `write`, the mathematical issues are yours) or `dev`
  (maintain the modules/tools/tests/classes — *every* file in the repo is
  writable, a note opens as `source`, the machinery issues are yours).
  Data: one row per mode in `cerebro-modes`, and `cerebro-mode-apply` is
  the only function that knows how any of it is switched on — it sets
  variables *if bound* and then runs `cerebro-mode-hook`, so this module
  configures cerebro-isolation/cerebro-study/the dashboard without
  requiring any of them and stays **pure** (it is in
  `cerebro-pure-modules`, so `cerebro mode` costs ~50 ms).
  `C-c M m/d/t/s`, `cerebro mode [math|dev]`, `cerebro math` / `cerebro
  dev` (one session, via `CEREBRO_MODE`), `make mode|math|dev`.
  Resolution: `CEREBRO_MODE` > `.emacs.d/var/mode` (gitignored) >
  `math`. **The issue filter may only hide the other mode's explicit
  work** — an issue tagged for neither belongs to both, it says on stderr
  what it hid, `--all-modes` shows everything, and acting on an issue by
  id is never filtered. A filter that can lose work is worse than no
  filter, and a test pins that property over every tag either mode knows.
- `.emacs.d/lisp/cerebro-isolation.el` — **the archive is writable, the
  machinery is not** (in `math`; `dev` turns it off wholesale — the mode
  is what moves this line, see above). `notes/`, `issues/`, `bib/` are writable; every
  other file in the repo opens read-only (`find-file-hook`). A file
  outside the repo is untouched — this is a policy about not damaging
  cerebro, not a claim on the session. It is a **guard rail, not a
  lock**: `C-c H u` (`cerebro-isolation-unlock`) crosses it in one
  command and says so. Never describe it as security.
- `.emacs.d/lisp/cerebro-find.el` — **there is no file tree**; files are
  reached by *kind* (`C-c f n/m/j/c/r/i/b`). Completion is over
  **titles**, never file names — a note in `notes/math/` is a digest.
  Duplicate titles are disambiguated by directory rather than shadowing:
  a note you cannot find is one you conclude you never wrote.
  `dired-sidebar`/`dired-hacks` are out of the config *and* `guix.scm`.
- `.emacs.d/lisp/cerebro-nav.el` — the results graph **as movement**
  (`C-c r j` jump to any result by name, `n`/`p` walk this note, `u`
  walks what still owes a proof, `b` backlinks, `D` inserts a
  `#+DEPENDS:` completed from real names). Separate from
  `cerebro-results.el` because that one must stay Org-free (invariant 4);
  this one is nothing but buffers and point. Display is isolated in
  `cerebro-nav--reveal` — `recenter` signals in an undisplayed buffer, so
  the movement works in a `with-temp-buffer` and the tests are real.
- `.emacs.d/lisp/cerebro-help.el` — the documentation surface (`C-c H`):
  the manual, the conventions, the brief; plus **derived** references —
  every key read from the live keymap (`C-c H k`), every setting with its
  current value via `apropos` (`C-c H v`), the module map from each
  file's own header line (`C-c H m`). Written lists go stale silently;
  these cannot.
- `.emacs.d/lisp/cerebro-study.el` — **what you are doing to a note**,
  as three rows of data (`cerebro-study-modes`, `C-c u s` cycles):
  `source` (nothing rendered, markup visible — the mode for checking a
  preview against the bytes), `write` (rendered, and the formula at
  point turns back into source), `study` (rendered, centred, **no
  timers**). The status line shows which. The load-bearing column is
  `:watch-point`: org-appear and org-fragtog ask `org-element-context`
  from `post-command-hook` at ~4ms a call, and a trackpad issues ~100
  commands a second in which point never moves — so they belong to
  `write` only. Nothing else may enable them from `org-mode-hook`;
  that is what made every note scroll badly. `:shapes` is the second
  such column: org-modern is a *global* mode, so `source` promised "the
  bytes" while a leading star was still hidden, `-` was still drawn as
  an en dash and every `#+begin_` was still a shape — the one mode you
  reach for when you already distrust the screen was showing you a
  rendering. It now turns `org-modern-mode` off buffer-locally.
- `.emacs.d/lisp/cerebro-{theme,modeline,appearance,focus,preview}.el` —
  how it *looks and reads*, each one a table of data plus a few pure
  functions: the palette/typography (built-in modus themes, fonts as an
  ordered preference list, one size driving everything, and
  `cerebro-theme-after-apply-hook` as the seam for anything colour- or
  size-dependent); a status line built from segments; Org presentation
  (org-modern/org-appear/hl-todo, and `org-pretty-entities` **off** — a
  note's mathematics stays the linear text the file contains, because
  redrawing only the entities Org knows leaves every `cerebro-macros.sty`
  command as source beside them); the centred reading mode; and LaTeX
  fragments rendered *with the notes' own macros*, so a preview that
  fails is a compile that will fail. Three things about
  `cerebro-preview.el` are load-bearing and were each wrong once:
  - **Size.** Org hands its converter either a dpi (`%D`) or a scale
    (`%S`) — different regimes, both read from Org's own table, never
    copied. `%S` is a magnification of a document dvisvgm emits in
    *points*, and Org has already multiplied by the display dpi to form
    it, so `cerebro-preview-scale` must divide that back out. Doing the
    opposite put dpi **squared** into it: ≈1.0 at 96dpi, 3.7× too large
    at 192dpi. The invariant, and a test:
    `cerebro-preview-converter-scale` must not depend on the display.
  - **Speed.** Org runs LaTeX per fragment and this preamble is 33
    `.sty` files, so the preamble is dumped to a format file once
    (mylatexformat) — 663 ms → 202 ms per fragment. One format, full
    fidelity with the export; built on first preview, not at startup.
    **A `.fmt` belongs to the TeX that wrote it**: the engine is part of
    the staleness signature, and a cached format is *probed* before use,
    because the failure mode otherwise is every preview in the buffer
    dying with Org blaming `dvisvgm`. Degrades to the plain preamble
    whenever anything about it fails — slow, never broken.
  - **The cache key.** Org names each image after a SHA-1 that includes
    `org-format-latex-options`, `:scale` and all — and `:scale` for a
    scale-based renderer is *inversely proportional to the display dpi*,
    because Org multiplies it back in. So the cache was keyed on the one
    quantity engineered to cancel out of the result: dpi 96 and dpi 100
    produced byte-identical SVGs under two different names, and
    attaching a monitor silently re-rendered all 2236 fragments in the
    archive at ~1s each. Fixed by taking `%S` out of Org's hands —
    `cerebro-preview--install-converter` bakes the display-independent
    scale into the converter command (the same pristine-copy pattern as
    the `-fmt=` splice), leaving `:scale` read by nothing but the hash,
    where it is now a constant. **Rounded** (`cerebro-preview-scale-decimals`):
    the dpi-cancelling arithmetic returned 1.2 at 100dpi and
    1.1999999999999997 at 96dpi, and that residue alone is a different
    SHA-1. Only for the *vector* backend — dvipng writes pixels, whose
    count must track the screen, so its key legitimately moves.
    A warmed note now opens in ~35 ms; `C-c u w` (`cerebro-preview-warm`)
    renders the whole archive once so that is the normal case.
  Keys under `C-c u` (`]`/`[` size the formulas against the prose, `R`
  rebuilds the format, `w` warms the whole archive's cache, `P` reports
  all of it).
- `.emacs.d/lisp/cerebro-math.el` — making a note *is* one keystroke
  (`C-c m t` = a theorem, in a file you never named, with an `:ID:`, a
  `:seed:` tag and a `#+NAME:` the results graph can cite; `C-c m e`
  extracts a selected statement into its own note and leaves a link).
  New notes go to `notes/math/` (`cerebro-math-directory`) — as do
  `cerebro note new` and the org-roam captures.
- `.emacs.d/lisp/cerebro-bib.el` — **the one bibliography** and the
  whole citation workflow on top of it (`C-c b`): insert with completion
  (citar when the environment has it, org-cite otherwise), add an entry
  from typed fields with a generated key, import one from the kill ring.
  Pure key/entry/parser functions; deliberately offline.
- `.emacs.d/lisp/cerebro-hash.el` — **what a note in `notes/math/` is
  called**: the digest of its own metadata, recomputed on save, so the
  file name is derived data rather than a second title that goes stale.
  Pure functions (`cerebro-hash-parse`, `-canonical`, `-digest`) plus two
  save hooks; `bin/cerebro-note` reproduces the canonical string in POSIX
  sh, and one pinned constant in both test suites keeps them honest.
- `.emacs.d/lisp/cerebro-course.el` — a course owns **no mathematics**:
  one file, whose `* Programme` lists `id:` links to notes in
  `notes/math/`, composed into a document as one
  `#+INCLUDE` per note, at export time, into `.build/`. Write the atomic
  notes first; a document is a view of them, never a copy. A course
  builds exactly four (`cerebro-course-outputs`, mirrored in
  `bin/cerebro-course-export`): syllabus, lecture, slides, handbook.
  `cerebro-course-source` is the one function that decides what a profile
  actually compiles, and `bin/org-export-latex.el` asks it — so `make
  export` and `C-c e c` cannot disagree.
- `.emacs.d/lisp/cerebro-pdf.el` — compile the note asynchronously
  (through the *same* `bin/org-export-latex.el` as `make export`) and
  read the PDF in a side window that auto-reverts; `C-c e r` compiles
  only the result at point via the `single` profile. pdf-tools when the
  environment has it, built-in doc-view otherwise.
- `.emacs.d/lisp/cerebro-cache.el` — **every whole-tree scan goes
  through this**: `cerebro-note-files` and `cerebro-results-scan` are
  memoised on the files' (or directories') mtimes, so the start page,
  the index and the queries read the archive once, not once each. It
  cannot go stale (the key comes from the filesystem, not from a hook)
  and `M-x cerebro-cache-disable` turns it off when a number looks wrong.
- `.emacs.d/lisp/cerebro-backup.el` + `bin/cerebro-backup` — backup
  targets as *data* (name, shell command, enabled), nothing on by
  default, a plain-text log of what last worked. Cron-able.
- `.emacs.d/lisp/cerebro-code.el` — the modern editing surface, all of
  it on built-in mechanisms: flymake diagnostics (elisp byte-compiler,
  shellcheck, **and a backend running `bin/notes-lint.el` live on the
  note you are writing**), tempel templates from `.emacs.d/templates`
  (the `thm`/`def` scaffolds), apheleia format-on-save for code only,
  indent bars, a breadcrumb header line, tree-sitter where a grammar
  exists. `cerebro-code-interactive-buffer-p` is the guard that keeps
  every one of those *out* of the notes the agenda/dashboard open in the
  background.
- `bin/cerebro-course-export` — every document of a course from its one
  file (the four profiles), each named per output in
  `notes/courses/out/`, plus a zip. The composition happens inside the
  exporter, so "compile the course" can never mean "compile a book that
  no longer matches the programme".
- `latex/cerebro*.cls`, `cerebro-macros.sty`, `cerebro-theorems.sty` —
  the parametric class family + shared notation + shared theorem suite.
  The look is deliberately bare: no emblem, no ornament, a rule and one
  typewriter line of metadata (`\cerebro@titleblock`), and a beamer class
  whose whole job is "plain" and "fit" — every figure capped by
  `\cerebrofit` so nothing is ever drawn outside its frame.
- `.emacs.d/lisp/cerebro-latex.el` — the profile → (content × doctype)
  export composition; `bin/org-export-latex.el` is its batch entry.
- `bin/` — doctor, exporter, linter, query/results/stats/issue/course
  tools, guix/emacs wrappers.
- `githooks/` — pre-commit (fast parse), post-commit (`make test`),
  pre-push (`make check`, i.e. test + lint). `make export-matrix` is on
  **no** hook, as the section above says — run it by hand.
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
