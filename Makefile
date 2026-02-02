APP_NAME := PodcastMaker
ROOT_DIR := $(abspath .)
BUILD_DIR := $(ROOT_DIR)/build
APP_DIR := $(BUILD_DIR)/$(APP_NAME).app
MACOS_DIR := $(APP_DIR)/Contents/MacOS
RES_DIR := $(APP_DIR)/Contents/Resources

.PHONY: build run clean

build:
	mkdir -p "$(MACOS_DIR)" "$(RES_DIR)"
	xcrun swiftc -O -framework Cocoa -framework AVFoundation \
		"$(ROOT_DIR)/src/main.swift" \
		-o "$(MACOS_DIR)/$(APP_NAME)"
	cp "$(ROOT_DIR)/Resources/Info.plist" "$(APP_DIR)/Contents/Info.plist"
	if command -v codesign >/dev/null 2>&1; then \
		codesign --force --deep --sign - "$(APP_DIR)"; \
	fi
	@echo "Built $(APP_DIR)"

run: build
	open "$(APP_DIR)"

clean:
	rm -rf "$(BUILD_DIR)"
