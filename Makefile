# Developer guide for this repository:
# - Use `make help` to see common workflows.
# - Use `make dev` for local iterative development.
# - Use `make release-dmg VERSION=x.y.z BUILD_NUMBER=n` for release artifacts.

APP_TARGET := ContextBriefApp
APP_BUNDLE_NAME ?= ContextBrief
APP_EXECUTABLE_NAME ?= ContextBrief
APP_DISPLAY_NAME ?= Context Brief
BUNDLE_IDENTIFIER ?= com.semihcihan.contextgenerator
VERSION ?= 1.0.0
BUILD_NUMBER ?= 1
MIN_MACOS_VERSION ?= 13.0
LOG ?= 0
LOG_TERMINAL ?= 0
DEBUG_ENV :=
DEVELOPER_DIR ?= $(shell xcode-select -p)
CONTEXT_GENERATOR_LOG_FILE ?= $(CURDIR)/.logs.txt

ifneq (,$(filter log,$(MAKECMDGOALS)))
LOG := 1
endif

ifeq ($(LOG),1)
DEBUG_ENV := CONTEXT_GENERATOR_DEBUG_LOGS=1 CONTEXT_GENERATOR_LOG_FILE="$(CONTEXT_GENERATOR_LOG_FILE)"
ifeq ($(LOG_TERMINAL),1)
DEBUG_ENV := $(DEBUG_ENV) CONTEXT_GENERATOR_TERMINAL_LOGS=1
endif
endif

.PHONY: help dev dev-stop log app-icon release-app release-dmg run-release-app
WATCH_PATTERN := watchexec -e swift --watch Sources --watch Package.swift --restart -- .*swift run $(APP_TARGET)
APP_BUNDLE := .build/release/$(APP_BUNDLE_NAME).app
APP_BUNDLE_EXEC := $(APP_BUNDLE)/Contents/MacOS/$(APP_EXECUTABLE_NAME)
APP_BUNDLE_INFO := $(APP_BUNDLE)/Contents/Info.plist
APP_BUNDLE_RESOURCES := $(APP_BUNDLE)/Contents/Resources
APP_BUNDLE_FRAMEWORKS := $(APP_BUNDLE)/Contents/Frameworks
INFO_PLIST_TEMPLATE := scripts/Info.plist.template
APP_ICON_SCRIPT := scripts/generate_app_icon.sh
APP_ICON_SOURCE := docs/app-icon.html
APP_ICON_OUTPUT_DIR := Sources/ContextGeneratorApp/Resources
APP_ICON_ICNS := $(APP_ICON_OUTPUT_DIR)/AppIcon.icns
DMG_NAME ?= $(APP_BUNDLE_NAME).dmg
DMG_OUTPUT ?= .build/release/$(DMG_NAME)

# Show available developer/release commands.
help:
	@printf '%s\n' \
		'Available targets:' \
		'  make dev                                  Run app with file watching + auto restart' \
		'  make dev log                              Same as dev, with debug logging to .logs.txt (no terminal)' \
		'  make dev log LOG_TERMINAL=1               Same as dev log, also print logs to terminal' \
		'  make dev-stop                             Stop watcher and running app process' \
		'  make app-icon                             Regenerate local AppIcon.icns + AppIcon.iconset from docs/app-icon.html' \
		'  make release-app VERSION=1.0.0 BUILD_NUMBER=1' \
		'                                            Build release .app bundle in .build/release/' \
		'  make release-dmg VERSION=1.0.0 BUILD_NUMBER=1' \
		'                                            Build release .app and package .dmg' \
		'  make run-release-app VERSION=1.0.0 BUILD_NUMBER=1' \
		'                                            Build release app and run it' \
		'' \
		'Config variables (override inline if needed):' \
		'  LOG=0|1           enable debug + file logging (make dev log)' \
		'  LOG_TERMINAL=1    also print logs to terminal (e.g. make dev log LOG_TERMINAL=1)' \
		'  DEVELOPER_DIR=$$(xcode-select -p)' \
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
		-- sh -ec 'pkill -x "$(APP_TARGET)" >/dev/null 2>&1 || true; exec env $(DEBUG_ENV) GOOGLE_SERVICE_INFO_PLIST_PATH="$(CURDIR)/Sources/ContextGeneratorApp/Resources/GoogleService-Info.plist" DEVELOPER_DIR=$(DEVELOPER_DIR) swift run $(APP_TARGET)'

dev-stop:
	@pkill -9 -f "$(WATCH_PATTERN)" >/dev/null 2>&1 || true
	@pkill -x "$(APP_TARGET)" >/dev/null 2>&1 || true

	# explicit no-op target used by `make dev log`
log:
	@:

app-icon:
	@test -f "$(APP_ICON_SCRIPT)" || { echo "Missing icon generator script: $(APP_ICON_SCRIPT)"; exit 1; }
	@test -f "$(APP_ICON_SOURCE)" || { echo "Missing icon source HTML: $(APP_ICON_SOURCE)"; exit 1; }
	@bash "$(APP_ICON_SCRIPT)" "$(APP_ICON_SOURCE)" "$(APP_ICON_OUTPUT_DIR)" "AppIcon"

# Build distributable .app with templated Info.plist metadata.
release-app:
	@env DEVELOPER_DIR=$(DEVELOPER_DIR) swift build -c release
	@test -f "$(INFO_PLIST_TEMPLATE)" || { echo "Missing plist template: $(INFO_PLIST_TEMPLATE)"; exit 1; }
	@test -f "$(APP_ICON_ICNS)" || { echo "Missing generated app icon: $(APP_ICON_ICNS)"; exit 1; }
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE_RESOURCES)" "$(APP_BUNDLE_FRAMEWORKS)"
	@cp ".build/release/$(APP_TARGET)" "$(APP_BUNDLE_EXEC)"
	@cp "Sources/ContextGeneratorApp/Resources/GoogleService-Info.plist" "$(APP_BUNDLE_RESOURCES)/GoogleService-Info.plist"
	@cp "Sources/ContextGeneratorApp/Resources/config.plist" "$(APP_BUNDLE_RESOURCES)/config.plist"
	@cp "$(APP_ICON_ICNS)" "$(APP_BUNDLE_RESOURCES)/AppIcon.icns"
	@for bundle in .build/release/*.bundle; do [ -d "$$bundle" ] || continue; cp -R "$$bundle" "$(APP_BUNDLE_RESOURCES)/"; done
	@for framework in .build/release/*.framework; do [ -d "$$framework" ] || continue; cp -R "$$framework" "$(APP_BUNDLE_FRAMEWORKS)/"; done
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
