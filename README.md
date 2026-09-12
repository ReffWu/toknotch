<div align="center">

<img src="docs/assets/icon.png" width="128" height="128" alt="TokNotch" />

# TokNotch

**You pay for AI every month. Now you can see what it's worth.**

English · [简体中文](README.zh-CN.md)

[![macOS 14.0+](https://img.shields.io/badge/macOS-14.0%2B-blue?logo=apple&style=flat-square)](https://github.com/ReffWu/toknotch)
[![License: MIT](https://img.shields.io/badge/License-MIT-emerald.svg?style=flat-square)](LICENSE)
[![9 languages](https://img.shields.io/badge/languages-9-cyan?style=flat-square)](#it-speaks-your-language)

</div>

---

Three rings live at the edge of your screen: **today**, **this month**, **everything**.
Reach for them and they open. That's the whole app.

<p align="center">
  <img src="docs/assets/preview-tooltip.png" width="48%" alt="The card that opens when you reach for the notch" />
  <img src="docs/assets/preview-detail.png" width="48%" alt="TokNotch resting at the screen edge" />
</p>

---

## Three things, and that's it

### 1. A glance is enough

No dashboard to open. No tab to keep alive. Leave the rings always on screen,
or let them rest as a pill at the edge and open when you reach — either way you
look up, and you know.

And the arcs mean something. Today is measured against **your best day in the
last thirty**. This month against **the same days last month**. All time against
**the next milestone**. A full ring means you beat your own record — it is never
a warning, and there is nothing to run out of.

### 2. Did the subscription pay for itself?

You know what you pay. You don't know what you got.

Tell TokNotch what a plan costs and when it renews, and it adds up what the same
work would have cost at the published API price. Then it says the only thing you
wanted to know: **paid back 13.4×**, or **$18 to go**.

It counts by the real billing period, not the calendar month. A plan billed on
the 3rd paid for the 3rd through the 2nd, and that's the stretch it judges.

For Claude and ChatGPT it usually doesn't even ask — the plan is recognised from
the configuration those tools already keep on your Mac.

### 3. Nothing to install. Nothing leaves your Mac.

No Homebrew. No npm. No Node. No account, no sign-in, no API key.

TokNotch reads the session logs your coding tools already write in your home
folder — that's it. It never opens the keychain, never shows you a password
prompt, and never sends anything anywhere.

---

## What it counts

Anything your coding tools have actually run, grouped by **who made the model**
rather than who billed for it — so a Qwen you ran locally still counts as Qwen,
and GLM through a reseller still counts as Zhipu.

> Anthropic · OpenAI · Google · DeepSeek · Qwen · Zhipu GLM · Moonshot Kimi ·
> MiniMax · xAI · Xiaomi MiMo · NVIDIA · Meta · Mistral

Each vendor can have a ring of its own — showing its lifetime usage and its
share of everything. They're all **off by default**, and the list you choose
from is built from what this Mac has really run. Vendors you've never touched
never appear.

The counting is done by [tokscale](https://github.com/junhoyeo/tokscale),
which ships inside the app. Nothing to install, nothing to keep up to date.

---

## Where it sits

**Any of the four edges.** Left or right as a slim column; top or bottom as a
wide bar. On a MacBook with a notch, the top edge runs up to meet it so the two
read as one shape.

**Out of the way until you want it.** At rest it's a small pill at the edge.
Reach for it and it opens. Or keep it open always, or hide it completely — your
call, in Settings.

**Or barely there at all.** Run it with a Dock icon, with a menu bar item, or
with neither.

It knows about your Dock and your menu bar, and moves when they do.

---

## It speaks your language

English · 简体中文 · 繁體中文 · 日本語 · 한국어 · Deutsch · Français · Español · Русский

Not just the words. Numbers, money and dates follow each language's own
conventions — 万 and 亿 in Chinese, k/M/B in English, Mrd. in German.

---

## Getting it

Builds are published on the [Releases page](https://github.com/ReffWu/toknotch/releases).
Drag TokNotch to Applications and open it. It updates itself after that.

**Requires macOS 14 (Sonoma) or newer.**

### Building it yourself

```sh
brew install xcodegen
make run
```

That's a Debug build, ad-hoc signed, which is enough to run and develop against.
See [CONTRIBUTING.md](CONTRIBUTING.md) for the rest.

---

## Under the hood

If you like knowing how things work, [ARCHITECTURE.md](docs/ARCHITECTURE.md)
walks through the pieces. The short version: a borderless `NSPanel` that draws
a real notch shape, a poller around the bundled tokscale binary, and a SwiftUI
card that unfolds out of the edge.

---

## Credits

TokNotch began as a fork of [vinzdg/codenotch](https://github.com/vinzdg/codenotch)
and was rewritten around local usage accounting. The original is MIT licensed and
its copyright is kept in [LICENSE](LICENSE).

Usage figures come from [tokscale](https://github.com/junhoyeo/tokscale) (MIT),
bundled in `Vendor/tokscale/`. Updates use [Sparkle](https://sparkle-project.org) (MIT).

## License

[MIT](LICENSE).
