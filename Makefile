APP := build/Turnring.app
# Command Line Tools ship the swift-testing macro plugin outside the default search path.
CLT_TESTING := /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
TEST_FLAGS := $(if $(wildcard $(CLT_TESTING)),-Xswiftc -plugin-path -Xswiftc $(CLT_TESTING))

.PHONY: build bundle run test clean

build:
	swift build -c release

# Wrap the plain binary in a minimal bundle; notifications need a bundle ID.
bundle: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp .build/release/turnring $(APP)/Contents/MacOS/turnring
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign - $(APP)

# Run from ~/Applications: usernoted rejects bundles in temporary folders.
run: bundle
	-pkill -x turnring
	rm -rf ~/Applications/Turnring.app
	mkdir -p ~/Applications
	cp -R $(APP) ~/Applications/Turnring.app
	open ~/Applications/Turnring.app

test:
	swift test $(TEST_FLAGS)

clean:
	rm -rf .build build
