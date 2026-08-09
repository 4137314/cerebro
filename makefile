PROJECT_DIR := $(shell pwd)
GUIX_RUN     := ./bin/guix-run
EMACS       ?= emacs

## Which steps need the pinned environment, and which only think they do.
##
## `guix time-machine -C ... -- shell -f guix.scm' costs ~90 seconds even
## when every package it would produce is already on PATH (see
## bin/guix-run), and it is a no-op inside `make shell'. The ERT suite and
## the byte-compile gate are pure Elisp -- CLAUDE.md says so and
## `cerebro-base-test-pure-modules-do-not-load-org' enforces it -- so
## outside the environment they ran a three-and-a-half-minute channel
## resolution for ten seconds of work, on every single commit, because
## post-commit runs `make test'. They now run on the Emacs on PATH, which
## inside `make shell' IS the pinned one, so nothing is lost where it
## matters. CEREBRO_GUIX_FORCE=1 puts them back through the profile --
## the deliberate check, e.g. after editing guix.scm.
PURE_RUN := $(if $(CEREBRO_GUIX_FORCE),$(GUIX_RUN),)

## Globbed, not listed. The test suite was a hand-kept list of 28 `-l'
## flags in this file and a second copy of it in CLAUDE.md, and a new
## tests/cerebro-x-tests.el was only ever run if you remembered to add it
## to both -- a test that silently never runs is worse than no test.
TEST_FILES := $(sort $(wildcard tests/cerebro-*-tests.el))

## The five whole-document profiles compiled by `export-matrix' (`single'
## is separate: it needs a --target).
PROFILES := syllabus lecture slides handbook conjecture

.PHONY: help install install-hooks bootstrap-check env shell mode math dev \
	ci check compile compile-all test export-matrix export-matrix-run \
	export-single export-course export lint query results stats garden \
	course clean clean-latex

## Bare `make` should never have a side effect: the first target used to
## be `install' (which rewrites git config and drops symlinks into
## $HOME), which made an idle `make` a footgun. Default to the harmless
## `help' summary instead; run setup explicitly with `make install'.
.DEFAULT_GOAL := help

## The summary is *derived*, like `C-c H k' derives the key list inside
## Emacs: every target's one-line description is the `##' comment on its
## own line, read out of this file by awk. A hand-written help text goes
## stale the first time a target is renamed, and a shell test
## (tests/run-shell-tests.sh) asserts that every .PHONY target appears
## here -- so adding a target without documenting it fails the suite.
help: ## this summary
	@echo "cerebro make targets (for the scriptable day-to-day CLI, see 'cerebro help'):"
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z][a-zA-Z0-9_-]*:.*## / {printf "  %-16s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "  export profiles: syllabus lecture slides handbook conjecture single"
	@echo "  usage: make export FILE=notes/x.org PROFILE=lecture [TARGET=thm-name]"
	@echo "         make course SLUG=analysis-B TITLE=\"...\"    (scaffold a course)"
	@echo "         make query Q=hubs / make results CMD=deps NAME=thm-x"
	@echo "         bin/cerebro-course-export FILE            (all four documents)"

## One-time setup: installs the 'cerebro' launcher and wires up the
## versioned git hooks in githooks/ (see githooks/pre-commit,
## post-commit, pre-push) and the Taskwarrior hooks in taskwarrior/hooks/.
install: install-hooks ## one-time setup: 'cerebro' CLI + git/Taskwarrior hooks
	@mkdir -p $(HOME)/.local/bin
	@ln -sf "$(PROJECT_DIR)/bin/cerebro" "$(HOME)/.local/bin/cerebro"
	@echo "Linked the 'cerebro' CLI -> ~/.local/bin/cerebro"
	@echo "  bare 'cerebro' opens the editor; 'cerebro help' lists every subcommand"

## Hooks are tracked files in githooks/ and taskwarrior/hooks/, not the
## untracked ~/.git/hooks/ or ~/.task/hooks/ -- this is what makes them
## "versioned" (the canonical copy lives in the repo; the ones Git/Task
## actually read are a config pointer and a symlink respectively).
##
## Everything in bin/ that is not Elisp is made executable, rather than a
## list of names: bin/ grows, the list did not, and a new tool that
## nobody could run was the failure mode. The .el files there are batch
## *arguments* (`emacs --batch -l bin/x.el'), never executed themselves.
install-hooks: ## wire up the versioned git + Taskwarrior hooks
	@chmod +x githooks/* taskwarrior/hooks/*
	@find bin -maxdepth 1 -type f ! -name '*.el' -exec chmod +x {} +
	@git config core.hooksPath githooks
	@echo "git core.hooksPath -> githooks/"
	@mkdir -p $(HOME)/.task/hooks
	@for h in taskwarrior/hooks/*; do \
		ln -sf "$(PROJECT_DIR)/$$h" "$(HOME)/.task/hooks/$$(basename $$h)"; \
	done
	@echo "taskwarrior hooks symlinked into ~/.task/hooks/"

## Reports which prerequisites are actually present on this machine.
bootstrap-check: ## report which prerequisites are present
	@./bin/bootstrap-check

## Reports the environment the *editor* runs in: profile, channel pin,
## and which guix.scm Emacs packages the config actually got (the shell
## twin of `M-x cerebro-guix-status'; see bin/cerebro-env.el).
env: ## report the pinned environment the editor gets
	@./bin/cerebro env

## Drop into the pinned, isolated environment interactively.
shell: ## drop into the pinned, isolated guix environment
	@$(GUIX_RUN)

## -- The two macro-modes (.emacs.d/lisp/cerebro-mode.el) ---------------
## `math' studies and writes the archive; `dev' maintains the machinery
## that holds it. `make mode' reports which is in force and why; `make
## math' / `make dev' open the editor in one for this session only, the
## same as `cerebro math' / `cerebro dev' (CEREBRO_MODE). Changing the
## *remembered* mode is `cerebro mode math|dev' -- deliberately a
## different command from starting one session in it.
mode: ## report the macro-mode in force (math / dev), and why
	@./bin/cerebro mode

math: ## open the editor in math mode (this session only)
	@./bin/cerebro math

dev: ## open the editor in dev mode (this session only)
	@./bin/cerebro dev

## Parametric export: one .org source, four documents (plus `single').
## Usage: make export FILE=notes/README.org PROFILE=handbook
##        make export FILE=notes/README.org PROFILE=single TARGET=some-name
## Known profiles: syllabus lecture slides handbook conjecture single
## (see cerebro-latex-profiles in .emacs.d/lisp/cerebro-latex.el).
PROFILE ?= handbook
export: ## FILE=x.org PROFILE=p [TARGET=n] -- one .org to LaTeX/PDF
	@test -n "$(FILE)" || (echo "usage: make export FILE=path/to/note.org PROFILE=syllabus|lecture|slides|handbook|conjecture|single [TARGET=name]"; exit 1)
	@# A course file is composed with the notes it indexes before it is
	@# compiled -- inside the exporter (cerebro-course-source), so there
	@# is nothing to regenerate here and no way to compile a book that no
	@# longer matches its programme.
	@$(GUIX_RUN) $(EMACS) --batch -l bin/org-export-latex.el -- --profile=$(PROFILE) $(if $(TARGET),--target=$(TARGET)) $(FILE)

## Thorough note consistency checks (see githooks/pre-push).
lint: ## thorough note consistency checks (see pre-push)
	@./bin/cerebro-lint

## Graph queries over the Org-roam database (see cerebro-query.el).
## Usage: make query Q=hubs   /   make query Q=by-tag ARGS=evergreen
query: ## Q=hubs -- graph queries (orphans hubs stale-hubs co-citation by-tag by-msc)
	@test -n "$(Q)" || (echo "usage: make query Q=orphans|hubs|stale-hubs|co-citation|by-tag|by-msc [ARGS=...]"; exit 1)
	@./bin/cerebro-query $(Q) $(ARGS)

## Results layer: the #+NAME/#+DEPENDS logical-dependency graph over
## theorems/definitions (see .emacs.d/lisp/cerebro-results.el).
## Usage: make results                (index -- every named result)
##        make results CMD=check      (cycles / dangling / duplicate names)
##        make results CMD=deps       NAME=thm-heine-borel   (what it rests on)
##        make results CMD=dependents NAME=def-compact       (what rests on it)
CMD ?= index
results: ## results layer: index | check | deps NAME=... | dependents NAME=...
	@./bin/cerebro-results $(CMD) $(NAME)

## Refresh the generated Taskwarrior -> Org agenda file.
agenda/taskwarrior.org:
	@$(GUIX_RUN) ./bin/task-to-org

## Notes/rigor/task/time dashboard (see bin/cerebro-stats).
stats: ## notes/rigor/classification/task/time dashboard
	@$(GUIX_RUN) ./bin/cerebro-stats

## Publish evergreen notes as a static HTML "digital garden" (see
## bin/cerebro-publish-garden). Output in public/ (gitignored).
garden: ## publish evergreen notes as a static HTML site
	@$(GUIX_RUN) ./bin/cerebro-publish-garden

## Byte-compilation as a gate (bin/cerebro-compile.el): the pure modules
## compile with warnings promoted to errors, because a free variable in a
## module that claims to depend on nothing is the dependency creeping
## back in. A second and a half, and silent when nothing is wrong -- so
## it sits in `check' with the tests.
compile: ## byte-compile the pure modules; warnings are errors
	@$(PURE_RUN) $(EMACS) --batch -l bin/cerebro-compile.el --

## The same, plus every other module with its warnings printed. Not a
## gate: outside the pinned environment most of those warnings say "this
## optional package is not installed", which is invariant 4 working.
compile-all: ## ...and report the warnings in every other module too
	@$(PURE_RUN) $(EMACS) --batch -l bin/cerebro-compile.el -- --all

## ERT (Elisp) tests + POSIX-sh tests for the bin/ scripts. Fast enough
## to be the post-commit gate (githooks/post-commit) -- it does NOT run
## the LaTeX profile matrix (that is `export-matrix', a manual concern).
## Every tests/cerebro-*-tests.el is loaded (see TEST_FILES): none of
## them needs Org-roam or Guix.
test: ## ERT + shell tests (seconds; the post-commit gate)
	@$(PURE_RUN) $(EMACS) --batch -L .emacs.d/lisp \
		$(foreach t,$(TEST_FILES),-l $(t)) \
		-f ert-run-tests-batch-and-exit
	@sh tests/run-shell-tests.sh

## The fast gate: everything that does not run LaTeX. This is what the
## pre-push hook runs, and it takes seconds. The LaTeX matrix is
## deliberately NOT here -- nine TeX compiles on the path of every push
## is a gate people learn to skip, which is worse than no gate.
check: compile test lint ## compile + test + lint -- the push gate, no LaTeX
	@echo "check: ok (compile + tests + lint)"

## Integration smoke test: compile EVERY named profile against
## notes/README.org (which is the exemplar as well as the manual) and,
## since the #+INCLUDE machinery is load-bearing, one real course end to
## end -- all four of its documents, from its own course.org.
##
## The environment is materialised ONCE, for the whole matrix, by
## re-entering make inside it: bin/guix-run is a no-op when
## GUIX_ENVIRONMENT is already set, so every compile below then runs
## directly. It used to call guix-run per compile -- ten channel
## resolutions of ~90s each, outside `make shell', for work that shares
## one profile.
##
## Serial on purpose, and `make -j' cannot change that: every profile of
## one source writes the same `.build/<basename>.tex' and `.pdf'
## (cerebro-latex-output-file names the build by the *source*, not by the
## profile), so two profiles of README.org in parallel would overwrite
## each other's intermediates.
export-matrix: ## compile every profile + a whole course (slow, manual)
	@$(GUIX_RUN) $(MAKE) --no-print-directory export-matrix-run

## The matrix itself, run with the environment already materialised.
## Listed (and documented) rather than hidden: every phony target here is
## something you can type, and the shell tests assert that every one of
## them says what it does.
export-matrix-run: ## the matrix, assuming you are already inside the environment
	@for p in $(PROFILES); do \
		echo "export-matrix: profile=$$p"; \
		$(EMACS) --batch -l bin/org-export-latex.el -- --profile=$$p notes/README.org || exit 1; \
	done
	@$(MAKE) --no-print-directory export-single
	@$(MAKE) --no-print-directory export-course
	@$(MAKE) --no-print-directory clean-latex
	@echo "export-matrix: ok"

export-single: ## one result through the `single' profile (part of the matrix)
	@echo "export-matrix: profile=single target=thm-uniqueness-of-limits"
	@$(EMACS) --batch -l bin/org-export-latex.el -- --profile=single --target=thm-uniqueness-of-limits notes/README.org

export-course: ## the four documents of one real course (part of the matrix)
	@echo "export-matrix: the four documents of a course"
	@./bin/cerebro-course-export notes/courses/analysis-A.org all --no-zip

## Scaffold a course: ONE file, notes/courses/<slug>.org (bin/cerebro-course).
## Usage: make course SLUG=analysis-B TITLE="Mathematical Analysis B"
course: ## SLUG=x TITLE=y -- scaffold a course (one file)
	@test -n "$(SLUG)" || (echo "usage: make course SLUG=<slug> [TITLE=\"...\"]"; exit 1)
	@./bin/cerebro-course "$(SLUG)" $(if $(TITLE),"$(TITLE)")

## Local "CI/CD": no server, no forge dependency. The thorough gate --
## run by hand before a release or after LaTeX work, not on any hook.
ci: check export-matrix ## check + export-matrix (before a release / after LaTeX work)
	@echo "ci: ok (compile + tests + lint + the full profile matrix)"

## Generated build output only -- never touches latex/cerebro.cls itself.
clean-latex: ## remove LaTeX intermediates and .build/ trees
	@find . -type d -name '.build' -not -path './.git/*' -exec rm -rf {} + 2>/dev/null || true
	@find notes latex -type f \( -name '*.aux' -o -name '*.log' -o -name '*.out' \
		-o -name '*.toc' -o -name '*.fls' -o -name '*.fdb_latexmk' -o -name '*.synctex.gz' \
		-o -name '*.nav' -o -name '*.snm' -o -name '*.vrb' \
		-o -name '*.bbl' -o -name '*.bcf' -o -name '*.blg' -o -name '*.run.xml' \
		-o -name '*.idx' -o -name '*.ind' -o -name '*.ilg' \) -delete
	@find notes -type f -name '*.tex' -delete
	@# Stray PDFs only: the collected course documents live in
	@# notes/courses/*/out/ and are what you hand to someone -- removing
	@# them is `make clean', not "clean the LaTeX intermediates".
	@find notes -type f -name '*.pdf' -not -path '*/out/*' -delete

## Everything generated, in one sweep: LaTeX build output plus the
## gitignored generated trees (public/ garden, agenda/ Taskwarrior
## bridge, the rebuildable Org-roam sqlite cache). Never touches source.
clean: clean-latex ## remove all generated output (LaTeX, public/, agenda/, DB)
	@rm -rf public agenda
	@rm -rf .emacs.d/var/ltximg
	@rm -rf notes/courses/*/out
	@rm -f .org-roam.db .org-roam.db-shm .org-roam.db-wal
	@echo "clean: removed LaTeX output, course documents, preview images, public/, agenda/, and the Org-roam cache"
