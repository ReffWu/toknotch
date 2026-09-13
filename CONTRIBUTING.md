# Contributing

## Building

```sh
brew install xcodegen   # once — project.yml generates the .xcodeproj
make build              # Debug build, ad-hoc signed
make test               # unit tests
make run                # build and launch
```

None of these need an Apple Developer account. `xcodebuild` ad-hoc signs a Debug
build automatically, which is enough to run and debug locally.

`TOKNOTCH_DEMO=1` fills the notch with fixed mock data, so
you can work on the UI on a machine with no assistant sessions on it.

`make release` is different: it archives, signs with a Developer ID certificate,
notarizes with Apple, and regenerates the Sparkle feed. That's the maintainer's
job for cutting an official build, and it needs credentials only the maintainer
has. You won't need it to contribute.

## How the code is laid out

[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) walks through it. The short
version:

| | |
|---|---|
| `Sources/Tokscale/` | Reads the bundled binary, infers vendors, prices plans, decides every string a number becomes |
| `Sources/Model/` | Polls on a timer, publishes ring snapshots, formats numbers per language |
| `Sources/Notch/` | Four-edge placement, the notch shape, the panel, the springs |
| `Sources/Features/` | Rings, arcs, the card that unfolds |
| `Sources/DesignSystem/` | Palette, type scale, vendor logo outlines |
| `Sources/Settings/` | Settings window, sixteen-language strings, what's-new sheet |

## Before opening a PR

- `make test` passes.
- New behavior has a test. `Tests/` mirrors `Sources/` by concern, not by
  file — look for the existing test class closest to what you're changing
  before adding a new one.
- If you're changing layout math in `Sources/Notch/NotchLayout.swift`, check it
  against `docs/design/frame-124-hover-tooltip.png` — every constant there is
  quoted from that frame in design-frame pixels via `Design.px(_:)`.

## Code style

- Comments explain **why**, not what — a hidden constraint, a bug a piece of
  code works around, a design decision that would otherwise look arbitrary.
  If removing a comment wouldn't confuse the next reader, it shouldn't be
  there.
- No premature abstraction. Three similar lines beat an early helper.
- Never invent a number. If a reading can't be had, the UI says so — see the
  `status.*` keys in `Sources/Resources/en.lproj/Localizable.strings` for the
  shape those messages take.

## Adding a vendor

Model attribution is by **maker**, not by billing route. To add one:

1. Add a case to `Vendor` in `Sources/Tokscale/Vendor.swift`, and a rule in
   `Vendor.inferred(fromModelID:)`. Rules are longest-token-first, so a longer
   name can't be caught by a shorter one.
2. Give it a `tint` — the company's own brand colour, never the intensity
   palette. A vendor ring answers "how much of my usage is this company", which
   is not a level of anything and must not be read as one.
3. Optionally add a single-path logo to `VendorOutline`. Without one it falls
   back to initials, which is the right outcome — a wrong logo is worse than
   honest letters.
4. If its name has a genuine local form a reader would expect (通义千问 where
   English writes Qwen), route `title(_:)` through the strings file and add the
   key to **all sixteen** `.lproj` files. Brand names that don't get translated
   stay inline.
5. If it sells a subscription, add its plans to `PlanCatalog` at published list
   price in USD.

## Adding or changing a string

Every user-visible string lives in `Sources/Resources/*.lproj/Localizable.strings`,
and all sixteen files carry the same keys. A key missing from one language is a
bug, not a fallback.

Numbers, money and dates go through `UsageFormat`, which follows each language's
own conventions — 万 and 亿 in Chinese, k/M/B in English, Mrd. in German. Don't
format a number inline.

## Reporting a bug

TokNotch runs borderless and windowless, so the unified log is the way to see
what it's doing:

```sh
/usr/bin/log show --last 10m --predicate 'subsystem == "com.reff.toknotch"' --info --debug
```

Live, while reproducing:

```sh
/usr/bin/log stream --predicate 'subsystem == "com.reff.toknotch"' --level debug
```
