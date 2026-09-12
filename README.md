<div align="center">

<img src="docs/assets/icon.png" width="128" height="128" alt="TokNotch App Icon" />

# TokNotch

**AI Token Ledger & Activity Indicator on your macOS Notch**  
**把 tokscale 搬进刘海 · 屏幕边缘 AI Token 账本与编码助手实时指示器**

[![macOS 14.0+](https://img.shields.io/badge/macOS-14.0%2B-blue?logo=apple&style=flat-square)](https://github.com/ReffWu/toknotch)
[![License: MIT](https://img.shields.io/badge/License-MIT-emerald.svg?style=flat-square)](LICENSE)
[![Release Hub](https://img.shields.io/badge/Artifacts-Hub-cyan?style=flat-square)](https://reffwu.github.io/artifacts/toknotch/)

[Features](#features) • [What It Reads](#what-it-reads) • [Placement & Motion](#placement--motion) • [Building](#building) • [中文介绍](#中文介绍)

</div>

---

A lightweight native macOS utility that docks to any screen edge or nests seamlessly inside your MacBook's hardware notch. Powered by an embedded **tokscale** engine, TokNotch tracks real-time token burn, equivalent API retail costs, subscription payback multipliers, and live agent activity rings for your coding assistants.

<p align="center">
  <img src="docs/assets/preview-tooltip.png" width="48%" alt="TokNotch Usage Card & Rings" />
  <img src="docs/assets/preview-detail.png" width="48%" alt="TokNotch Notch Dock" />
</p>

---

## Features

- **Three-Ring Usage Indicators (今日 · 本月 · 累计)**: One glance shows today's token velocity, this month's burn, and cumulative all-time consumption with vendor-branded rings.
- **Embedded tokscale Engine**: Ships with a pre-compiled, self-contained `tokscale` binary inside the app bundle. Zero manual dependencies — no npm, node, or Homebrew required for end users.
- **Subscription Payback & Retail Value**: Automatically tallies model usage against retail API pricing, computing your subscription payback multiplier (e.g. 13.4× ROI bubble) and exact dollars saved.
- **Active Session Tracking ("Is it still working?")**:
  - A thin arc spins smoothly inside a provider's ring while a task is running.
  - Transforms into a pulsing amber ring when an agent is blocked and waiting for user input.
- **Multi-Profile Support**: Working with multiple accounts (e.g. `CLAUDE_CONFIG_DIR=~/.claude-work`) produces separate, dedicated rings that never conflict or swap places.
- **Hardware Notch Adaptation**: Sits cleanly inside MacBook Pro display notches with mathematically exact Bezier corner radii (`SideNotchShape`), or rests as a discreet pill on any of the 4 screen edges.
- **Inward Reach Protection**: Pill hot zone expands generously along the screen edge for effortless mouse triggers, but restricts inward depth so it never interferes with browser tab strips.
- **Sparkle Auto-Updates**: EdDSA cryptographic signature verification with silent background updates.
- **Global Localization**: Native support for English, 简体中文, 繁體中文, 日本語, 한국어, Deutsch, Français, Español, and Русский.

---

## What It Reads

TokNotch **never transmits credentials or requires a separate cloud login**. All metrics are read locally from the tools and sessions your Mac already holds:

| Provider / Model | Source | How |
|---|---|---|
| **Claude Code** | Official OAuth | Keychain OAuth token matching Claude Code's internal `/usage` endpoint. |
| **Cursor** | Official Local Session | Local SQLite state in the Application Support directory. |
| **Codex** | Official App Server | Local app server RPC with automatic fallback to rollout logs. |
| **Google Gemini / Antigravity** | Official / Derived | Local language server first, then quota endpoints or request digest. |
| **DeepSeek** | tokscale Engine | Local CLI session logs & API tokens across terminal environments. |
| **Alibaba (通义千问 / Qwen)** | tokscale Engine | Local coding assistant session and plan billing entries. |
| **Zhipu (智谱 GLM)** | tokscale Engine | Z.ai / Coding Plan endpoints and local tool configurations. |
| **Moonshot (Kimi)** | tokscale Engine | Local agent logs & tool state. |
| **MiniMax, xAI (Grok), Meta (Llama), Mistral** | tokscale Engine | Aggregated token accounting mapped directly to original model makers. |

Switching off a provider in Settings immediately halts reads and purges cached measurements; it never touches or revokes the owning tool's credentials.

---

## Placement & Motion

- **4 Screen Edges**: Top, bottom, left, and right. Horizontal layouts for top/bottom; vertical columns for left/right.
- **Usable Screen Anchoring**: Automatically respects menu bars and the Dock, shifting dynamically when the Dock hides or changes position.
- **Resting Pill & Unfold**: At rest, TokNotch collapses into a sleek edge pill. Hovering wakes it with smooth spring animations.
- **Glass Settings Orb**: Below the notch sits a subtle interactive orb — an unobtrusive arc at rest, blooming into a gear icon on hover.
- **App Presence Options**: Run with a Dock icon, a Menu Bar status item, both, or completely borderless and notch-only.

---

## Building

### Requirements
- macOS 14.0 (Sonoma) or newer
- Xcode 15.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Commands

```sh
# Generate project and launch a Debug build
make run

# Run unit tests
make test

# Release build (ad-hoc signed DMG)
make dmg
```

> [!NOTE]
> Debug builds are ad-hoc signed, sufficient for local testing. Run with `CODENOTCH_DEMO=1` or `TOKNOTCH_DEMO=1` to populate fixed mock data without local assistant sessions.

### Diagnostics & Unified Log

TokNotch runs borderless and windowless. To inspect real-time diagnostic output:

```sh
/usr/bin/log stream --predicate 'subsystem == "com.reff.toknotch"' --level debug
```

---

## 中文介绍

TokNotch 是一款为 macOS 深度定制的原生 AI Token 账本与编码助手常驻指示器。

### 核心亮点
1. **把 tokscale 搬进刘海**：内置开箱即用的原生 `tokscale` 引擎，无需配置 Node.js、npm 或 Python 环境，安装即用。
2. **今日 · 本月 · 累计三环设计**：一瞥即知当天消耗速率、本月累计用量与历史总账本。
3. **真实等效 API 价值与回本倍率**：精准统计各模型 Token 真实开销，换算等效官方 API 价格，并在图标上直观呈现订阅回本收益倍率（例如 13.4× 回本气泡）。
4. **编码助手忙碌与等待唤醒状态**：
   - 助手后台工作时，对应品牌环内光弧匀速旋转；
   - 助手需要确认指令、权限或等待输入时，呼吸式琥珀金光环主动提醒。
5. **硬件级刘海融合与边缘停靠**：针对 MacBook Pro 屏幕刘海做了精确贝塞尔圆角贴合，无缝融入屏幕硬件；在外接显示器上则作为小巧的折叠药丸停靠在任一屏幕边缘，鼠标触达即展开。
6. **隐私无感**：完全基于本机既有会话和本地日志提取，无需二次登录，不上传任何代码或密钥。

---

## Architecture

- `Sources/Tokscale/`: Core token aggregation engine, model-to-vendor inference, and subscription plan catalog.
- `Sources/Model/`: Usage polling store, ring snapshots, and localized currency/token formatting.
- `Sources/Notch/`: Edge placement coordinate mapping (`along`/`across`), Bezier notch curvature, window controller, and fluid spring animations.
- `Sources/Features/`: Ring glyphs, circular progress rendering, and detailed multi-model hover cards.
- `Sources/Settings/`: SwiftUI settings panel, multi-language localization dictionary, and release notes history.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## License

[MIT](LICENSE)
