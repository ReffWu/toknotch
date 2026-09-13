# `?=` rather than `:=` so a CI runner that selects its own Xcode wins.
# Release steps rely on prerequisites running in the order they are listed.
.NOTPARALLEL:

export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

PROJECT := TokNotch.xcodeproj
SCHEME  := TokNotch
DEST    := platform=macOS,arch=arm64

.PHONY: gen build test run clean tokscale

gen:
	xcodegen generate

# Refresh the tokscale build that ships inside the app. Pass a version to pin
# one: `make tokscale VERSION=4.15.1`.
tokscale:
	./Scripts/fetch-tokscale.sh $(VERSION)

build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		-configuration Debug build

test: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		-configuration Debug test

run: build
	@APP=$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		-configuration Debug -showBuildSettings 2>/dev/null \
		| awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $$2; exit}')/TokNotch.app; \
	pkill -x TokNotch || true; \
	open "$$APP"

clean:
	rm -rf build DerivedData $(PROJECT)

# --- Release ----------------------------------------------------------------
#
# Everything a release needs lives in Scripts/release.sh: tests, a Developer ID
# archive with tokscale signed inside out, notarization through the Apple
# account signed in to Xcode, a verified dmg and a signed appcast. See
# docs/RELEASING.md.

.PHONY: release publish install sparkle-keys

release:
	Scripts/release.sh

publish:
	Scripts/release.sh --publish

# A Developer ID build straight into /Applications, for trying a change on this
# Mac. Signed like a release so privacy grants and the login item carry over,
# but not notarized.
IDENTITY := Developer ID Application: XIN SHENG WU (37V2HFG7YT)
INSTALL_APP := build/install/Build/Products/Release/TokNotch.app

install: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		-configuration Release -derivedDataPath build/install \
		-clonedSourcePackagesDirPath build/SourcePackages \
		CODE_SIGN_IDENTITY="Developer ID Application" CODE_SIGN_STYLE=Manual \
		DEVELOPMENT_TEAM=37V2HFG7YT ENABLE_HARDENED_RUNTIME=YES build -quiet
	codesign --force --options runtime --timestamp --sign "$(IDENTITY)" \
		"$(INSTALL_APP)/Contents/Resources/tokscale/libFoundationModels.dylib"
	codesign --force --options runtime --timestamp --sign "$(IDENTITY)" \
		"$(INSTALL_APP)/Contents/Resources/tokscale/tokscale"
	codesign --force --options runtime --timestamp --sign "$(IDENTITY)" "$(INSTALL_APP)"
	osascript -e 'quit app id "com.reffwu.toknotch"' || true
	osascript -e 'quit app id "com.reff.toknotch"' || true
	rm -rf /Applications/TokNotch.app
	ditto "$(INSTALL_APP)" /Applications/TokNotch.app
	rm -rf build/install
	open /Applications/TokNotch.app

# One-time: the key pair Sparkle signs updates with. Shared by every ReffWu app
# and already in the login keychain. Never run this again for a shipped app.
sparkle-keys:
	build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
