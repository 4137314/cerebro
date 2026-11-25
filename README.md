# cerebro

Read-only hub of my knowledge bases, in one Emacs window: the
[`knowledge-base`](https://github.com/4137314/knowledge-base) reader (`lib.mkHub`) opens on
the page of the bases; `RET` enters one, `H` comes back from anywhere, `?` shows the keys.

| base | notes | where |
|---|---|---|
| Mathematics | `personal/math/study/kb` | 209 notes: foundations, algebra, analysis, topology, geometry, probability, physics |
| Bachelor Thesis | `uni/bachelor-thesis/study/kb` | |
| Remote Sensing | `uni/remote-sensing/study/kb` | |
| Computer Science | `uni/computer-science/study/kb` | |
| Business | `uni/business/study/kb` | 63 English notes: organization, strategy, marketing, procurement, operations, accounting, projects and revision |
| Physics | `uni/physics/study/kb` | 161 English notes: quantum mechanics, quantum optics, QED, EM fields, optoelectronics, photonics, solid state, circuits, digital, power and superconducting electronics, revision |

The bases are listed in `bases.el`. Roots are relative to the git superproject that
contains cerebro (`~/dev`), so moving folders inside `~/dev` only needs `bases.el`
updated; `"."` means this repo. Each base keeps its caches and reading place in
`~/.local/state/cerebro-emacs/bases/<base>/`; the first visit to a base renders its
formulas (a few minutes), later visits are immediate.

## Use

```sh
make install     # build, add "Cerebro" to the launcher (re-run if cerebro itself moves)
make run         # open the hub from a terminal
make check       # check every base: metadata, links, prerequisite graph, formulas
make uninstall   # remove the launcher entry and the profile
make site        # the public site of the bases marked :publish t, in _site/ (no PDF)
make site-pdf    # the same with the PDF manuals of every base
make site-base BASE=physics   # one base with its manuals, as a CI job does
```

`make` builds against the sibling checkout `../knowledge-base` when it exists, otherwise
against the reader pinned in `flake.lock` (`nix flake update knowledge-base` to move it).
`NAME=cerebro-test make run` starts a separate instance (own server and state).

## Public site

The bases marked `:publish t` in `bases.el` (all but the thesis) are published as a static
site on GitHub Pages, from the `gh-pages` branch of this repo. `tools/site.el` builds
each base in its own batch Emacs with the reader's engine: the same index and study order,
and the same SVG of every formula and TikZ picture as the hub (a local `make site` reuses
the hub's cache, so it takes seconds).

It reads like a small specialist encyclopedia (`tools/site.js`, optional: every page works
without it):

- each note: breadcrumbs (base / domain / area), prerequisites, the notes it unlocks, see
  also, the notes that mention it, its whole learning path in study order, contents of
  long notes, previous/next in study order, its PDFs;
- search over every base (`/`), previews of linked notes on hover, keys: `j`/`k` next and
  previous note, `u` up to the area, `h` home, `l` learning path, `c` contents, `r` random
  note, `?` all keys;
- canonical links, descriptions and `sitemap.xml` for the crawlers.

`tools/manual.el` turns each base into a LuaLaTeX book (a chapter per domain, a section per
area, a subsection per note with a link to its page, links between notes kept) and cuts it
with qpdf into one PDF per domain and per area: `<base>/pdf/<base>.pdf`,
`<base>/pdf/<domain>.pdf`, `<base>/pdf/<domain>--<area>.pdf`.

The site is built by the workflow `.github/workflows/cerebro-site.yml` of the `~/dev`
superproject, which registers every base as a submodule: one job per published base, in
parallel (pages and manuals), then one job that merges them, writes the home page, search
index and sitemap (`make site-index`) and pushes the result here. It runs on each push to
`main` that moves a base, the reader or cerebro, every Monday and by hand. A base is
withdrawn by removing its `:publish t`.

The math notes lived in `kb/` until 2026-11-25 and are now the
[`math`](https://github.com/4137314/math) repo; they were converted on 2026-11-17 from the
org-roam notes of the old cerebro editor by `tools/convert_roam.py` (`make test`). The
editor itself (Guix environment, org-roam, LaTeX export, issue tracker, Taskwarrior hooks)
and the original notes, including the course and conjecture files, are in the history and
on the `feature/emacs-ui` branch.
