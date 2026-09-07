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
# Downloads both platform packages from the npm registry and `lipo`s them into
# one universal binary. Both are needed: the app itself builds universal, so
# shipping an arm64-only helper would give an Intel Mac an app that launches
# and then reads nothing at all — the worst possible way for this to fail.
# Nothing is installed onto this machine.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Vendor/tokscale"
VERSION="${1:-$(cat "$DEST/VERSION" 2>/dev/null || echo latest)}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ "$VERSION" = "latest" ]; then
  VERSION=$(curl -fsSL "https://registry.npmjs.org/@tokscale/cli-darwin-arm64/latest" \
    | python3 -c 'import sys,json;print(json.load(sys.stdin)["version"])')
fi

slices=()
for arch in darwin-arm64 darwin-x64; do
  echo "fetching @tokscale/cli-$arch@$VERSION"
  url=$(curl -fsSL "https://registry.npmjs.org/@tokscale/cli-$arch/$VERSION" \
    | python3 -c 'import sys,json;print(json.load(sys.stdin)["dist"]["tarball"])')
  mkdir -p "$WORK/$arch"
  curl -fsSL "$url" | tar -xz -C "$WORK/$arch"
  slices+=("$WORK/$arch/package/bin/tokscale")
  # Only the arm64 package carries this; it is dlopen'd and optional.
  if [ -f "$WORK/$arch/package/bin/libFoundationModels.dylib" ]; then
    cp "$WORK/$arch/package/bin/libFoundationModels.dylib" "$DEST/"
  fi
done

mkdir -p "$DEST"
lipo -create "${slices[@]}" -output "$DEST/tokscale"
chmod +x "$DEST/tokscale"
echo "$VERSION" > "$DEST/VERSION"

echo "bundled tokscale $VERSION ($(du -h "$DEST/tokscale" | cut -f1))"
lipo -info "$DEST/tokscale"
"$DEST/tokscale" --version
