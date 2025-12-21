APP_ATTENTION = AIAttention
APP_RESUME = AIResume
SRC_ATTENTION = src/$(APP_ATTENTION).applescript
SRC_RESUME = src/$(APP_RESUME).applescript
BUILD_DIR = build
INSTALL_DIR = $(HOME)/Applications

.PHONY: all clean build install

all: build

build:
	mkdir -p $(BUILD_DIR)
	osacompile -o $(BUILD_DIR)/$(APP_ATTENTION).app $(SRC_ATTENTION)
	osacompile -o $(BUILD_DIR)/$(APP_RESUME).app $(SRC_RESUME)
	@if [ -f notification.mp3 ]; then cp -f notification.mp3 $(BUILD_DIR)/$(APP_ATTENTION).app/Contents/Resources/notification.mp3; fi
	@echo "Build complete."

install: build
	mkdir -p $(INSTALL_DIR)
	rm -rf $(INSTALL_DIR)/$(APP_ATTENTION).app
	rm -rf $(INSTALL_DIR)/$(APP_RESUME).app
	cp -r $(BUILD_DIR)/$(APP_ATTENTION).app $(INSTALL_DIR)/
	cp -r $(BUILD_DIR)/$(APP_RESUME).app $(INSTALL_DIR)/
	@echo "Installed apps to $(INSTALL_DIR)"
	@echo "IMPORTANT: Run BOTH apps manually once to grant permissions!"

clean:
	rm -rf $(BUILD_DIR)
