# Public site Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The bases marked `:publish t` in `bases.el` (math, physics, business, computer-science, remote-sensing; never the thesis) become a static site on GitHub Pages, rebuilt automatically.

**Architecture:** `tools/site.el` loads the reader's engine (`kb.el`, from the `knowledge-base` input) once per base in its own batch Emacs: `kb-reload` gives index and study order, `kb-render-all` the SVG of every formula and TikZ picture (same pipeline and cache as the hub), and an `ox-html` derived backend turns each note into a page whose fragments are `<img>` of those SVGs and whose `id:` links point to sibling pages. The flake exposes it as `.#site`; `make site` builds `_site/`. The workflow lives in the private `dev` superproject (which holds every base, including physics and business), builds the site and pushes only `_site/` to the `gh-pages` branch of the public `cerebro` repo.

**Tech Stack:** Emacs 30 Lisp (ox-html, ERT), Nix flakes, make, GitHub Actions (`peaceiris/actions-gh-pages@v4`).

**Spec:** this plan (design agreed in conversation on 2026-11-25).

## Global Constraints

- Only bases with `:publish t` are exported; the thesis entry never gets it.
- The page HTML never contains absolute local paths (`/home/...`, store paths).
- Hub behaviour unchanged: `kb-hub-read` ignores unknown plist keys, `make run`/`check` untouched.
- Secrets live only in `dev` (private): one fine-grained PAT `SITE_TOKEN` (read: computer-science, remote-sensing, knowledge-base; write: cerebro).
- Commits: conventional, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; no push.

## Review Focus

- Fragment whose SVG is missing (LaTeX error) → page still builds, the TeX is shown as code, a warning is printed (test `site-test-missing-svg`).
- `id:` link to a note that is not in the base → plain text, no dead link (test `site-test-link-unknown-id`).
- Text with `_` (snake_case, file names) → no subscripts (test `site-test-no-subscripts`).
- Two bases with different preambles in one build → each base in its own Emacs, hashes match the hub's cache (driver design, checked by the full build).
- Registry entry without `:publish` → absent from the site (test `site-test-publish-filter`).

---

### Task 1: Exporter `tools/site.el` + ERT tests

**Files:** Create `tools/site.el`, `tools/test-site.el`. Modify `makefile` (`test` also runs ERT).

**Interfaces (produces):**
- `(site-bases REGISTRY HUB-ROOT)` → list of `(NAME :title T :dir D :config C)` for `:publish t` entries.
- `(site-note-html FILE)` → HTML body of one note (string); records used SVG hashes in `site--used`.
- `(site-build-base NAME TITLE DIR CONFIG OUT STATE)` → writes `OUT/NAME/{index.html,<id>.html,m/<hash>.svg}`.
- `site-main` (command-line: REGISTRY HUB-ROOT OUT) → one child Emacs per base, then `OUT/index.html`, `style.css`, `.nojekyll`.

Tests (system `emacs --batch -Q -L ../knowledge-base/emacs`): `site-test-publish-filter`, `site-test-math-img` (fragment with cached SVG → `<img src="m/<hash>.svg"`), `site-test-missing-svg`, `site-test-link-known-id` (`href="b.html"`), `site-test-link-unknown-id`, `site-test-no-subscripts`, `site-test-special-block` (`class="theorem"`).

### Task 2: Flake app + `make site`

`packages.site` / `apps.site`: `cerebro-site` with emacs-nox + texliveFull, loads `${knowledge-base}/emacs` and `${./tools/site.el}`. `make site` → `_site/` (gitignored). Verify: full build, open a physics page with TikZ, a math page with theorems.

### Task 3: `:publish t` in `bases.el`, README

### Task 4: Workflow in `dev`: `.github/workflows/cerebro-site.yml`

Triggers: push to `main` touching `personal/cerebro`, `personal/knowledge-base`, `uni/{physics,business,computer-science,remote-sensing}`; weekly; manual. Checks out only those submodules with `SITE_TOKEN`, installs Nix, `make -C personal/cerebro site`, pushes `_site` to `4137314/cerebro` branch `gh-pages`. User steps: create the PAT, `gh secret set SITE_TOKEN`, enable Pages (branch `gh-pages`).
