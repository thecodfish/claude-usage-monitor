BINARY   = ClaudeUsageMonitor
SDK      = $(shell xcrun --sdk macosx --show-sdk-path)
SOURCES  = Sources/ClaudeUsageMonitor/main.swift \
           Sources/ClaudeUsageMonitor/AppDelegate.swift \
           Sources/ClaudeUsageMonitor/UsageScraper.swift \
           Sources/ClaudeUsageMonitor/LoginWindowController.swift \
           Sources/ClaudeUsageMonitor/PopoverView.swift
APP      = $(BINARY).app/Contents

.PHONY: all build bundle run clean

all: bundle

build:
	mkdir -p .build
	xcrun swiftc \
	    -sdk "$(SDK)" \
	    -target arm64-apple-macosx13.0 \
	    -framework AppKit \
	    -framework WebKit \
	    -O \
	    $(SOURCES) \
	    -o .build/$(BINARY)

bundle: build
	mkdir -p $(APP)/MacOS
	cp .build/$(BINARY) $(APP)/MacOS/
	cp Sources/ClaudeUsageMonitor/Resources/Info.plist $(APP)/
	codesign --force --sign - \
	    --entitlements ClaudeUsageMonitor.entitlements \
	    --options runtime \
	    $(APP)/MacOS/$(BINARY)

run: bundle
	killall $(BINARY) 2>/dev/null; sleep 0.3; open $(BINARY).app

clean:
	rm -rf .build $(BINARY).app
