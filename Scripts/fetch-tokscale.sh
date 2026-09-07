#!/bin/bash
# Refresh the bundled tokscale binary.
#
# TokNotch ships tokscale inside the app so that installing TokNotch is the
# only thing a user has to do — no Homebrew, no npm, no node. The binary is a
# self-contained Mach-O that links nothing but system frameworks, which is what
# makes that possible.
#
#   ./scripts/fetch-tokscale.sh [version]
#
# Downloads the platform package straight from the npm registry, unpacks the
# binary into Vendor/tokscale/ and records the version. Nothing is installed
# onto this machine.
set -euo pipefail

VERSION="${1:-$(cat "$(dirname "$0")/../Vendor/tokscale/VERSION" 2>/dev/null || echo latest)}"
ARCH="${ARCH:-darwin-arm64}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Vendor/tokscale"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ "$VERSION" = "latest" ]; then
  VERSION=$(curl -fsSL "https://registry.npmjs.org/@tokscale/cli-$ARCH/latest" \
    | python3 -c 'import sys,json;print(json.load(sys.stdin)["version"])')
fi

echo "fetching @tokscale/cli-$ARCH@$VERSION"
URL=$(curl -fsSL "https://registry.npmjs.org/@tokscale/cli-$ARCH/$VERSION" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["dist"]["tarball"])')
curl -fsSL "$URL" | tar -xz -C "$WORK"

mkdir -p "$DEST"
cp "$WORK/package/bin/tokscale" "$DEST/tokscale"
[ -f "$WORK/package/bin/libFoundationModels.dylib" ] \
  && cp "$WORK/package/bin/libFoundationModels.dylib" "$DEST/"
chmod +x "$DEST/tokscale"
echo "$VERSION" > "$DEST/VERSION"

echo "bundled tokscale $VERSION ($(du -h "$DEST/tokscale" | cut -f1))"
"$DEST/tokscale" --version
