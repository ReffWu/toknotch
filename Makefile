export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer

PROJECT := TokNotch.xcodeproj
SCHEME  := TokNotch
DEST    := platform=macOS,arch=arm64

.PHONY: gen build test run clean tokscale

gen:
	xcodegen generate

# Refresh the tokscale build that ships inside the app. Pass a version to pin
# one: `make tokscale VERSION=4.15.1`.
tokscale:
	./scripts/fetch-tokscale.sh $(VERSION)

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

.PHONY: archive dmg notarize release verify-release

# Release configuration, exported with the Developer ID identity. `xcodebuild
# archive` + `-exportArchive` rather than a plain build: it re-signs the bundle
# Release configuration, built and archived locally.
archive: gen
	rm -rf $(RELEASE_DIR)
	mkdir -p $(RELEASE_DIR)
	@touch build/.metadata_never_index
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		-configuration Release -archivePath $(RELEASE_DIR)/$(APP_NAME).xcarchive archive

# A plain drag-to-Applications disk image.
dmg: archive
	rm -f $(DMG)
	rm -rf $(RELEASE_DIR)/stage
	mkdir -p $(RELEASE_DIR)/stage
	cp -R $(RELEASE_DIR)/$(APP_NAME).xcarchive/Products/Applications/$(APP_NAME).app $(RELEASE_DIR)/stage/
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

# The feed customers' copies poll. Signs each update with the EdDSA private key
# in the login keychain — Sparkle installs nothing that key did not sign, so a
# compromised host cannot push code.
#
# Writes into docs/, which GitHub Pages serves. The dmg goes there too, so the
# URL the appcast advertises is the one the file actually sits at — a mismatch
# is the usual reason an update downloads and then fails to verify.
# NOT docs/ — that holds the design frames and specs, and GitHub Pages serves
# whatever it is pointed at. Publishing from there would put the whole design
# history on the public web alongside the download.
PAGES_DIR := site
# Where the dmg actually sits. The enclosure URL the appcast advertises has to
# match it exactly, or an update downloads and then fails to verify.
DOWNLOAD_PREFIX := https://hivinz.com/

appcast: $(DMG)
	@test -n "$(SPARKLE_BIN)" || (echo "Sparkle tools not found — run make build first" && exit 1)
	mkdir -p $(PAGES_DIR)
	@# Rebuilt from what is actually in the folder, never merged into the old
	@# one. The dmg keeps a constant name, so only one build can exist at a
	@# time — but generate_appcast preserves entries it already knows, and left
	@# the previous version advertised at a URL now serving a different file,
	@# with a signature that could never verify.
	rm -f $(PAGES_DIR)/appcast.xml
	cp $(DMG) $(PAGES_DIR)/
	$(SPARKLE_BIN)/generate_appcast $(PAGES_DIR) --download-url-prefix $(DOWNLOAD_PREFIX)
	@echo "Publish by committing $(PAGES_DIR)/ and pushing."

release: notarize verify-release appcast
	@echo "Notarized: $(DMG)"

# What Gatekeeper on a customer's Mac will check. `spctl` accepting the app is
# the actual proof that the download will open without a right-click.
verify-release:
	xcrun stapler validate $(DMG)
	hdiutil attach $(DMG) -nobrowse -mountpoint $(RELEASE_DIR)/mnt
	codesign --verify --deep --strict --verbose=2 $(RELEASE_DIR)/mnt/$(APP_NAME).app
	spctl --assess --type execute --verbose=4 $(RELEASE_DIR)/mnt/$(APP_NAME).app
	hdiutil detach $(RELEASE_DIR)/mnt
