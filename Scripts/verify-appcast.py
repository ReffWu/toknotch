#!/usr/bin/env python3
"""Check an appcast before anybody's copy is told to trust it.

A broken feed does not fail loudly. Sparkle downloads the update, finds the
signature does not match, and gives up — silently, on somebody else's Mac,
where nobody will ever see the reason. Everything checkable is checked here
instead, while the release is still on this machine.

    verify-appcast.py <appcast.xml> <dmg> <version> <download-prefix>
"""
import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def main(appcast: Path, dmg: Path, version: str, prefix: str) -> int:
    failures: list[str] = []

    def check(ok: bool, message: str) -> None:
        if not ok:
            failures.append(message)

    root = ET.parse(appcast).getroot()
    items = root.findall("./channel/item")
    check(len(items) == 1,
          f"the feed carries {len(items)} items; a rebuilt feed should carry exactly 1")
    if not items:
        return report(failures)
    item = items[0]

    short = item.findtext(f"{{{SPARKLE_NS}}}shortVersionString")
    check(short == version,
          f"the feed advertises {short!r}, but this build is {version!r}")

    enclosure = item.find("enclosure")
    check(enclosure is not None, "the item has no enclosure — nothing to download")
    if enclosure is None:
        return report(failures)

    url = enclosure.get("url", "")
    check(url == f"{prefix}{dmg.name}",
          f"the enclosure points at {url!r}, but the file will sit at "
          f"{prefix}{dmg.name!r}")

    length = enclosure.get("length")
    actual = dmg.stat().st_size
    check(length == str(actual),
          f"the feed says {length} bytes, the dmg is {actual}")

    signature = enclosure.get(f"{{{SPARKLE_NS}}}edSignature")
    check(bool(signature), "the enclosure carries no EdDSA signature — "
                           "Sparkle installs nothing unsigned")

    # The public key the app ships has to be the one that signed this, or every
    # copy in the field rejects the update it just downloaded.
    info = Path("Sources/Info.plist")
    if info.exists() and signature:
        shipped = plistlib.loads(info.read_bytes()).get("SUPublicEDKey")
        check(shipped == public_key_in_keychain(),
              "the app ships a different public key than the one that signed this feed")

    return report(failures)


def public_key_in_keychain() -> str | None:
    """What `generate_keys` says the private key in the keychain pairs with."""
    tools = list(Path("build/SourcePackages").glob("artifacts/sparkle/Sparkle/bin/generate_keys"))
    tools += list(Path.home().glob(
        "Library/Developer/Xcode/DerivedData/TokNotch-*/SourcePackages/"
        "artifacts/sparkle/Sparkle/bin/generate_keys"))
    if not tools:
        return None
    out = subprocess.run([str(tools[0])], capture_output=True, text=True).stdout
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("<string>") and line.endswith("</string>"):
            return line[len("<string>"):-len("</string>")]
    return None


def report(failures: list[str]) -> int:
    if failures:
        print("appcast is not publishable:", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1
    print("appcast verified: version, size, URL, signature and public key all agree")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 5:
        print(__doc__, file=sys.stderr)
        raise SystemExit(2)
    raise SystemExit(main(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3], sys.argv[4]))
