# Cerebro hub Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One "Cerebro" launcher entry opening a read-only Emacs hub that lists the knowledge bases (math, thesis, remote-sensing, computer-science) and switches between them in one window.

**Architecture:** The shared reader (`personal/knowledge-base`) learns to switch base in-process (`kb-open-base`), to show a bases page when started with a registry (`KB_BASES`), and to render org special blocks; `lib.mkHub` wraps it. `personal/cerebro` main becomes the hub: flake, registry, the converted math notes in `kb/`, makefile and launcher.

**Tech Stack:** Emacs 30 Lisp (ERT for tests, system `emacs --batch`), Nix flakes, Python 3 stdlib (conversion, `unittest`), make.

**Spec:** `docs/superpowers/specs/2026-11-17-cerebro-hub-design.md`

## Global Constraints

- Never touch Emacs server `remote-sensing` or `~/.local/state/remote-sensing-emacs` (user is studying).
- Manual runs of the hub: instance name `cerebro-test`, `XDG_STATE_HOME=$SCRATCH/state` where `SCRATCH=/tmp/claude-1000/-home-main/4ae32f0f-caea-4d50-8e75-aab7e565e10c/scratchpad`.
- Work on branch `feat/hub` in both repos (git worktrees under `$SCRATCH/wt/`); no push, no `nix profile` commands — user does those.
- Note bodies of the 210 math notes unchanged by conversion except `[[id:UUID]]` → `[[id:slug]]`.
- Registry roots are relative to the `~/dev` superproject root; no hard-coded `/home/main`.
- Single-base readers (`mkReader`, `make study`) keep working unchanged.
- Commits: conventional, imperative, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

- A base's `kb-config.el` with `kb-preamble-add` opened twice, or after another base → preamble must not accumulate (Task 2 test `kb-test-switch-resets-config`).
- Registry entry whose root does not exist (submodule not checked out) → bases page shows it dimmed "missing", RET gives a message, no error (Task 3 test `kb-test-bases-missing-root`).
- Reading bookmark/formula scale of base A must not leak into base B (Task 2 test `kb-test-switch-per-base-state`).
- Math note whose `#+DEPENDS` label belongs to no note, or a dependency cycle → conversion still yields a valid DAG and reports it (Task 4 tests `test_unknown_label_dropped`, `test_cycle_broken_into_see`).
- Notes with `#+begin_proof` nested inside text with `\[ \]` formulas → formulas inside blocks still render (Task 1 test `kb-test-blocks-keep-fragments`).

---

### Task 1: Render special blocks in the reader

**Files:**
- Modify: `personal/knowledge-base/emacs/kb-ui.el` (`kb--decorate`, faces)
- Create: `personal/knowledge-base/tests/kb-test.el`, `personal/knowledge-base/tests/run.sh`

**Interfaces:**
- Produces: `kb-block-labels` (alist `"theorem"` → `"Theorem"` … for theorem definition lemma proposition corollary remark axiom proof example), face `kb-block`; `tests/run.sh` = `emacs --batch -Q -L emacs -l emacs/kb.el -l emacs/kb-ui.el -l tests/kb-test.el -f ert-run-tests-batch-and-exit`.

- [ ] **Step 1: Write failing tests** in `tests/kb-test.el`: `kb-test-blocks-labelled` (temp org buffer with `#+NAME: thm-x`, `#+DEPENDS: def-y`, `#+begin_theorem … #+end_theorem`, `#+begin_proof … #+end_proof`; after `(kb--decorate)` an overlay at the begin line has `display` containing "Theorem", one at proof contains "Proof", the `#+NAME:`/`#+DEPENDS:`/`#+end_*` lines have `invisible t`); `kb-test-blocks-keep-fragments` (`(kb--fragments (point-min) (point-max))` inside a theorem block still returns the `\[ a=b \]` fragment).
- [ ] **Step 2: Run** `bash tests/run.sh` → FAIL (no overlay).
- [ ] **Step 3: Implement** in `kb--decorate`: for each `^#\+begin_\(\w+\)` in `kb-block-labels`, display the line as the label in `kb-block` (amber bold; proof in `kb-dim` italic) followed by the rest of the line; hide `#+end_…`, `#+NAME:`, `#+DEPENDS:` lines.
- [ ] **Step 4: Run** `bash tests/run.sh` → all pass.
- [ ] **Step 5: Commit** `feat(reader): render theorem/proof blocks`.

### Task 2: Switch base in-process

**Files:**
- Modify: `personal/knowledge-base/emacs/kb.el`, `emacs/kb-ui.el`, `emacs/init.el`
- Test: `tests/kb-test.el`, fixture `tests/bases/a/` (example notes + config with `kb-preamble-add "\\usepackage{siunitx}"`), `tests/bases/b/` (one note, no config)

**Interfaces:**
- Produces: `(kb-open-base DIR STATE-DIR &optional CONFIG)` → reloads everything for that base and returns the node count; `kb--defaults` captured at load (values of `kb-domains kb-areas kb-forbidden kb-latex-preamble kb-math-scale`); `kb--reset-settings`. `init.el` uses `kb-open-base` for the single-base start (same behaviour).

- [ ] **Step 1: Failing tests**: `kb-test-switch-loads-base` (open a → 3 nodes, `kb-dir` = a; open b → 1 node, nodes of a gone); `kb-test-switch-resets-config` (open a, b, a: `kb-latex-preamble` contains `siunitx` exactly once; after b it contains none; `kb-domains` nil after b); `kb-test-switch-per-base-state` (state dirs distinct temp dirs; `kb-math-scale` set and saved in a is 1.0 in b and restored in a; `kb--reading` per base; note buffers of a killed on switch).
- [ ] **Step 2: Run** → FAIL (`kb-open-base` void).
- [ ] **Step 3: Implement** `kb-open-base`: save reading/prefs/meta of the current base, kill buffers visiting files under old `kb-dir` and `*kb*` lists, clear history/future, `kb--reset-settings`, set `kb-dir`/`kb-state-dir`, load config, `kb-reload`, `kb--load-meta`, `kb--load-prefs`, `kb--load-reading`, update `revert-without-query`; when interactive, `kb-render-all nil` in idle. Refactor `init.el`’s tail to call it.
- [ ] **Step 4: Run** → pass; also `nix run ./#example -- --check` (with `XDG_STATE_HOME=$SCRATCH/state`) → `kb-check: all good`.
- [ ] **Step 5: Commit** `feat(reader): switch base in the same Emacs`.

### Task 3: Bases page and `mkHub`

**Files:**
- Create: `personal/knowledge-base/emacs/kb-hub.el`
- Modify: `emacs/init.el` (load hub when `KB_BASES` set), `emacs/kb-ui.el` (key `H`, help panel), `emacs/check.el` (`--check` on every base when hub), `flake.nix` (`lib.mkHub`, `packages.example-hub`), `README.md`
- Create: `example/bases.el`; Test: `tests/kb-test.el`

**Interfaces:**
- Consumes: `kb-open-base` (Task 2).
- Produces: registry format — file evaluating to a list of `(NAME :title STR :root REL :notes REL :config REL-or-nil)`; `(kb-hub-read FILE HUB-ROOT)` → list of plists with absolute `:dir`, `:config`, `:present`; `kb-bases` command (buffer `*bases*`, list-mode like the index: title, note count, reading note title; RET → `kb-open-base` with state `<kb-state-dir>/bases/<name>/` then `kb-home`); `H` → `kb-bases` in note and list maps. `mkHub pkgs { name ? "cerebro", registry, rootVar ? "CEREBRO_ROOT", texlive }`: command `<name>`, root from `$rootVar` else git toplevel; hub root = `git -C root rev-parse --show-superproject-working-tree` else root; exports `KB_BASES`, `KB_HUB_ROOT`, `KB_NAME`; `--check` runs check.el on each present base; focus logic as `mkReader`.

- [ ] **Step 1: Failing tests**: `kb-test-hub-read` (registry with two entries, roots resolved against a temp hub root); `kb-test-bases-missing-root` (missing root → `:present nil`, page shows it, RET messages "missing", no error); `kb-test-bases-open` (RET on an entry → `kb-dir` is that base, state dir is `…/bases/<name>/`); `kb-test-H-bound` (`(keymap-lookup kb-mode-map "H")` → `kb-bases`).
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** `kb-hub.el`, wire `init.el` (`initial-buffer-choice` → `*bases*` when hub), `mkHub` and `example/bases.el` (math and cs of `example/` as two bases).
- [ ] **Step 4: Run** tests → pass; `XDG_STATE_HOME=$SCRATCH/state nix run ./#example-hub -- --check` → all good for both.
- [ ] **Step 5: Commit** `feat(reader): hub of several bases (mkHub)`.

### Task 4: Convert the math notes

**Files (cerebro, branch `feat/hub` from `main`):**
- Create: `tools/convert-roam.py`, `tools/test_convert_roam.py`, `tools/tag-map.toml` (tag → domain, from the spec table)

**Interfaces:**
- Produces: `python3 tools/convert-roam.py SRC_NOTES_MATH OUT_KB` writes `OUT_KB/<domain>/<slug>.org`, prints a report (count, dropped labels, broken cycles); functions `slug(title)->str`, `parse(text)->Note`, `convert(notes)->dict[path,str]`.
- Source: `git -C ~/dev/personal/cerebro show origin/feature/emacs-ui:notes/math/...` exported via `git archive` to `$SCRATCH/roam-math`.

- [ ] **Step 1: Failing tests** (`python3 -m unittest tools.test_convert_roam`): `test_slug` ("Abelian group" → `abelian-group`; duplicates get `-2`); `test_drawer` (DOMAIN algebra, AREA group-theory, KIND definition, MSC kept, `#+summary:` = first paragraph collapsed to one line); `test_links_rewritten` (UUID → slug, body otherwise byte-identical); `test_requires_from_depends` (label owned by another note → REQUIRES; own label ignored); `test_unknown_label_dropped`; `test_cycle_broken_into_see`; `test_kind_theorem` (first block proposition → theorem).
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement**; area = most specific non-status tag with `_`→`-`; status tags `growing evergreen easy medium hard seed seedling` dropped; keep `#+DATE`, drop `#+FILETAGS`/`#+HASH`.
- [ ] **Step 4: Run** tests → pass; run on the real notes → 210 files, 0 unresolved links.
- [ ] **Step 5: Commit** `feat: script converting the org-roam math notes`.

### Task 5: Cerebro becomes the hub

**Files (cerebro `feat/hub`):**
- Delete from main (kept in `origin/feature/emacs-ui`, `legacy/*`): `guix.scm guix/ .emacs.d/ bin/ githooks/ issues/ latex/ taskwarrior/ tests/ notes/ bib/ .envrc` (bib: move to `kb/` if any note cites it — check)
- Create: `kb/` (converted notes), `kb-config.el`, `bases.el`, `flake.nix`, `flake.lock`, `makefile`, `cerebro.desktop.in`, `README.md` (replaces README.org)

**Interfaces:**
- Consumes: `mkHub` (Task 3), converter (Task 4).
- Produces: `make run | check | install | uninstall`; makefile passes `--override-input knowledge-base path:$(ROOT)/../knowledge-base` until the user pushes knowledge-base; install → `~/.local/state/cerebro-emacs/profile`, `~/.local/share/applications/cerebro.desktop` (Exec `env CEREBRO_ROOT=@ROOT@ @BIN@`).

- [ ] **Step 1:** Generate `kb/` with the converter; write `kb-config.el` (domains foundations algebra analysis topology geometry probability physics; forbidden `TODO|FIXME`) and `bases.el` (spec table).
- [ ] **Step 2: Verify** `CEREBRO_ROOT=<wt> XDG_STATE_HOME=$SCRATCH/state nix run <wt>#default --override-input knowledge-base path:<kb-wt> -- --check` → `kb-check: all good` for math, thesis, remote-sensing, computer-science (fix converted notes/config until green; LaTeX errors in math notes → add packages via `kb-preamble-add` in `kb-config.el`).
- [ ] **Step 3: Manual run** with `KB_NAME`-instance `cerebro-test` (`name = "cerebro-test"` via env override in makefile `NAME ?= cerebro`): bases page shows 4 bases, open math → theorem/proof visible, `H` back, open remote-sensing → its index. Check `pgrep -a emacs` still shows the user's `remote-sensing` server untouched.
- [ ] **Step 4: Commit** `feat!: cerebro is the read-only hub of the knowledge bases`.

### Task 6: Launcher

- [ ] **Step 1:** (after user OK in report) `make install` in cerebro; `rm ~/.local/share/applications/{thesis,remote-sensing,computer-science}.desktop`; `update-desktop-database ~/.local/share/applications`.
- [ ] **Step 2: Verify** `grep Exec ~/.local/share/applications/cerebro.desktop` paths exist; `rofi -show drun` lists "Cerebro".
- [ ] **Step 3:** `~/dev`: bump submodule pointers only if user asks; run `dev-check` from `~/dev` and report.
