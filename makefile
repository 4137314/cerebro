PROJECT_DIR := $(shell pwd)
GUIX_RUN     := ./bin/guix-run

.PHONY: install install-hooks bootstrap-check shell ci test export lint query clean-latex

## One-time setup: installs the 'cerbero' launcher and wires up the
## versioned git hooks in githooks/ (see githooks/pre-commit,
## post-commit, pre-push) and the Taskwarrior hooks in taskwarrior/hooks/.
install: install-hooks
	@mkdir -p $(HOME)/.local/bin
	@echo '#!/bin/sh' > $(HOME)/.local/bin/cerbero
	@echo 'cd "$(PROJECT_DIR)"' >> $(HOME)/.local/bin/cerbero
	@echo 'if [ -n "$$DISPLAY" ] || [ -n "$$WAYLAND_DISPLAY" ]; then' >> $(HOME)/.local/bin/cerbero
	@echo '    $(GUIX_RUN) emacsclient -c --alternate-editor="emacs --init-directory=.emacs.d --daemon"' >> $(HOME)/.local/bin/cerbero
	@echo 'else' >> $(HOME)/.local/bin/cerbero
	@echo '    $(GUIX_RUN) emacs -nw --init-directory=.emacs.d' >> $(HOME)/.local/bin/cerbero
	@echo 'fi' >> $(HOME)/.local/bin/cerbero
	@chmod +x $(HOME)/.local/bin/cerbero
	@echo "Installed 'cerbero' launcher in ~/.local/bin/cerbero"

## Hooks are tracked files in githooks/ and taskwarrior/hooks/, not the
## untracked ~/.git/hooks/ or ~/.task/hooks/ -- this is what makes them
## "versioned" (the canonical copy lives in the repo; the ones Git/Task
## actually read are a config pointer and a symlink respectively).
install-hooks:
	@chmod +x githooks/* bin/bootstrap-check bin/cerebro-issue bin/guix-run \
		bin/cerebro-lint bin/cerebro-query bin/task-to-org bin/cerebro-new-book \
		taskwarrior/hooks/*
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
	@test -n "$(Q)" || (echo "usage: make query Q=orphans|hubs|stale-hubs|co-citation|by-tag [ARGS=...]"; exit 1)
	@./bin/cerebro-query $(Q) $(ARGS)

## Refresh the generated Taskwarrior -> Org agenda file.
agenda/taskwarrior.org:
	@$(GUIX_RUN) ./bin/task-to-org

## ERT (Elisp) tests + POSIX-sh tests for the bin/ scripts.
test:
	@$(GUIX_RUN) emacs --batch -L .emacs.d/lisp -l tests/cerebro-latex-tests.el -f ert-run-tests-batch-and-exit
	@sh tests/run-shell-tests.sh

## Local "CI/CD": no server, no forge dependency -- this is what
## githooks/post-commit calls. bootstrap-check's exit status is only a
## warning here (not a hard prerequisite): a missing tool shouldn't turn
## an informational post-commit step into a scary failure on every
## commit before Guix is even installed -- see bin/guix-run.
ci:
	@./bin/bootstrap-check || echo "ci: bootstrap-check found gaps (see above) -- continuing anyway"
	@$(MAKE) test
	@for p in full statements lecture report manual slides; do \
		echo "ci: export profile=$$p"; \
		$(GUIX_RUN) emacs --batch -l bin/org-export-latex.el -- --profile=$$p notes/example.org || exit 1; \
	done
	@echo "ci: export profile=single target=thm-uniqueness-of-limits"
	@$(GUIX_RUN) emacs --batch -l bin/org-export-latex.el -- --profile=single --target=thm-uniqueness-of-limits notes/example.org
	@$(MAKE) clean-latex
	@echo "ci: ok (test suite + full profile matrix export succeeded)"

## Generated build output only -- never touches latex/cerebro.cls itself.
clean-latex:
	@find notes latex -type f \( -name '*.aux' -o -name '*.log' -o -name '*.out' \
		-o -name '*.toc' -o -name '*.fls' -o -name '*.fdb_latexmk' -o -name '*.synctex.gz' \
		-o -name '*.nav' -o -name '*.snm' -o -name '*.vrb' \) -delete
	@find notes -type f -name '*.tex' -delete
	@find notes -type f -name '*.pdf' -delete
