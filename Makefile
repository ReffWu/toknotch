# `?=` rather than `:=` so a CI runner that selects its own Xcode wins.
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

PROJECT := TokNotch.xcodeproj
SCHEME  := TokNotch
DEST    := platform=macOS,arch=arm64

.PHONY: gen build test run clean tokscale sparkle-keys sign-app

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

# --- Release -----------------------------------------------------------------
RELEASE_DIR := build/release
APP_NAME    := TokNotch
# The label of the stored notarytool credential in the login keychain, not
# anything to do with the app's name — it was created before the rename and
# renaming the variable is what broke `make release` after it. Recreating it
# needs an app-specific password, so the label simply stays as it is.
NOTARY_PROFILE := UsageNotch
DMG := $(RELEASE_DIR)/$(APP_NAME).dmg

.PHONY: archive dmg notarize release verify-release appcast verify-appcast tag publish

# How the build is signed.
#
# Ad-hoc by default, so `make dmg` always works and produces something you can
# hand to somebody who is willing to click through Gatekeeper. `make release`
# overrides both of these — a published build has to be Developer ID signed and
# hardened, or notarisation refuses it and Sparkle cannot install it.
SIGN_IDENTITY ?= -
SIGN_FLAGS    ?= CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)"

APP_IN_ARCHIVE = $(RELEASE_DIR)/$(APP_NAME).xcarchive/Products/Applications/$(APP_NAME).app

# Release configuration, built and archived locally.
archive: gen
	rm -rf $(RELEASE_DIR)
	mkdir -p $(RELEASE_DIR)
	@touch build/.metadata_never_index
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		-configuration Release -archivePath $(RELEASE_DIR)/$(APP_NAME).xcarchive \
		$(SIGN_FLAGS) archive

# Sign the binary we ship inside the app, then the app around it.
#
# tokscale arrives ad-hoc signed by whoever built the npm package. Under the
# hardened runtime a process may not execute code signed by somebody else, so a
# release that skips this notarises cleanly, installs cleanly, and then reads
# nothing at all. Inside out, because re-signing a nested binary invalidates the
# signature of the bundle around it.
sign-app: archive
	@if [ "$(SIGN_IDENTITY)" = "-" ]; then \
		echo "ad-hoc build: leaving signatures as they are"; \
	else \
		codesign --force --options runtime --timestamp --sign "$(SIGN_IDENTITY)" \
			"$(APP_IN_ARCHIVE)/Contents/Resources/tokscale/libFoundationModels.dylib"; \
		codesign --force --options runtime --timestamp --sign "$(SIGN_IDENTITY)" \
			"$(APP_IN_ARCHIVE)/Contents/Resources/tokscale/tokscale"; \
		codesign --force --options runtime --timestamp --sign "$(SIGN_IDENTITY)" \
			"$(APP_IN_ARCHIVE)"; \
		codesign --verify --deep --strict --verbose=2 "$(APP_IN_ARCHIVE)"; \
	fi

# A plain drag-to-Applications disk image.
dmg: sign-app
	rm -f $(DMG)
	rm -rf $(RELEASE_DIR)/stage
	mkdir -p $(RELEASE_DIR)/stage
	cp -R $(APP_IN_ARCHIVE) $(RELEASE_DIR)/stage/
	ln -s /Applications $(RELEASE_DIR)/stage/Applications
	hdiutil create -volname "$(APP_NAME)" -srcfolder $(RELEASE_DIR)/stage \
		-ov -format UDZO $(DMG)
	codesign --force --sign - $(DMG)
	rm -rf $(RELEASE_DIR)/stage

# Submits and waits. `--wait` blocks until Apple answers, which is usually a
# couple of minutes; on rejection, the log says which binary failed and why.
notarize: dmg
	xcrun notarytool submit $(DMG) --keychain-profile $(NOTARY_PROFILE) --wait
	xcrun stapler staple $(DMG)

# Sparkle ships its tools inside the resolved package artifacts.
SPARKLE_BIN = $(shell dirname $$(find $$HOME/Library/Developer/Xcode/DerivedData/TokNotch-*/SourcePackages/artifacts/sparkle -name generate_appcast 2>/dev/null | head -1))

# --- The update feed ---------------------------------------------------------
#
# Both the feed and the dmg are assets on a GitHub release. Nothing is hosted,
# nothing is committed, and no domain has to stay pointed anywhere — publishing
# a release is what publishes the update.
#
# Read from project.yml rather than repeated here, so a version bump happens in
# one place. The tag has to be `v$(VERSION)` for the enclosure URL below to
# resolve, which `make tag` is there to get right.
VERSION := $(shell awk -F'"' '/MARKETING_VERSION:/ {print $$2}' project.yml)
TAG     := v$(VERSION)

# Staged, never committed: a dmg in git is a dmg in git forever.
FEED_DIR := $(RELEASE_DIR)/feed

# Where the dmg will actually sit once the release exists. The enclosure URL the
# appcast advertises has to match it exactly, or an update downloads and then
# fails to verify.
DOWNLOAD_PREFIX := https://github.com/ReffWu/toknotch/releases/download/$(TAG)/

# Signs each update with the EdDSA private key in the login keychain — Sparkle
# installs nothing that key did not sign, so neither GitHub nor anybody who
# reaches the release can push code. That private key is why this runs here and
# not in CI.
# `dmg`, not `$(DMG)`: the dmg is built by a phony rule, so naming the file as
# a prerequisite asks make for a rule that does not exist and the target only
# ever worked when the file happened to be there already.
appcast: dmg
	@test -n "$(SPARKLE_BIN)" || (echo "Sparkle tools not found — run make build first" && exit 1)
	rm -rf $(FEED_DIR)
	mkdir -p $(FEED_DIR)
	@# Generated from an empty folder every time, never merged into an older
	@# feed. The dmg keeps a constant name, so only one build can exist at a
	@# time — but generate_appcast preserves entries it already knows, and left
	@# the previous version advertised at a URL now serving a different file,
	@# with a signature that could never verify.
	cp $(DMG) $(FEED_DIR)/
	$(SPARKLE_BIN)/generate_appcast $(FEED_DIR) --download-url-prefix $(DOWNLOAD_PREFIX)
	@echo
	@echo "Feed staged for $(TAG):"
	@ls -1 $(FEED_DIR)
	@echo "Publish it with: make publish"

# What the running copies will actually be told, checked before anybody is told
# it. Verifies the feed parses, advertises the version this build is, carries a
# signature, and points at the URL the dmg is about to occupy.
verify-appcast: appcast
	@python3 Scripts/verify-appcast.py $(FEED_DIR)/appcast.xml $(FEED_DIR)/$(APP_NAME).dmg \
		$(VERSION) $(DOWNLOAD_PREFIX)

# The tag the enclosure URL above resolves against. Separate from `publish` so a
# tag is never created by something that might fail halfway.
tag:
	@git diff --quiet || (echo "working tree is dirty — commit first" && exit 1)
	git tag -a $(TAG) -m "TokNotch $(VERSION)"
	git push origin $(TAG)

# Creates the release the feed URL points at, with the dmg and the appcast on
# it. Uploading both together is what keeps them consistent: Sparkle reads the
# appcast from the newest release and downloads the dmg beside it.
publish: verify-appcast
	gh release create $(TAG) \
		$(FEED_DIR)/$(APP_NAME).dmg $(FEED_DIR)/appcast.xml \
		--title "TokNotch $(VERSION)" --notes-file CHANGELOG.md --verify-tag

# The published build: Developer ID signed, hardened, notarised, stapled, and
# advertised in the appcast Sparkle polls.
release: SIGN_IDENTITY = Developer ID Application
release: SIGN_FLAGS = CODE_SIGN_IDENTITY="Developer ID Application" ENABLE_HARDENED_RUNTIME=YES
release: notarize verify-release verify-appcast
	@echo "Notarized: $(DMG)"

# One-time: the key pair Sparkle signs updates with. The private half goes into
# the login keychain and never leaves this Mac; the public half is printed for
# Info.plist. Run once, ever — regenerating it strands everybody already
# running a copy, because their app will reject anything the new key signed.
sparkle-keys:
	@test -n "$(SPARKLE_BIN)" || (echo "Sparkle tools not found — run make build first" && exit 1)
	$(SPARKLE_BIN)/generate_keys

# What Gatekeeper on a customer's Mac will check. `spctl` accepting the app is
# the actual proof that the download will open without a right-click.
verify-release:
	xcrun stapler validate $(DMG)
	hdiutil attach $(DMG) -nobrowse -mountpoint $(RELEASE_DIR)/mnt
	codesign --verify --deep --strict --verbose=2 $(RELEASE_DIR)/mnt/$(APP_NAME).app
	spctl --assess --type execute --verbose=4 $(RELEASE_DIR)/mnt/$(APP_NAME).app
	hdiutil detach $(RELEASE_DIR)/mnt
