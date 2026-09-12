# Changelog

All notable changes to TokNotch are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The same notes, in the app's own words and in your language, appear in the
What's New sheet after an update.

## [Unreleased]

### Changed
- Documentation rewritten from the reader's side, in English
  ([README.md](README.md)) and Simplified Chinese ([README.zh-CN.md](README.zh-CN.md)).
- `docs/ARCHITECTURE.md` added; `CONTRIBUTING.md` brought back in line with the
  code after the local-usage rewrite.

## [1.0.0]

The first TokNotch release: tokscale, in the notch. Three rings, at a glance.

### Added
- **Today · This month · All time.** Three rings that stay on screen, each
  showing tokens used over that stretch. Hover for equivalent value, the
  input/output split, request count and the models used most.
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
- **Subscription payback.** Enter a vendor's monthly cost and renewal day, and
  its card shows how many times over the equivalent API value has repaid the
  subscription this billing period, and how far there is to go. Counted by the
  real billing period, not the calendar month.
- **Nothing to install.** tokscale ships inside the app (MIT). No Homebrew, no
  npm, no node. Entirely local: no keychain, no password prompts, nothing
  leaves the machine.
- **Four edges, or the hardware notch.** Left and right as a slim column, top
  and bottom as a wide bar. On a Mac with a notch of its own, the top edge runs
  up to meet it so the two read as one shape.
- **Nine languages,** with each language's own conventions for numbers, money
  and dates.

[Unreleased]: https://github.com/ReffWu/toknotch/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/ReffWu/toknotch/releases/tag/v1.0.0
