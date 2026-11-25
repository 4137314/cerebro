# Site navigation and PDF manuals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** The site reads like a specialist Wikipedia for power users (search, keyboard, previews, breadcrumbs, study-order paging, backlinks, learning paths), and every base offers PDF manuals: the whole base, each domain, each area. The workflow builds the bases in parallel.

**Architecture:** `tools/site.el` gains the note-page navigation and writes per base `base.json` (title, counts, domains, areas, PDFs) and `search.json`; `site-main` takes `--base`, `--pdf`, `--no-index`, `--index-only`. `tools/manual.el` exports a base through an ox-latex derived backend into one LuaLaTeX book (domain = chapter, area = section on a new page, note = subsection with `\label{note:<id>}`), compiles it twice, reads the absolute page of each domain/area from `\zlabel`s in the `.aux`, and cuts domain/area PDFs with `qpdf`. `tools/site.js` (no dependencies) does search, keys, previews and the in-page contents. The workflow: job `bases` reads the published bases from `bases.el`, a matrix job builds each base (HTML + PDF) as an artifact, job `publish` merges them, writes home/search/sitemap (`.#site-index`, no TeX) and deploys.

**Tech Stack:** Emacs Lisp (ox-html, ox-latex, ERT), LuaLaTeX (fontspec with DejaVu fallback, amsthm, hyperref, zref-abspage), qpdf, plain JS, GitHub Actions matrix + artifacts.

## Global Constraints
- PDF naming: `<base>/pdf/<base>.pdf`, `<base>/pdf/<domain>.pdf`, `<base>/pdf/<domain>--<area>.pdf`.
- A LaTeX error in a note must not stop the manual: nonstopmode, PDF kept, errors reported in the log.
- `make site` stays fast (no PDF); `make site-pdf` builds everything locally.
- Pages work without JS (search, previews and keys are an enhancement).

## Review Focus
- Area name equal to its domain name (math: area `algebra` in domain `algebra`) → distinct labels/files (`algebra.pdf` vs `algebra--algebra.pdf`) (test `manual-test-ranges`).
- Last area of the book → range ends at the last page (test `manual-test-ranges`).
- Note without area → grouped under its domain, no area PDF (test `site-test-groups`).
- Search query with accents/case → matches (`normalize` in site.js).
- First/last note in study order → no prev/next link (test `site-test-note-nav`).

## Tasks
1. `site--groups`, note-page navigation (breadcrumbs with anchors, prev/next, see also, mentioned in, learning path, PDF links), `base.json`/`search.json`, CLI flags — ERT tests first.
2. `tools/manual.el` + tests (`manual-test-note-latex`, `manual-test-ranges`), flake runtime (qpdf), `make site-pdf`, `site-base`, `site-index`.
3. `tools/site.js` + CSS; check in a browser.
4. Workflow matrix in `~/dev`; README.
