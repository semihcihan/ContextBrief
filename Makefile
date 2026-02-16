# Developer guide for this repository:
# - Use `make help` to see common workflows.
# - Use `make dev` for local iterative development.
# - Use `make release-dmg VERSION=x.y.z BUILD_NUMBER=n` for release artifacts.

APP_TARGET := ContextGeneratorApp
APP_BUNDLE_NAME ?= ContextBrief
APP_EXECUTABLE_NAME ?= ContextBrief
APP_DISPLAY_NAME ?= Context Brief
BUNDLE_IDENTIFIER ?= com.semihcihan.contextgenerator
VERSION ?= 1.0.0
BUILD_NUMBER ?= 1
MIN_MACOS_VERSION ?= 13.0
LOG ?= 0
DEBUG_ENV :=
XCODE_APP ?= /Applications/Xcode_26.app
DEVELOPER_DIR ?= $(XCODE_APP)/Contents/Developer

ifneq (,$(filter log,$(MAKECMDGOALS)))
LOG := 1
endif

ifeq ($(LOG),1)
DEBUG_ENV := CONTEXT_GENERATOR_DEBUG_LOGS=1 CONTEXT_GENERATOR_TERMINAL_LOGS=1
endif

.PHONY: help dev dev-stop log release-app release-dmg run-release-app
WATCH_PATTERN := watchexec -e swift --watch Sources --watch Package.swift --restart -- .*swift run $(APP_TARGET)
APP_BUNDLE := .build/release/$(APP_BUNDLE_NAME).app
APP_BUNDLE_EXEC := $(APP_BUNDLE)/Contents/MacOS/$(APP_EXECUTABLE_NAME)
APP_BUNDLE_INFO := $(APP_BUNDLE)/Contents/Info.plist
APP_BUNDLE_RESOURCES := $(APP_BUNDLE)/Contents/Resources
INFO_PLIST_TEMPLATE := scripts/Info.plist.template
DMG_NAME ?= $(APP_BUNDLE_NAME).dmg
DMG_OUTPUT ?= .build/release/$(DMG_NAME)

# Show available developer/release commands.
help:
	@printf '%s\n' \
		'Available targets:' \
		'  make dev                                  Run app with file watching + auto restart' \
		'  make dev log                              Same as dev, with debug logging enabled' \
		'  make dev-stop                             Stop watcher and running app process' \
		'  make release-app VERSION=1.0.0 BUILD_NUMBER=1' \
		'                                            Build release .app bundle in .build/release/' \
		'  make release-dmg VERSION=1.0.0 BUILD_NUMBER=1' \
		'                                            Build release .app and package .dmg' \
		'  make run-release-app VERSION=1.0.0 BUILD_NUMBER=1' \
		'                                            Build release app and run it' \
		'' \
		'Config variables (override inline if needed):' \
		'  XCODE_APP=/Applications/Xcode_26.app' \
		'  VERSION=1.0.0 BUILD_NUMBER=1' \
		'  BUNDLE_IDENTIFIER=com.semihcihan.contextgenerator'

# Development loop:
# - requires watchexec (`brew install watchexec`)
# - watches `Sources` and `Package.swift`
# - restarts app on each Swift change
dev:
	@command -v watchexec >/dev/null 2>&1 || { echo "watchexec is required. Install with: brew install watchexec"; exit 1; }
	@test -d "$(DEVELOPER_DIR)" || { echo "DEVELOPER_DIR not found: $(DEVELOPER_DIR)"; exit 1; }
	@$(MAKE) --no-print-directory dev-stop
	@watchexec \
		-e swift \
		--watch Sources \
		--watch Package.swift \
		--restart \
		-- sh -ec 'pkill -x "$(APP_TARGET)" >/dev/null 2>&1 || true; exec env $(DEBUG_ENV) DEVELOPER_DIR=$(DEVELOPER_DIR) swift run $(APP_TARGET)'

dev-stop:
	@pkill -9 -f "$(WATCH_PATTERN)" >/dev/null 2>&1 || true
	@pkill -x "$(APP_TARGET)" >/dev/null 2>&1 || true

	# explicit no-op target used by `make dev log`
log:
	@:

# Build distributable .app with templated Info.plist metadata.
release-app:
	@env DEVELOPER_DIR=$(DEVELOPER_DIR) swift build -c release
	@test -f "$(INFO_PLIST_TEMPLATE)" || { echo "Missing plist template: $(INFO_PLIST_TEMPLATE)"; exit 1; }
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE_RESOURCES)"
	@cp ".build/release/$(APP_TARGET)" "$(APP_BUNDLE_EXEC)"
	@cp "Sources/ContextGeneratorApp/Resources/GoogleService-Info.plist" "$(APP_BUNDLE_RESOURCES)/GoogleService-Info.plist"
	# Generate final Info.plist from template placeholders.
	@sed \
		-e "s|__APP_NAME__|$(APP_EXECUTABLE_NAME)|g" \
		-e "s|__APP_DISPLAY_NAME__|$(APP_DISPLAY_NAME)|g" \
		-e "s|__BUNDLE_IDENTIFIER__|$(BUNDLE_IDENTIFIER)|g" \
		-e "s|__BUILD_NUMBER__|$(BUILD_NUMBER)|g" \
		-e "s|__APP_VERSION__|$(VERSION)|g" \
		-e "s|__MIN_MACOS_VERSION__|$(MIN_MACOS_VERSION)|g" \
		"$(INFO_PLIST_TEMPLATE)" > "$(APP_BUNDLE_INFO)"

	# Package release app into compressed DMG.
release-dmg: release-app
	@bash ./scripts/build_dmg.sh "$(APP_BUNDLE)" "$(DMG_OUTPUT)"

# Build release app and run it locally (useful for quick release sanity checks).
run-release-app: release-app
	@pkill -x "$(APP_EXECUTABLE_NAME)" >/dev/null 2>&1 || true
	@exec env $(DEBUG_ENV) "$(APP_BUNDLE_EXEC)" -FIRDebugEnabled
