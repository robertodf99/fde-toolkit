# Hook Me Up — build plumbing. `make` builds everything from a clean clone.

# The toolchain chosen with xcode-select is used as is. Only when it is the Command
# Line Tools (which may lack Swift Testing), DEVELOPER_DIR is unset and Xcode is in
# /Applications, Xcode's toolchain is used instead.
XCODE_DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
ifeq ($(origin DEVELOPER_DIR),undefined)
  ifneq ($(findstring CommandLineTools,$(shell xcode-select -p 2>/dev/null)),)
    ifneq ($(wildcard $(XCODE_DEVELOPER_DIR)),)
      export DEVELOPER_DIR := $(XCODE_DEVELOPER_DIR)
    endif
  endif
endif

SWIFT ?= swift
FORMAT_PATHS := Package.swift Sources Tests scripts

.PHONY: build test app vsix dist signing-check selftest format lint logo install-dry-run install uninstall test-install plugin-check editor-extension-check clean

# Where `make app` puts the bundle.
APP_DIR ?= .build
APP := $(APP_DIR)/HookMeUp.app
INSTALL_DIR ?= $(HOME)/Applications
INSTALLED_APP := $(INSTALL_DIR)/Hook Me Up.app

build:
	$(SWIFT) build -c release

test:
	$(SWIFT) test

# Apple's swift-format, bundled with the toolchain; settings in .swift-format.
format:
	$(SWIFT) format format --in-place --recursive --parallel $(FORMAT_PATHS)

lint:
	$(SWIFT) format lint --strict --recursive --parallel $(FORMAT_PATHS)

# The project logo, GitHub's social preview and the Product Hunt thumbnail in docs/images
# (scripts/make-logo.swift; the app icon is drawn separately, by make app).
logo:
	$(SWIFT) scripts/make-logo.swift docs/images

# Signs with $(CODESIGN_IDENTITY) if set ("-" = ad-hoc), else the first "Apple
# Development:" identity in the keychain, else ad-hoc (see scripts/build-app.sh).
CODESIGN_IDENTITY ?=

app:
	APP_DIR="$(APP_DIR)" CODESIGN_IDENTITY="$(CODESIGN_IDENTITY)" ./scripts/build-app.sh

# The editor extension on its own (the app has it in Contents/Resources): .build/hook-me-up.vsix.
vsix:
	./scripts/build-vsix.sh .build/hook-me-up.vsix

# Release package: .build/dist/hook-me-up-$(VERSION)-macos.zip and its .sha256.
# The release workflow runs: make dist VERSION=<tag> UNIVERSAL=1 CODESIGN_IDENTITY=-
VERSION ?= dev
dist:
	VERSION="$(VERSION)" CODESIGN_IDENTITY="$(CODESIGN_IDENTITY)" ./scripts/package.sh

# Forced ad-hoc, no-identity fallback and auto-pick, in a temporary folder (.build/HookMeUp.app is left alone).
signing-check:
	./scripts/check-signing.sh

# The built hook with no agent listening must print nothing and exit 0 (fail open).
selftest: build
	./scripts/selftest-hook.sh .build/release/hook-me-up

SETTINGS ?= $(HOME)/.claude/settings.json
INSTALLED_HOOK := $(INSTALLED_APP)/Contents/MacOS/hook-me-up
SETUP := .build/release/hook-me-up-setup

# Shows what install would change, on a COPY of your settings in a private temp
# folder (removed afterwards). Your real settings file is never written.
install-dry-run: build
	@tmp=$$(mktemp -d /tmp/hmu-dryrun.XXXXXX) || exit 1; \
	if [ -f "$(SETTINGS)" ]; then cp "$(SETTINGS)" "$$tmp/settings.json"; else echo '{}' > "$$tmp/settings.json"; fi; \
	$(SETUP) install --settings "$$tmp/settings.json" --hook "$(INSTALLED_HOOK)" --state "$$tmp/state.json" --dry-run; status=$$?; \
	rm -f "$$tmp/settings.json"; rmdir "$$tmp"; \
	echo "(dry run on a temporary copy; $(SETTINGS) was not touched)"; exit $$status

# Install from source (run by the user): packages this checkout and runs install.sh
# with it (app to ~/Applications, hooks after the diff and a confirmation, LaunchAgent).
install:
	VERSION=dev CODESIGN_IDENTITY="$(CODESIGN_IDENTITY)" ./scripts/package.sh
	HOOK_ME_UP_ZIP="$(CURDIR)/.build/dist/hook-me-up-dev-macos.zip" ./install.sh

uninstall:
	./uninstall.sh

# install.sh and uninstall.sh against a throwaway HOME (never the real one).
test-install:
	./scripts/test-install.sh

# The Claude Code plugin's manifests and skills, without the claude CLI.
plugin-check:
	./scripts/check-plugin.sh

# The editor extension's JavaScript (syntax, request checks, which terminal it shows),
# with a stand-in for VS Code. Needs node; not part of CI.
editor-extension-check:
	@command -v node >/dev/null || { echo "editor-extension-check: node is not installed" >&2; exit 1; }
	node --check editor-extension/extension.js
	node scripts/test-editor-extension.js

clean:
	$(SWIFT) package clean
