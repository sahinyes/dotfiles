# Everyday maintainer tasks. `make help` lists them.
# Tests load the REAL config, so NVIM_APPNAME picks the profile under test:
# the default is the installed one (~/.config/nvim). For a side-by-side
# checkout use e.g. `make test NVIM_APPNAME=nvim-test`.
SHELL := /bin/bash
NVIM ?= nvim
export NVIM_APPNAME ?= nvim

LUA_SUITES := $(filter-out tests/helpers.lua tests/keymap_probe.lua,$(wildcard tests/*.lua))
SH_FILES := install.sh $(wildcard lib/*.sh scripts/*.sh shell/env.sh tmux/scripts/*.sh tests/install/*.sh tests/terminal/*.sh)

.PHONY: help test test-lua test-py test-terminal test-unit test-install test-mac test-release lint fmt lock-check lock-refresh

help: ## List targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'

test: test-lua test-py test-terminal test-unit ## Fast suites (Lua, Python, tmux/doctor, installer units)

test-lua: ## Neovim suites, headless, with the full config
	@rc=0; for t in $(LUA_SUITES); do \
	  $(NVIM) --headless -i NONE -c "luafile $$t" || rc=1; \
	done; exit $$rc

test-py: ## Note migration tests
	python3 -B -m unittest tests/test_migrate.py

test-terminal: ## tmux.conf on an isolated server, doctor.sh, nn in a real terminal
	bash tests/terminal/tmux_spec.sh
	bash tests/terminal/doctor_spec.sh
	bash tests/terminal/nn_spec.sh

test-unit: ## install.sh helpers in a throwaway HOME (no network)
	tests/install/unit-test.sh

test-install: ## install.sh in Debian containers (docker, slow)
	tests/install/run.sh

test-mac: ## install.sh on macOS in a throwaway HOME
	tests/install/mac-test.sh

test-release: ## Signed-tag trust-key/update flow with throwaway keys
	tests/install/release-test.sh

lint: ## stylua, shellcheck, shfmt, bash 3.2 syntax, ruff, gitleaks
	stylua --check nvim tests
	shellcheck -x $(SH_FILES)
	shfmt -i 2 -ci -d install.sh lib/*.sh scripts/lock-refresh.sh tests/install/*.sh
	@for f in $(SH_FILES); do /bin/bash -n "$$f" || exit 1; done
	ruff check --no-cache scripts tests
	ruff format --no-cache --check scripts tests
	gitleaks dir . --no-banner --redact

fmt: ## Format Lua and Python
	stylua nvim tests
	ruff format --no-cache scripts tests

lock-check: ## Verify tools.lock pins against upstream (read-only, needs gh)
	scripts/lock-refresh.sh --check

lock-refresh: ## Re-derive tools.lock pins; review `git diff tools.lock` after
	scripts/lock-refresh.sh
