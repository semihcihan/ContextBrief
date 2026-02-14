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

.PHONY: dev log
dev:
	@command -v watchexec >/dev/null 2>&1 || { echo "watchexec is required. Install with: brew install watchexec"; exit 1; }
	@test -d "$(DEVELOPER_DIR)" || { echo "DEVELOPER_DIR not found: $(DEVELOPER_DIR)"; exit 1; }
	@watchexec \
		-e swift \
		--watch Sources \
		--watch Package.swift \
		--restart \
		-- "$(DEBUG_ENV) DEVELOPER_DIR=$(DEVELOPER_DIR) swift run $(APP_TARGET)"

log:
	@:
