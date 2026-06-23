PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
SCRIPT := scp-speedtest.sh
BIN := scp-speedtest

.PHONY: all check test lint format-check install uninstall

all: check

check: lint test

test:
	bash -n $(SCRIPT)
	bash -n tests/run_tests.sh
	tests/run_tests.sh

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck $(SCRIPT) tests/run_tests.sh; \
	else \
		echo "shellcheck not found; skipping"; \
	fi

format-check:
	@if command -v shfmt >/dev/null 2>&1; then \
		shfmt -d -i 2 -ci $(SCRIPT) tests/run_tests.sh; \
	else \
		echo "shfmt not found; skipping"; \
	fi

install:
	install -d "$(DESTDIR)$(BINDIR)"
	install -m 0755 $(SCRIPT) "$(DESTDIR)$(BINDIR)/$(BIN)"

uninstall:
	rm -f "$(DESTDIR)$(BINDIR)/$(BIN)"
