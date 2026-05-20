APP_NAME := ModDrag
BINARY_NAME := mod-drag
BUILD_DIR := .build
APP_DIR := $(BUILD_DIR)/$(APP_NAME).app
APP_BINARY := $(APP_DIR)/Contents/MacOS/$(BINARY_NAME)
MODULE_CACHE := $(BUILD_DIR)/module-cache
SWIFTC := xcrun swiftc
FRAMEWORKS := -framework AppKit -framework ApplicationServices -framework CoreGraphics -framework IOKit

.PHONY: build app install-app clean

build:
	mkdir -p $(MODULE_CACHE)
	$(SWIFTC) -O -parse-as-library $(FRAMEWORKS) -module-cache-path $(MODULE_CACHE) main.swift -o $(BINARY_NAME)

app:
	sh scripts/build-app.sh

install-app: app
	cp -R "$(APP_DIR)" /Applications/
	@echo "Installed /Applications/$(APP_NAME).app"

clean:
	rm -rf $(BUILD_DIR) $(BINARY_NAME)
