# Quality gates for the shell in this repo.
#
#   make test   run the test suite -- needs nothing but bash, so it works
#               on a bare install before anything else is set up
#   make lint   shellcheck every shell script (needs shellcheck)
#   make fmt    show what shfmt would change (needs shfmt)
#   make check  lint + test
#
# lint and fmt say what to install rather than passing silently when the
# tool is missing -- a quality gate that quietly does nothing is worse
# than no gate.

SHELL := /bin/bash

# config/rofi/scripts/NetManagerDM.sh is excluded on purpose: it is a
# Python script that happens to carry a .sh extension (its name is baked
# into polybar/config.ini and rofi-network.sh, so renaming it is not a
# free change). shellcheck errors out on it, and so does bash -n.
# home/ holds shell files without a .sh extension, xinitrc among them --
# the one file most able to leave you at a black screen, so it is
# exactly the one worth linting.
SCRIPTS := $(shell { find . -name '*.sh' \
		-not -path './installer/target/*' \
		-not -path './.git/*' \
		-not -name 'NetManagerDM.sh'; \
	ls home/xinitrc home/bashrc home/bash_profile home/bash_logout 2>/dev/null; \
	} | sort)

.PHONY: help check test lint fmt syntax

help:
	@echo 'make test    run tests/ (bash only, no dependencies)'
	@echo 'make lint    shellcheck all shell scripts'
	@echo 'make fmt     shfmt --diff (does not rewrite anything)'
	@echo 'make syntax  bash -n every script'
	@echo 'make check   lint + syntax + test'

check: lint syntax test

test:
	@./tests/run.sh

lint:
	@command -v shellcheck >/dev/null 2>&1 || { \
		echo 'shellcheck not installed:  sudo pacman -S shellcheck' >&2; exit 1; }
	@shellcheck -x $(SCRIPTS) && echo 'shellcheck: clean ($(words $(SCRIPTS)) scripts)'

syntax:
	@fail=0; for f in $(SCRIPTS); do \
		bash -n "$$f" || { echo "syntax error: $$f" >&2; fail=1; }; \
	done; \
	[ $$fail -eq 0 ] && echo 'bash -n: clean ($(words $(SCRIPTS)) scripts)'

fmt:
	@command -v shfmt >/dev/null 2>&1 || { \
		echo 'shfmt not installed:  sudo pacman -S shfmt' >&2; exit 1; }
	@shfmt --diff --indent 4 --case-indent $(SCRIPTS)
