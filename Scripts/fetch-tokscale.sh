#!/bin/bash
# Put the pinned tokscale build inside Vendor/tokscale, verified.
#
# TokNotch ships tokscale inside the app so that installing TokNotch is the
# only thing a user has to do: no Homebrew, no npm, no node. The binary is a
# self-contained Mach-O from tokscale's own npm packages (MIT), which link
# nothing but system frameworks.
#
#   ./Scripts/fetch-tokscale.sh            make sure the pinned version is here
#   ./Scripts/fetch-tokscale.sh 4.16.0     move the pin to that version
#   ./Scripts/fetch-tokscale.sh latest     move the pin to the newest release
#
# The binary is not kept in git. What is kept is Vendor/tokscale/tokscale.lock:
# the version and the npm integrity hash of each platform package. Every
# download is checked against it, so a build can only ever contain the exact
# bytes that were tested, whoever builds it and whenever.
#
# Both platform packages are fetched and `lipo`ed into one universal binary:
# the app builds universal, and an arm64-only helper would give an Intel Mac an
# app that launches and then reads nothing at all.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Vendor/tokscale"
LOCK="$DEST/tokscale.lock"
ARCHES=(darwin-arm64 darwin-x64)

locked() { grep "^$1=" "$LOCK" | cut -d= -f2-; }
registry() {
  curl -fsSL "https://registry.npmjs.org/@tokscale/cli-$1/$2" \
    | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['version'], d['dist']['tarball'], d['dist']['integrity'])"
}

REQUEST="${1:-}"
if [ -z "$REQUEST" ]; then
  VERSION="$(locked version)"
  if [ -x "$DEST/tokscale" ] && [ "$("$DEST/tokscale" --version 2>/dev/null)" = "tokscale $VERSION" ]; then
    exit 0
  fi
else
  read -r VERSION _ _ < <(registry darwin-arm64 "$REQUEST")
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$DEST"
slices=()
for arch in "${ARCHES[@]}"; do
  read -r _ url published < <(registry "$arch" "$VERSION")
  expected="$published"
  if [ -z "$REQUEST" ]; then
    expected="$(locked "$arch")"
    if [ "$expected" != "$published" ]; then
      echo "tokscale $VERSION ($arch) on npm no longer matches tokscale.lock" >&2
      exit 1
    fi
  fi
  echo "fetching @tokscale/cli-$arch@$VERSION"
  curl -fsSL "$url" -o "$WORK/$arch.tgz"
  actual="sha512-$(openssl dgst -sha512 -binary "$WORK/$arch.tgz" | base64 | tr -d '\n')"
  if [ "$actual" != "$expected" ]; then
    echo "integrity check failed for @tokscale/cli-$arch@$VERSION" >&2
    exit 1
  fi
  echo "$actual" > "$WORK/$arch.integrity"
  mkdir -p "$WORK/$arch"
  tar -xzf "$WORK/$arch.tgz" -C "$WORK/$arch"
  slices+=("$WORK/$arch/package/bin/tokscale")
  # Only the arm64 package carries this; tokscale dlopens it and runs without it.
  if [ -f "$WORK/$arch/package/bin/libFoundationModels.dylib" ]; then
    cp "$WORK/$arch/package/bin/libFoundationModels.dylib" "$DEST/"
  fi
done

lipo -create "${slices[@]}" -output "$DEST/tokscale"
chmod +x "$DEST/tokscale"
echo "$VERSION" > "$DEST/VERSION"
if [ -n "$REQUEST" ]; then
  {
    echo "version=$VERSION"
    for arch in "${ARCHES[@]}"; do echo "$arch=$(cat "$WORK/$arch.integrity")"; done
  } > "$LOCK"
fi

echo "bundled tokscale $VERSION ($(du -h "$DEST/tokscale" | cut -f1))"
"$DEST/tokscale" --version
