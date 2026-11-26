# Toolkit entry point. Tool-specific build settings live with each tool.
.DEFAULT_GOAL := build
HOOK_ME_UP_TARGETS := build test app vsix dist signing-check selftest format lint logo install-dry-run install uninstall test-install plugin-check editor-extension-check clean
.PHONY: $(HOOK_ME_UP_TARGETS) marketplace-check

$(HOOK_ME_UP_TARGETS):
	$(MAKE) -C tools/hook-me-up $@

marketplace-check:
	./scripts/check-marketplace.sh
