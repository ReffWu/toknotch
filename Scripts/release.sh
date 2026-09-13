#!/usr/bin/env bash
# Build, sign, notarize and (with --publish) release TokNotch.
#
#   Scripts/release.sh             everything up to a verified dmg and appcast
#   Scripts/release.sh --publish   the same, then the GitHub release
#
# Notarization goes through the Apple account signed in to Xcode, so no
# notarytool password is needed. With NOTARY_PROFILE set to a stored notarytool
# credential, the disk image itself is signed, notarized and stapled too.
set -euo pipefail
cd "$(dirname "$0")/.."

app="TokNotch"
repo="ReffWu/toknotch"
team="37V2HFG7YT"
identity="Developer ID Application: XIN SHENG WU ($team)"
version="$(awk -F'"' '/MARKETING_VERSION:/ {print $2}' project.yml)"
root="build/release"
archive="$root/$app.xcarchive"
packages="build/SourcePackages"
feed="$root/feed"
dmg="$root/$app.dmg"
prefix="https://github.com/$repo/releases/download/v$version/"

security find-identity -v -p codesigning | grep -q "$identity" || {
  echo "No '$identity' certificate in the keychain." >&2
  exit 1
}

rm -rf "$root"
mkdir -p "$root"
touch build/.metadata_never_index

xcodegen generate
xcodebuild -project "$app.xcodeproj" -scheme "$app" -destination 'platform=macOS,arch=arm64' \
  -configuration Debug -clonedSourcePackagesDirPath "$packages" test -quiet

xcodebuild archive -quiet -project "$app.xcodeproj" -scheme "$app" -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$archive" \
  -clonedSourcePackagesDirPath "$packages" \
  CODE_SIGN_IDENTITY="Developer ID Application" CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$team" ENABLE_HARDENED_RUNTIME=YES

# tokscale arrives ad-hoc signed. Under the hardened runtime the app may only run
# code signed by its own team, so the nested binaries are signed first and the
# bundle around them last.
inside="$archive/Products/Applications/$app.app"
for nested in "$inside/Contents/Resources/tokscale/libFoundationModels.dylib" \
              "$inside/Contents/Resources/tokscale/tokscale"; do
  codesign --force --options runtime --timestamp --sign "$identity" "$nested"
done
codesign --force --options runtime --timestamp --sign "$identity" "$inside"

cat > "$root/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>destination</key>
  <string>upload</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>signingCertificate</key>
  <string>Developer ID Application</string>
  <key>teamID</key>
  <string>${team}</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive -allowProvisioningUpdates \
  -archivePath "$archive" -exportOptionsPlist "$root/export.plist" -exportPath "$root/submitted"

for _ in $(seq 1 60); do
  if xcodebuild -exportNotarizedApp -allowProvisioningUpdates \
    -archivePath "$archive" -exportPath "$root/notarized" >/dev/null 2>&1; then
    break
  fi
  echo "Waiting for Apple to notarize $app $version"
  sleep 30
done
shipped="$root/notarized/$app.app"
test -d "$shipped"

codesign --verify --deep --strict --verbose=2 "$shipped"
xcrun stapler validate "$shipped"
spctl --assess --type execute --verbose=4 "$shipped"
"$shipped/Contents/Resources/tokscale/tokscale" --version

stage="$root/stage"
mkdir -p "$stage"
ditto "$shipped" "$stage/$app.app"
ln -s /Applications "$stage/Applications"
hdiutil create -quiet -ov -volname "$app" -srcfolder "$stage" -format UDZO "$dmg"
rm -rf "$stage"
if [ -n "${NOTARY_PROFILE:-}" ]; then
  codesign --force --timestamp --sign "$identity" "$dmg"
  xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$dmg"
fi
(cd "$root" && shasum -a 256 "$app.dmg" > "$app.dmg.sha256")

mkdir -p "$feed"
cp "$dmg" "$feed/"
"$packages/artifacts/sparkle/Sparkle/bin/generate_appcast" "$feed" --download-url-prefix "$prefix"
python3 Scripts/verify-appcast.py "$feed/appcast.xml" "$feed/$app.dmg" "$version" "$prefix"

if [ "${1:-}" = "--publish" ]; then
  awk -v v="$version" '
    $0 ~ "^## \\[" v "\\]" { on = 1; next }
    on && /^## \[/ { exit }
    on { print }
  ' CHANGELOG.md > "$root/notes.md"
  gh release create -R "$repo" "v$version" "$dmg" "$root/$app.dmg.sha256" "$feed/appcast.xml" \
    --title "$app $version" --notes-file "$root/notes.md" --target main --draft
  gh release edit -R "$repo" "v$version" --draft=false --latest
fi

echo "$app $version is signed, notarized and ready in $root"
