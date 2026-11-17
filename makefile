# cerebro: read-only hub of the knowledge bases.  `make` lists the targets.

.DEFAULT_GOAL := help
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
# Instance name: command, Emacs server and state (~/.local/state/$(NAME)-emacs).
NAME ?= cerebro
# The reader: the sibling checkout when present (~/dev/personal/knowledge-base), else
# the version in flake.lock.
KB ?= $(abspath $(ROOT)/../knowledge-base)
OVERRIDE := $(if $(wildcard $(KB)/flake.nix),--override-input knowledge-base path:$(KB))
NIX := nix --no-warn-dirty
STATE := $(or $(XDG_STATE_HOME),$(HOME)/.local/state)/$(NAME)-emacs
APPS := $(or $(XDG_DATA_HOME),$(HOME)/.local/share)/applications
DESKTOP := $(APPS)/$(NAME).desktop
BIN := $(STATE)/profile/bin/cerebro
ENV := KB_NAME=$(NAME) CEREBRO_ROOT=$(ROOT)

help: ## list the targets
	@awk 'BEGIN{FS=":.*## "} /^[a-zA-Z0-9_-]+:.*## /{printf "  \033[1m%-12s\033[0m %s\n",$$1,$$2}' \
	  $(MAKEFILE_LIST)

run: ## open the hub (the page of the bases)
	$(ENV) $(NIX) run $(ROOT) $(OVERRIDE) --no-write-lock-file

check: ## every base: metadata, links, prerequisites, formulas and figures
	$(NIX) build $(ROOT) $(OVERRIDE) --no-write-lock-file --no-link
	$(ENV) systemd-run --user --scope -q -p MemoryMax=2G nice timeout 1800 \
	  $(NIX) run $(ROOT) $(OVERRIDE) --no-write-lock-file -- --check

install: ## build the hub and add "Cerebro" to the launcher
	mkdir -p $(STATE) $(APPS)
	$(NIX) build $(ROOT) $(OVERRIDE) --no-write-lock-file -o $(STATE)/profile
	sed -e 's|@ROOT@|$(ROOT)|g' -e 's|@BIN@|$(BIN)|g' cerebro.desktop.in > $(DESKTOP)
	-update-desktop-database $(APPS) 2>/dev/null
	@echo "installed: $(DESKTOP) (search \"cerebro\" in the launcher)"

uninstall: ## remove the launcher entry and the profile (notes and caches stay)
	rm -f $(DESKTOP) $(STATE)/profile

test: ## tests of the conversion script
	python3 -m unittest tools.test_convert_roam

.PHONY: help run check install uninstall test
