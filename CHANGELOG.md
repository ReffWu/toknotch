# Changelog

All notable changes to TokNotch are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The same notes, in the app's own words and in your language, appear in the
What's New sheet after an update.

## [1.2.5]

WorkBuddy counts again.

### Fixed

- **WorkBuddy usage is counted again.** WorkBuddy AI 5.5 keeps its sessions in
  `~/.workbuddy-ai`, while tokscale 4.16 only reads `~/.workbuddy`, so its
  tokens were missing. TokNotch now shows tokscale the new folder for
  WorkBuddy alone and adds the result to every ring.

## [1.2.4]

Updates take care of themselves.

### Changed

- **Updates download and install on their own by default,** checked every six
  hours and installed as soon as they are ready instead of waiting for a quit
  that a login app never does. Settings has an Install updates automatically
  switch to turn it off.

## [1.2.3]

Every tool, kept current.

### Fixed

- **Antigravity usage stopped updating.** tokscale only reports Antigravity
  after `tokscale antigravity sync` copies it out of the running language
  servers, and TokNotch never ran it. It now syncs at most every five minutes,
  and on every manual refresh, on Macs with Antigravity installed.
- **A hung tokscale froze the readings.** Every tokscale call now has a
  deadline.

### Changed

- **tokscale 4.16.0,** with its Antigravity and pricing fixes.
- **tokscale is pinned and verified instead of stored in git.**
  `Vendor/tokscale/tokscale.lock` holds the version and npm integrity hashes;
  builds fetch and check exactly those bytes. Contract tests run the bundled
  binary on session logs with known token counts, and a weekly workflow opens
  an issue when a new tokscale passes (or fails) the suite.

## [1.2.2]

Meet the other apps.

### Added

- **More from Reff Wu.** The foot of Settings lists the other apps Reff Wu
  makes, read once a day from https://reffwu.github.io/apps/catalog.json, with
  Get or Open for each.

### Changed

- **A README that starts with the download,** followed by a screenshot in each
  README's language.

## [1.2.1]

Small things, done properly.

### Added

- **About window.** Shows the app icon at 240 pt with its engraving, from the
  menu bar menu and the version line in Settings.

### Changed

- **Each vendor in its own colour.** Payback multiples on notch cards and in
  Settings use the vendor's colour; only the combined total keeps green and
  orange.
- **The settings arc folds away with the notch,** travelling with its far
  corner on every edge instead of drifting the other way.

## [1.2.0]

Your payback at a glance, with less to set.

### Changed

- **Settings is two pages.** Payback lists every vendor once, with its plan,
  renewal day, payback multiple and ring switch on one line; Settings holds the
  notch, language and icon, with the version and update check in a single line
  at the bottom.
- **Menu bar instead of Dock.** TokNotch now always lives in the menu bar and
  never takes a Dock slot. Its menu shows this period's payback and today's
  tokens at a glance.
- **A menu bar icon drawn for the menu bar.** A MacBook screen with three rings
  in its notch, with a separate pixel-aligned drawing for 1x displays.
- **A better first edge.** On a Mac with a notch, a new install starts on the
  top edge; everywhere else, on the right.
- **Cleaner selection rings.** The ring around the chosen app icon and edge
  picture now follows its shape with an even gap.
- **Straight to Payback on first launch.** A fresh install opens settings on the
  Payback page; What's New only appears after later updates.

### Removed

- The "hidden" notch mode and the Dock / menu bar / neither choice.

## [1.1.0]

Keeps itself up to date, and speaks your language.

### Added

- **Automatic updates that actually arrive.** Every release is now signed with a
  Developer ID, notarized by Apple and published on GitHub with its update feed,
  so TokNotch checks for new versions on its own and installs them in place.
- **Sixteen languages.** Arabic, Italian, Dutch, Polish, Brazilian Portuguese,
  Turkish and Vietnamese join the nine already here, each writing numbers, money
  and dates its own way.
- **Pick your icon.** The app icon comes with a dark or a light frame, chosen
  under Appearance. The frame now carries the TokNotch and REFFWU engraving.

### Changed

- **Fewer things to set.** TokNotch opens with your Mac the first time it runs,
  update checks are always on, and the General page only shows where the
  numbers come from unless something needs attention.
- **New bundle identifier** `com.reffwu.toknotch`. Settings, plans and choices
  from earlier builds are carried over automatically on first launch.

## [1.0.0]

The first TokNotch release. What every plan has paid back, at a glance.

### Added

- **Subscription payback.** Tell TokNotch what a plan costs and when it renews,
  and its card shows how many times over your usage has repaid it — *13.4× paid
  back*, or *$18 to go*. Priced at what the same work would have cost on the
  published API rates.
- **Plans recognised for you.** Claude Code's plan comes from `~/.claude.json`;
  the ChatGPT plan behind Codex comes from its sign-in. Only the plan name and
  the billing dates are read, never the credentials beside them. Everything else
  is one menu away, picked by name rather than looked up by price.
- **Counted by the real billing period.** A plan billed on the 3rd paid for the
  3rd through the 2nd, and that is the stretch it judges — not the calendar
  month, which on the 2nd would be almost entirely usage the last payment
  already covered.
- **Today · This month · All time.** Three rings that stay at the edge of the
  screen. Under each is the token count; the card adds equivalent value, the
  input and output split, request count and the models used most.
- **Arcs that mean something.** Today is measured against your best day in the
  last thirty, this month against the same days last month, all time against
  the next milestone. Every card says what it is comparing against — a full
  ring means you beat your own record, not a warning.
- **A ring per vendor, only where it's earned.** Anthropic, OpenAI, DeepSeek,
  Qwen and the rest. All off by default; the list offered is built from what
  this Mac has actually run.
- **Attribution by model maker.** The same model reached through different
  routes collapses into one row, a locally-run Qwen still counts as Qwen, and a
  plan-billed GLM is no longer credited to somebody else.
- **Nothing to install.** tokscale ships inside the app (MIT). No Homebrew, no
  npm, no node. Entirely local: it never opens the keychain, never asks for a
  password, and nothing leaves the machine.
- **Four edges, or the hardware notch.** Left and right as a slim column, top
  and bottom as a wide bar. On a Mac with a notch of its own, the top edge runs
  up to meet it so the two read as one shape.
- **Nine languages,** with each language's own conventions for numbers, money
  and dates — 万 and 亿 in Chinese, k/M/B in English, Mrd. in German.
- **Updates that install themselves,** signed with an EdDSA key so nothing
  unsigned can ever be installed. See [docs/RELEASING.md](docs/RELEASING.md).

[1.2.5]: https://github.com/ReffWu/toknotch/releases/tag/v1.2.5
[1.2.4]: https://github.com/ReffWu/toknotch/releases/tag/v1.2.4
[1.2.3]: https://github.com/ReffWu/toknotch/releases/tag/v1.2.3
[1.2.2]: https://github.com/ReffWu/toknotch/releases/tag/v1.2.2
[1.2.1]: https://github.com/ReffWu/toknotch/releases/tag/v1.2.1
[1.2.0]: https://github.com/ReffWu/toknotch/releases/tag/v1.2.0
[1.1.0]: https://github.com/ReffWu/toknotch/releases/tag/v1.1.0
[1.0.0]: https://github.com/ReffWu/toknotch/releases/tag/v1.0.0
