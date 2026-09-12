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
# 1. Bump the version — one place, and everything else reads it.
#    project.yml → settings.base.MARKETING_VERSION

# 2. Write what changed, in all nine languages.
#    Sources/Resources/*.lproj/Localizable.strings → whatsNew.vXYZ.*
#    Sources/Settings/ReleaseNotes.swift → a ReleaseNote for the new version
#    CHANGELOG.md → the same, for people reading on GitHub

make test          # LocalizationTests fails if a language is missing a key
git commit …

make tag           # tags vX.Y.Z and pushes it
make release       # Developer ID, notarised, stapled, verified, appcast
make publish       # creates the GitHub release with both assets
```

`make release` needs a **Developer ID Application** certificate and a stored
`notarytool` keychain profile. Without those, `make dmg` still produces an
installable disk image — ad-hoc signed, which Gatekeeper will warn about on
first open and which the user has to right-click → Open to get past.

## Why the version only appears once

`MARKETING_VERSION` in `project.yml` is the single source. XcodeGen writes it
into `Sources/Info.plist`, the Makefile reads it back out with `awk` to build
the tag and the enclosure URL, and `WhatsNewTests` fails if the version the app
is built as has no release note. A version typed twice is a version that will
eventually disagree with itself, and the way it disagrees is an update that
downloads and then refuses to install.

## Why signing happens inside out

tokscale arrives ad-hoc signed by whoever built the npm package. Under the
hardened runtime a process may not execute code signed by somebody else, so
`sign-app` re-signs the nested binaries first and the app around them second —
re-signing a nested binary invalidates the signature of the bundle around it.
A release that skips this notarises cleanly, installs cleanly, and then reads
nothing at all.

## Why the appcast is not generated in CI

`generate_appcast` signs each update with the EdDSA private key in the
maintainer's login keychain. Sparkle installs nothing that key did not sign, so
neither GitHub nor anyone who can reach the release can push code to an
installed copy. Moving the signing step into CI would mean putting that private
key into a repository secret, which trades away the one property that makes the
feed safe to host on somebody else's infrastructure.

The key pair was made once with `make sparkle-keys`. **Never run it again** —
regenerating strands every copy already installed, because their embedded
public key will reject anything the new key signed.

## What `verify-appcast` checks

Run automatically by `make release` and `make publish`, because a broken feed
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
