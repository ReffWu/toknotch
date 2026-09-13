# Architecture

TokNotch is a small app with one screen of its own. Most of it is the shape at
the edge of the display and the arithmetic behind three numbers.

```
tokscale (bundled binary)
        │  two JSON commands, on a timer
        ▼
   UsageDigest  ──►  RingBuilder  ──►  [RingSnapshot]  ──►  SwiftUI
        │                 ▲                                    │
   PlanDetector     Subscription                          NotchPanel
   PlanCatalog      BillingPeriod                    (borderless NSPanel)
```

## The layers

### `Sources/Tokscale/` — where numbers come from

`TokscaleCLI` runs the bundled `tokscale` binary and decodes its two published
JSON outputs. Deliberately not tokscale's own TUI cache file: that's scratch
space, only written while the TUI is running, and its totals measured wrong.

`UsageDigest` is the decoded reading. `Vendor` works out who *made* a model from
the model id, rather than trusting the `provider` field, which records the
billing route — the same model reached three ways gets filed under three names,
and a plan-billed GLM ends up credited to Alibaba.

`PlanDetector` recognises a plan from configuration those tools already keep on
disk (`~/.claude.json` → `oauthAccount.organizationType`, and the Codex
sign-in). Only the plan name and billing date, never the keys beside them.
`PlanCatalog` turns a plan id into a list price. `Subscription` and
`BillingPeriod` handle the real billing window — a plan billed on the 3rd paid
for the 3rd through the 2nd.

`RingBuilder` is the one place a number becomes words. Every string a person
reads is decided here, in every language. Views below it draw formatted text
and never do arithmetic.

### `Sources/Model/` — what's on screen

`UsageStore` polls on a timer and publishes `[RingSnapshot]`. There is no
on-disk cache: the reading comes from a local command that answers in under a
second, so a cache could only ever show something staler than asking again.

`UsageFormat` writes numbers the way each language writes them. `IntensityBand`
maps a fraction to a colour band.

### `Sources/Notch/` — the shape

`NotchGeometry` finds the target screen and its usable rect, respecting the menu
bar and the Dock. `NotchEdge` and `NotchPlacement` map the same layout onto four
edges through an `along`/`across` coordinate pair, so one set of measurements
serves all four. `SideNotchShape` draws the inverse-rounded corners that make it
read as part of the bezel.

`NotchPanel` is a non-activating `NSPanel` at status-bar level, click-through
outside its own path. `NotchWindowController` re-anchors it when the screen
arrangement changes. `NotchMotion` holds the springs.

Every constant in `NotchLayout` is quoted in design-frame pixels via
`Design.px(_:)` so it can be checked against
[`docs/design/frame-124-hover-tooltip.png`](design/frame-124-hover-tooltip.png)
directly.

### `Sources/Features/` and `Sources/DesignSystem/`

The rings, the arcs, the card that unfolds, the settings orb — and the palette,
type scale and vendor logo outlines they're drawn from.

### `Sources/Settings/` and `Sources/App/`

The SwiftUI settings window, the sixteen-language string table, the "what's new"
sheet, and the agent process itself: `AppDelegate`, the optional status item,
and the Sparkle updater.

## Testing

`Tests/` mirrors `Sources/` by concern rather than by file. Layout and render
tests check real geometry against the design frames; `RealDataProbe` reads this
machine's actual tokscale output and is skipped where there isn't any.

```sh
make test
```

## Two things worth knowing

**The bundled binary.** `Vendor/tokscale/` holds a universal `tokscale` built by
`Scripts/fetch-tokscale.sh` from the two npm platform packages, `lipo`'d
together. It ships as a folder reference so Xcode copies it with `ditto`, which
is what preserves the executable bit. Shipping it is the reason installing
TokNotch is the whole setup.

**Signing order at release.** tokscale arrives ad-hoc signed by whoever built
the npm package, and under the hardened runtime a process may not execute code
signed by somebody else. `make release` re-signs the nested binaries first and
the app around them second — the other order invalidates the outer signature,
and a release that skips it notarises cleanly, installs cleanly, and then reads
nothing at all.
