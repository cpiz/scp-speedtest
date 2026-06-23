PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
SCRIPT := scp-speedtest.sh
INSTALL_SCRIPT := install.sh
BIN := scp-speedtest
VERSION := $(shell sed -n 's/^VERSION="\([^"]*\)"/\1/p' $(SCRIPT))
DIST_NAME := scp-speedtest-$(VERSION)
DIST_ROOT := dist/$(DIST_NAME)
DIST_ARCHIVE := dist/$(DIST_NAME).tar.gz

.PHONY: all check test lint format-check install uninstall dist clean

all: check

check: lint test

test:
	bash -n $(SCRIPT)
	bash -n $(INSTALL_SCRIPT)
	bash -n tests/run_tests.sh
	tests/run_tests.sh

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck $(SCRIPT) $(INSTALL_SCRIPT) tests/run_tests.sh; \
	else \
		echo "shellcheck not found; skipping"; \
	fi

format-check:
	@if command -v shfmt >/dev/null 2>&1; then \
		shfmt -d -i 2 -ci $(SCRIPT) $(INSTALL_SCRIPT) tests/run_tests.sh; \
	else \
		echo "shfmt not found; skipping"; \
	fi

install:
	install -d "$(DESTDIR)$(BINDIR)"
	install -m 0755 $(SCRIPT) "$(DESTDIR)$(BINDIR)/$(BIN)"

uninstall:
	rm -f "$(DESTDIR)$(BINDIR)/$(BIN)"

dist:
	rm -rf "$(DIST_ROOT)" "$(DIST_ARCHIVE)"
	install -d "$(DIST_ROOT)/docs" "$(DIST_ROOT)/schemas"
	install -m 0755 $(SCRIPT) "$(DIST_ROOT)/$(SCRIPT)"
	install -m 0755 $(INSTALL_SCRIPT) "$(DIST_ROOT)/$(INSTALL_SCRIPT)"
	install -m 0644 README.md README.zh-CN.md CHANGELOG.md CONTRIBUTING.md LICENSE SECURITY.md Makefile "$(DIST_ROOT)/"
	install -m 0644 docs/json-output.md "$(DIST_ROOT)/docs/"
	install -m 0644 schemas/scp-speedtest-output.schema.json "$(DIST_ROOT)/schemas/"
	tar -C dist -czf "$(DIST_ARCHIVE)" "$(DIST_NAME)"
	@echo "$(DIST_ARCHIVE)"

clean:
	rm -rf dist
