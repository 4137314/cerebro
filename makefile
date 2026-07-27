PROJECT_DIR := $(shell pwd)
GUIX_RUN     := ./bin/guix-run

.PHONY: install install-hooks bootstrap-check shell ci export clean-latex

## One-time setup: installs the 'cerbero' launcher and wires up the
## versioned git hooks in githooks/ (see githooks/pre-commit, post-commit).
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

## Hooks are tracked files in githooks/, not the untracked .git/hooks/ --
## this is what makes them "versioned git hooks". Local repo config only.
install-hooks:
	@chmod +x githooks/* bin/bootstrap-check bin/cerebro-issue bin/guix-run
	@git config core.hooksPath githooks
	@echo "git core.hooksPath -> githooks/"

## Reports which prerequisites are actually present on this machine.
bootstrap-check:
	@./bin/bootstrap-check

## Drop into the pinned, isolated environment interactively.
shell:
	@$(GUIX_RUN)

## Parametric export: one .org source, several LaTeX/PDF variants.
## Usage: make export FILE=notes/example.org PROFILE=full
##        make export FILE=notes/example.org PROFILE=statements-only
PROFILE ?= full
export:
	@test -n "$(FILE)" || (echo "usage: make export FILE=path/to/note.org [PROFILE=full|statements-only]"; exit 1)
	@$(GUIX_RUN) emacs --batch -l bin/org-export-latex.el -- --profile=$(PROFILE) $(FILE)

## Local "CI/CD": no server, no forge dependency -- this is what
## githooks/post-commit calls. bootstrap-check's exit status is only a
## warning here (not a hard prerequisite): a missing tool shouldn't turn
## an informational post-commit step into a scary failure on every
## commit before Guix is even installed -- see bin/guix-run.
ci:
	@./bin/bootstrap-check || echo "ci: bootstrap-check found gaps (see above) -- continuing anyway"
	@$(GUIX_RUN) emacs --batch -l bin/org-export-latex.el -- --profile=full notes/example.org
	@echo "ci: ok (demo export succeeded)"

## Generated build output only -- never touches latex/cerebro.cls itself.
clean-latex:
	@find notes latex -type f \( -name '*.aux' -o -name '*.log' -o -name '*.out' \
		-o -name '*.toc' -o -name '*.fls' -o -name '*.fdb_latexmk' -o -name '*.synctex.gz' \) -delete
	@find notes -type f -name '*.tex' -delete
	@find notes -type f -name '*.pdf' -delete
