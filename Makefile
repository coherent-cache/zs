SCRIPTS := bin/zs bin/zn bin/zp bin/zmx-login shell/zmx.bash

.PHONY: test lint

lint:
	@for f in $(SCRIPTS); do bash -n $$f || exit 1; done
	@echo "lint: syntax ok"
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -S error $(SCRIPTS) && echo "lint: shellcheck ok"; \
	fi

test: lint
	bats tests
