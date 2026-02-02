APP_NAME := PodcastMaker
ROOT_DIR := $(abspath .)
BUILD_DIR := $(ROOT_DIR)/build
APP_DIR := $(BUILD_DIR)/$(APP_NAME).app
MACOS_DIR := $(APP_DIR)/Contents/MacOS
RES_DIR := $(APP_DIR)/Contents/Resources
FRAMEWORKS_DIR := $(APP_DIR)/Contents/Frameworks
BUILD_PRODUCTS := $(ROOT_DIR)/.build/arm64-apple-macosx/release
WHISPER_DIR := $(ROOT_DIR)/third_party/whisper
WHISPER_CLI := $(WHISPER_DIR)/whisper-cli
WHISPER_MODELS := $(WHISPER_DIR)/models

.PHONY: build run clean bundle-whisper

build:
	mkdir -p "$(MACOS_DIR)" "$(RES_DIR)" "$(FRAMEWORKS_DIR)"
	swift build -c release
	cp "$(BUILD_PRODUCTS)/$(APP_NAME)" "$(MACOS_DIR)/$(APP_NAME)"
	cp "$(ROOT_DIR)/Resources/Info.plist" "$(APP_DIR)/Contents/Info.plist"
	@if [ -d "$(BUILD_PRODUCTS)/whisper.framework" ]; then \
		cp -R "$(BUILD_PRODUCTS)/whisper.framework" "$(FRAMEWORKS_DIR)/"; \
		echo "Bundled whisper.framework into $(FRAMEWORKS_DIR)"; \
	else \
		echo "whisper.framework not found in $(BUILD_PRODUCTS)"; \
	fi
	/usr/bin/install_name_tool -add_rpath "@executable_path/../Frameworks" "$(MACOS_DIR)/$(APP_NAME)" || true
	$(MAKE) bundle-whisper
	if command -v codesign >/dev/null 2>&1; then \
		codesign --force --deep --sign - "$(APP_DIR)"; \
	fi
	@echo "Built $(APP_DIR)"

bundle-whisper:
	mkdir -p "$(RES_DIR)/whisper"
	@if [ -x "$(WHISPER_CLI)" ]; then \
		cp "$(WHISPER_CLI)" "$(RES_DIR)/whisper/"; \
		echo "Bundled whisper-cli into $(RES_DIR)/whisper"; \
	else \
		echo "whisper-cli not found at $(WHISPER_CLI) (skipping binary)"; \
	fi
	@if [ -d "$(WHISPER_MODELS)" ]; then \
		mkdir -p "$(RES_DIR)/whisper/models"; \
		cp -R "$(WHISPER_MODELS)/." "$(RES_DIR)/whisper/models/"; \
		echo "Bundled whisper models into $(RES_DIR)/whisper/models"; \
	else \
		echo "whisper models not found at $(WHISPER_MODELS) (skipping models)"; \
	fi

run: build
	open "$(APP_DIR)"

clean:
	rm -rf "$(BUILD_DIR)" .build
