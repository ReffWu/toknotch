<div align="center">

<img src="docs/assets/icon.png" width="128" height="128" alt="TokNotch" />

# TokNotch

**How many times over has each AI plan paid for itself?**

Claude Code, Codex and the rest — priced against the published API rates,
sitting at the edge of your screen.

English · [简体中文](README.zh-CN.md)

[![macOS 14.0+](https://img.shields.io/badge/macOS-14.0%2B-blue?logo=apple&style=flat-square)](https://github.com/ReffWu/toknotch)
[![License: MIT](https://img.shields.io/badge/License-MIT-emerald.svg?style=flat-square)](LICENSE)
[![9 languages](https://img.shields.io/badge/languages-9-cyan?style=flat-square)](#it-speaks-your-language)

</div>

---

You know what you pay every month. You don't know what you got for it.

TokNotch adds up everything your coding tools actually ran, prices it at what
the same work would have cost on the published API rates, and puts one number
in front of you:

<div align="center">

### **13.4× paid back**

</div>

Or, when a plan hasn't earned its keep yet: **$18 to go**.

<p align="center">
  <img src="docs/assets/preview-tooltip.png" width="48%" alt="A usage card, opened" />
  <img src="docs/assets/preview-detail.png" width="48%" alt="TokNotch resting at the screen edge" />
</p>

---

## The payback number

Tell TokNotch what a plan costs and when it renews. That's the whole setup.

For **Claude Code** it usually doesn't even ask — the plan is recognised from
`~/.claude.json`, the ordinary config file Claude Code already keeps. For
**Codex** it reads the ChatGPT plan the same way. For everyone else you pick
your plan by name from a list (Claude Pro, ChatGPT Plus, Google AI Ultra…)
rather than looking a price up, or type any figure you like.

It then counts **by your real billing period, not the calendar month**. A plan
billed on the 3rd paid for the 3rd through the 2nd — judging it on what happened
since the 1st quietly mixes in days the last payment already covered. On the 2nd
of the month that's nearly a whole period of somebody else's usage.

---

## And three rings, always on

**Today · This month · All time.** Token counts, at the edge of the screen.

The arcs aren't decoration. Today is measured against **your best day in the
last thirty**, this month against **the same days last month**, all time against
**the next milestone**. Every card says what it's comparing against.

A full ring means you beat your own record. It's never a warning, and there's
nothing here to run out of.

---

## What it counts

Everything your coding tools have actually run, grouped by **who made the model**
rather than who billed for it — so a Qwen you ran locally still counts as Qwen,
and a GLM billed through someone else's plan still counts as Zhipu.

> Anthropic · OpenAI · Google · DeepSeek · Qwen · Zhipu GLM · Moonshot Kimi ·
> MiniMax · xAI · Xiaomi MiMo · NVIDIA · Meta · Mistral

Each can have a ring of its own. They're all **off by default**, and the list
you choose from is built from what this Mac has really run — vendors you've
never touched never appear.

The counting is done by [tokscale](https://github.com/junhoyeo/tokscale), which
ships inside the app.

---

## Nothing to install. Nothing leaves your Mac.

No Homebrew. No npm. No Node. No account, no sign-in, no API key.

TokNotch reads the session logs your coding tools already write in your home
folder. It never opens the keychain, never shows you a password prompt, and
never sends anything anywhere.

Codex is the one exception worth spelling out: its plan lives inside
`~/.codex/auth.json`, which *is* a credential file. Only the three plan claims
are ever read from it — the plan type and its dates. The access token, refresh
token and API key sitting beside them are never read, never copied, never
logged.

---

## Where it sits

**Any of the four edges.** Left or right as a slim column; top or bottom as a
wide bar. On a MacBook with a notch, the top edge runs up to meet it so the two
read as one shape.

**Out of the way until you want it.** At rest it's a small pill at the edge —
reach for it and it opens. Or keep it open always, or hide it completely.

**Or barely there at all.** A Dock icon, a menu bar item, or neither.

It knows about your Dock and your menu bar, and moves when they do.

---

## It speaks your language

English · 简体中文 · 繁體中文 · 日本語 · 한국어 · Deutsch · Français · Español · Русский

Not just the words. Numbers, money and dates follow each language's own
conventions — 万 and 亿 in Chinese, k/M/B in English, Mrd. in German.

---

## Getting it

Builds are published on the [Releases page](https://github.com/ReffWu/toknotch/releases).
Drag TokNotch to Applications and open it; it updates itself after that.

**Requires macOS 14 (Sonoma) or newer.**

### Building it yourself

```sh
brew install xcodegen
make run
```

A Debug build, ad-hoc signed, which is enough to run and develop against.
See [CONTRIBUTING.md](CONTRIBUTING.md) for the rest, and
[docs/RELEASING.md](docs/RELEASING.md) for how a release is cut.

---

## Under the hood

[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) walks through the pieces. The short
version: a borderless `NSPanel` that draws a real notch shape, a poller around
the bundled tokscale binary, and a SwiftUI card that unfolds out of the edge.

---

## Credits

TokNotch began as a fork of [vinzdg/codenotch](https://github.com/vinzdg/codenotch)
and was rewritten around local usage accounting. The original is MIT licensed and
its copyright is kept in [LICENSE](LICENSE).

Usage figures come from [tokscale](https://github.com/junhoyeo/tokscale) (MIT),
bundled in `Vendor/tokscale/`. Updates use [Sparkle](https://sparkle-project.org) (MIT).

## License

[MIT](LICENSE).
