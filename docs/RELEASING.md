# Releasing

The whole update chain lives on GitHub. There is no server, no domain, and
nothing hosted: the appcast Sparkle polls and the dmg it downloads are both
assets on the same GitHub release, so publishing a release is what publishes
the update.

```
project.yml (MARKETING_VERSION)
        │
        ├──► Info.plist  SUFeedURL → releases/latest/download/appcast.xml
        │                SUPublicEDKey → the key in the login keychain
        │
        └──► make publish
                 ├─ archive → sign → dmg      build/release/TokNotch.dmg
                 ├─ generate_appcast          signs with the private key
                 ├─ verify-appcast            version, size, URL, signature, key
                 └─ gh release create vX.Y.Z  dmg + appcast.xml as assets
```

## Cutting one

```sh
# 1. Bump the version: project.yml → MARKETING_VERSION, and CURRENT_PROJECT_VERSION by one.
#    Sparkle compares the build number, so it must grow on every release.

# 2. Write what changed, in all sixteen languages.
#    Sources/Resources/*.lproj/Localizable.strings → whatsNew.vXYZ.*
#    Sources/Settings/ReleaseNotes.swift → a ReleaseNote for the new version
#    CHANGELOG.md → the same, for people reading on GitHub

make test          # LocalizationTests fails if a language is missing a key
git commit …
git push           # and wait for CI

make publish       # tests, archive, sign, notarize, verify, dmg, appcast, GitHub release
```

`make release` does everything except the GitHub release, for a dry run.
`make install` puts a Developer ID signed build straight into /Applications
for trying a change on this Mac.

## What `make publish` needs, once

**1. A Developer ID Application certificate** for team 37V2HFG7YT in the login
keychain. Not "Apple Development" — that one signs builds for your own machines,
and Gatekeeper on somebody else's rejects what it signs. The script checks for it
before anything is built.

**2. The Apple account signed in to Xcode** (Xcode → Settings → Accounts).
`Scripts/release.sh` exports the archive with `destination upload`, which
submits it for notarization through that account, then waits on
`xcodebuild -exportNotarizedApp` until Apple accepts it. No password is stored
anywhere for this.

**Optional: a notarytool credential**, for notarizing the disk image itself as
well as the app inside it:

```sh
xcrun notarytool store-credentials TokNotch --apple-id <apple-id> --team-id 37V2HFG7YT
NOTARY_PROFILE=TokNotch make publish
```

The password it asks for is an app-specific password from appleid.apple.com.
Without it the dmg is left unsigned around the notarized, stapled app, which
Gatekeeper accepts; a signed but un-notarized dmg would be rejected.

`gh release create` is always given `-R ReffWu/toknotch`. Inside a clone that
also has an upstream remote, gh otherwise targets the upstream repository and
fails with a misleading "workflow scope" error.

## Why the version only appears once

`MARKETING_VERSION` in `project.yml` is the single source. XcodeGen writes it
into `Sources/Info.plist`, `Scripts/release.sh` reads it back out with `awk` to
build the tag and the enclosure URL, and `WhatsNewTests` fails if the version the app
is built as has no release note. A version typed twice is a version that will
eventually disagree with itself, and the way it disagrees is an update that
downloads and then refuses to install.

## Why signing happens inside out

tokscale arrives ad-hoc signed by whoever built the npm package. Under the
hardened runtime a process may not execute code signed by somebody else, so
`Scripts/release.sh` re-signs the nested binaries first and the app around them second —
re-signing a nested binary invalidates the signature of the bundle around it.
A release that skips this notarises cleanly, installs cleanly, and then reads
nothing at all, which is why the script runs the notarized copy's tokscale
before it builds the dmg.

## Why the appcast is not generated in CI

`generate_appcast` signs each update with the EdDSA private key in the
maintainer's login keychain. Sparkle installs nothing that key did not sign, so
neither GitHub nor anyone who can reach the release can push code to an
installed copy. Moving the signing step into CI would mean putting that private
key into a repository secret, which trades away the one property that makes the
feed safe to host on somebody else's infrastructure.

The key pair was made once and is shared by every ReffWu app. **Never generate
a new one** — that strands every copy already installed, because their embedded
public key will reject anything the new key signed.

## What `verify-appcast` checks

Run automatically by `Scripts/release.sh`, because a broken feed
fails silently on somebody else's Mac:

- the feed carries exactly one item (a rebuilt feed, not one merged into an old one)
- it advertises the version this build actually is
- the byte length matches the dmg on disk
- the enclosure URL is the one the dmg is about to occupy
- there is an EdDSA signature
- the public key the app ships is the one paired with the signing key

## If an update does not install

Sparkle gives up quietly. Check, in this order:

1. `curl -sL https://github.com/ReffWu/toknotch/releases/latest/download/appcast.xml` —
   does the feed resolve at all, and is it the release you expect?
2. Does the enclosure URL in it return the dmg, or a 404? A tag that does not
   match `v$(MARKETING_VERSION)` is the usual cause.
3. `plutil -extract SUPublicEDKey raw Sources/Info.plist` against the key
   `generate_keys` prints. A mismatch rejects every update.
4. The installed copy's log:
   `/usr/bin/log show --last 1h --predicate 'subsystem == "org.sparkle-project.Sparkle"' --info`
