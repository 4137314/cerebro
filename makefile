PROJECT_DIR := $(shell pwd)
GUIX_RUN     := ./bin/guix-run

.PHONY: help install install-hooks bootstrap-check shell ci test export-matrix export lint query results stats garden course clean clean-latex

## Bare `make` should never have a side effect: the first target used to
## be `install' (which rewrites git config and drops symlinks into
## $HOME), which made an idle `make` a footgun. Default to the harmless
## `help' summary instead; run setup explicitly with `make install'.
.DEFAULT_GOAL := help

help:
	@echo "cerebro make targets (for the scriptable day-to-day CLI, see 'cerebro help'):"
	@echo "  make install        one-time setup: 'cerebro' CLI + git/Taskwarrior hooks"
	@echo "  make bootstrap-check report which prerequisites are present"
	@echo "  make shell          drop into the pinned, isolated guix environment"
	@echo "  make export FILE=notes/x.org PROFILE=full   one .org -> one LaTeX/PDF"
	@echo "      profiles: full statements lecture report manual dispensa slides"
	@echo "                handout syllabus exercises problems paper preprint single"
	@echo "  make course DIR=notes/courses/x TITLE=...    scaffold a course as data"
	@echo "  make lint           thorough note consistency checks (see pre-push)"
	@echo "  make query Q=hubs   graph queries (orphans hubs stale-hubs co-citation by-tag by-msc)"
	@echo "  make results        results layer: index | check | deps NAME=... | dependents NAME=..."
	@echo "  make stats          notes/rigor/classification/task/time dashboard"
	@echo "  make garden         publish evergreen notes as a static HTML site"
	@echo "  make test           ERT + shell tests (fast; the post-commit gate)"
	@echo "  make export-matrix  compile every profile against example.org (pre-push gate)"
	@echo "  make ci             test + export-matrix (the thorough, pre-push gate)"
	@echo "  make clean          remove all generated output (LaTeX, public/, agenda/, DB)"

## One-time setup: installs the 'cerebro' launcher and wires up the
## versioned git hooks in githooks/ (see githooks/pre-commit,
## post-commit, pre-push) and the Taskwarrior hooks in taskwarrior/hooks/.
install: install-hooks
	@mkdir -p $(HOME)/.local/bin
	@ln -sf "$(PROJECT_DIR)/bin/cerebro" "$(HOME)/.local/bin/cerebro"
	@echo "Linked the 'cerebro' CLI -> ~/.local/bin/cerebro"
	@echo "  bare 'cerebro' opens the editor; 'cerebro help' lists every subcommand"

## Hooks are tracked files in githooks/ and taskwarrior/hooks/, not the
## untracked ~/.git/hooks/ or ~/.task/hooks/ -- this is what makes them
## "versioned" (the canonical copy lives in the repo; the ones Git/Task
## actually read are a config pointer and a symlink respectively).
install-hooks:
	@chmod +x githooks/* bin/cerebro bin/bootstrap-check bin/cerebro-issue bin/cerebro-issues \
		bin/cerebro-issue-scan bin/cerebro-note bin/guix-run bin/emacs bin/cerebro-lint \
		bin/cerebro-query bin/cerebro-results bin/task-to-org bin/cerebro-new-book \
		bin/cerebro-course bin/cerebro-stats bin/cerebro-publish-garden taskwarrior/hooks/*
	@git config core.hooksPath githooks
	@echo "git core.hooksPath -> githooks/"
	@mkdir -p $(HOME)/.task/hooks
	@for h in taskwarrior/hooks/*; do \
		ln -sf "$(PROJECT_DIR)/$$h" "$(HOME)/.task/hooks/$$(basename $$h)"; \
	done
	@echo "taskwarrior hooks symlinked into ~/.task/hooks/"

## Reports which prerequisites are actually present on this machine.
bootstrap-check:
	@./bin/bootstrap-check

## Drop into the pinned, isolated environment interactively.
shell:
	@$(GUIX_RUN)

## Parametric export: one .org source, several LaTeX/PDF variants.
## Usage: make export FILE=notes/example.org PROFILE=full
##        make export FILE=notes/example.org PROFILE=single TARGET=some-name
## Known profiles: full statements lecture report manual slides single
## (see cerebro-latex-profiles in .emacs.d/lisp/cerebro-latex.el).
PROFILE ?= full
export:
	@test -n "$(FILE)" || (echo "usage: make export FILE=path/to/note.org PROFILE=full|statements|lecture|report|manual|slides|single [TARGET=name]"; exit 1)
	@$(GUIX_RUN) emacs --batch -l bin/org-export-latex.el -- --profile=$(PROFILE) $(if $(TARGET),--target=$(TARGET)) $(FILE)

## Thorough note consistency checks (see githooks/pre-push).
lint:
	@./bin/cerebro-lint

## Graph queries over the Org-roam database (see cerebro-query.el).
## Usage: make query Q=hubs   /   make query Q=by-tag ARGS=evergreen
query:
	@test -n "$(Q)" || (echo "usage: make query Q=orphans|hubs|stale-hubs|co-citation|by-tag|by-msc [ARGS=...]"; exit 1)
	@./bin/cerebro-query $(Q) $(ARGS)

## Results layer: the #+NAME/#+DEPENDS logical-dependency graph over
## theorems/definitions (see .emacs.d/lisp/cerebro-results.el).
## Usage: make results                (index -- every named result)
##        make results CMD=check      (cycles / dangling / duplicate names)
##        make results CMD=deps       NAME=thm-heine-borel   (what it rests on)
##        make results CMD=dependents NAME=def-compact       (what rests on it)
CMD ?= index
results:
	@./bin/cerebro-results $(CMD) $(NAME)

## Refresh the generated Taskwarrior -> Org agenda file.
agenda/taskwarrior.org:
	@$(GUIX_RUN) ./bin/task-to-org

## Notes/rigor/task/time dashboard (see bin/cerebro-stats).
stats:
	@$(GUIX_RUN) ./bin/cerebro-stats

## Publish evergreen notes as a static HTML "digital garden" (see
## bin/cerebro-publish-garden). Output in public/ (gitignored).
garden:
	@$(GUIX_RUN) ./bin/cerebro-publish-garden

## ERT (Elisp) tests + POSIX-sh tests for the bin/ scripts. Fast enough
## to be the post-commit gate (githooks/post-commit) -- it does NOT run
## the LaTeX profile matrix (that is `export-matrix', a pre-push
## concern). cerebro-graph-tests.el needs neither Org-roam nor Guix.
test:
	@$(GUIX_RUN) emacs --batch -L .emacs.d/lisp \
		-l tests/cerebro-latex-tests.el \
		-l tests/cerebro-graph-tests.el \
		-l tests/cerebro-msc-tests.el \
		-l tests/cerebro-taxonomy-tests.el \
		-l tests/cerebro-org-tests.el \
		-l tests/cerebro-results-tests.el \
		-f ert-run-tests-batch-and-exit
	@sh tests/run-shell-tests.sh

## Integration smoke test: compile EVERY named profile against
## notes/example.org, including the amsart paper/preprint. Slow (a real
## LaTeX run per profile), so it lives on the pre-push path
## (githooks/pre-push), never on every commit. The whole matrix is
## certified end to end against a real Guix LaTeX toolchain.
export-matrix:
	@for p in full statements lecture report manual dispensa slides handout syllabus exercises problems paper preprint; do \
		echo "export-matrix: profile=$$p"; \
		$(GUIX_RUN) emacs --batch -l bin/org-export-latex.el -- --profile=$$p notes/example.org || exit 1; \
	done
	@echo "export-matrix: profile=single target=thm-uniqueness-of-limits"
	@$(GUIX_RUN) emacs --batch -l bin/org-export-latex.el -- --profile=single --target=thm-uniqueness-of-limits notes/example.org
	@$(MAKE) clean-latex
	@echo "export-matrix: ok"

## Scaffold a course as data (course.org + book.org); see bin/cerebro-course.
## Usage: make course DIR=notes/courses/analysis-1 TITLE="Analysis I"
course:
	@test -n "$(DIR)" || (echo "usage: make course DIR=notes/courses/<slug> [TITLE=\"...\"]"; exit 1)
	@./bin/cerebro-course "$(DIR)" $(if $(TITLE),"$(TITLE)")

## Local "CI/CD": no server, no forge dependency. The thorough gate --
## run by githooks/pre-push (before sharing), not on every commit.
## bootstrap-check's exit status is only a warning here (not a hard
## prerequisite): a missing tool shouldn't turn an informational step
## into a scary failure before Guix is even installed -- see bin/guix-run.
ci:
	@./bin/bootstrap-check || echo "ci: bootstrap-check found gaps (see above) -- continuing anyway"
	@$(MAKE) test
	@$(MAKE) export-matrix
	@echo "ci: ok (test suite + full profile matrix export succeeded)"

## Generated build output only -- never touches latex/cerebro.cls itself.
clean-latex:
	@find notes latex -type f \( -name '*.aux' -o -name '*.log' -o -name '*.out' \
		-o -name '*.toc' -o -name '*.fls' -o -name '*.fdb_latexmk' -o -name '*.synctex.gz' \
		-o -name '*.nav' -o -name '*.snm' -o -name '*.vrb' \
		-o -name '*.bbl' -o -name '*.bcf' -o -name '*.blg' -o -name '*.run.xml' \) -delete
	@find notes -type f -name '*.tex' -delete
	@find notes -type f -name '*.pdf' -delete

## Everything generated, in one sweep: LaTeX build output plus the
## gitignored generated trees (public/ garden, agenda/ Taskwarrior
## bridge, the rebuildable Org-roam sqlite cache). Never touches source.
clean: clean-latex
	@rm -rf public agenda
	@rm -f .org-roam.db .org-roam.db-shm .org-roam.db-wal
	@echo "clean: removed LaTeX output, public/, agenda/, and the Org-roam cache"
