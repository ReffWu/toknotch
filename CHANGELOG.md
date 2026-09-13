# Changelog

All notable changes to TokNotch are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The same notes, in the app's own words and in your language, appear in the
What's New sheet after an update.

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

[1.0.0]: https://github.com/ReffWu/toknotch/releases/tag/v1.0.0
