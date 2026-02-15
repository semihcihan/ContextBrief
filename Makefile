APP_TARGET := ContextGeneratorApp
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

.PHONY: dev dev-stop log release-app run-release-app
WATCH_PATTERN := watchexec -e swift --watch Sources --watch Package.swift --restart -- .*swift run $(APP_TARGET)
APP_BUNDLE := .build/release/$(APP_TARGET).app
APP_BUNDLE_EXEC := $(APP_BUNDLE)/Contents/MacOS/$(APP_TARGET)
APP_BUNDLE_INFO := $(APP_BUNDLE)/Contents/Info.plist
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

log:
	@:

release-app:
	@env DEVELOPER_DIR=$(DEVELOPER_DIR) swift build -c release
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"
	@cp ".build/release/$(APP_TARGET)" "$(APP_BUNDLE_EXEC)"
	@cp "Sources/ContextGeneratorApp/Resources/GoogleService-Info.plist" "$(APP_BUNDLE)/Contents/Resources/GoogleService-Info.plist"
	@printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' '<plist version="1.0">' '<dict>' '	<key>CFBundleName</key>' '	<string>ContextGeneratorApp</string>' '	<key>CFBundleDisplayName</key>' '	<string>ContextGeneratorApp</string>' '	<key>CFBundleIdentifier</key>' '	<string>com.semihcihan.contextgenerator</string>' '	<key>CFBundleVersion</key>' '	<string>1</string>' '	<key>CFBundleShortVersionString</key>' '	<string>1.0</string>' '	<key>CFBundlePackageType</key>' '	<string>APPL</string>' '	<key>CFBundleExecutable</key>' '	<string>ContextGeneratorApp</string>' '	<key>LSMinimumSystemVersion</key>' '	<string>13.0</string>' '</dict>' '</plist>' > "$(APP_BUNDLE_INFO)"

run-release-app: release-app
	@pkill -x "$(APP_TARGET)" >/dev/null 2>&1 || true
	@exec env $(DEBUG_ENV) "$(APP_BUNDLE_EXEC)" -FIRDebugEnabled
