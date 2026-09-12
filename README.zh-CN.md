<div align="center">

<img src="docs/assets/icon.png" width="128" height="128" alt="TokNotch" />

# TokNotch

**每个月都在为 AI 付钱。现在，你能看见它值多少。**

[English](README.md) · 简体中文

[![macOS 14.0+](https://img.shields.io/badge/macOS-14.0%2B-blue?logo=apple&style=flat-square)](https://github.com/ReffWu/toknotch)
[![License: MIT](https://img.shields.io/badge/License-MIT-emerald.svg?style=flat-square)](LICENSE)
[![9 种语言](https://img.shields.io/badge/languages-9-cyan?style=flat-square)](#它说你的语言)

</div>

---

屏幕边上常驻三个环：**今日**、**本月**、**累计**。
鼠标挪过去，它就展开。整个 App 就是这件事。

<p align="center">
  <img src="docs/assets/preview-tooltip.png" width="48%" alt="鼠标靠近时展开的用量卡片" />
  <img src="docs/assets/preview-detail.png" width="48%" alt="停靠在屏幕边缘的 TokNotch" />
</p>

---

## 就三件事

### 1. 抬眼一看就够了

不用打开面板，不用留着一个网页。可以让环一直亮在屏幕上，也可以让它平时缩成边上一枚
小药丸、鼠标够过去才展开 —— 无论哪种，你抬眼，就知道了。

而且弧度是有含义的。今日，对比的是**最近三十天里你最猛的那一天**；本月，对比的是
**上个月同样这几天**；累计，对比的是**下一个里程碑**。环走满，意味着你破了自己的纪录 ——
它从来不是警告，这里也没有任何额度会被用完。

### 2. 这个月的订阅，回本了吗？

你知道自己付了多少。你不知道自己拿到了多少。

把某个订阅的月费和扣费日告诉 TokNotch，它就会按官方 API 的公开价，把你这段时间跑掉的
Token 折算成等值金额。然后告诉你唯一想知道的那句话：**已回本 13.4 倍**，或者**还差 $18**。

它按真实的计费周期算，不是自然月。3 号扣费的套餐，买的就是 3 号到下月 2 号，
它判断的也正是这一段。

Claude 和 ChatGPT 通常连问都不用问 —— 套餐是从这些工具本来就存在你 Mac 上的配置里
认出来的。

### 3. 什么都不用装，什么都不外传。

不需要 Homebrew，不需要 npm，不需要 Node。不用注册，不用登录，不用 API Key。

TokNotch 读的是你的编码工具本来就在家目录里写下的会话日志 —— 仅此而已。
它不碰钥匙串，不会弹密码框，也不会把任何东西发到任何地方。

---

## 它统计什么

你的编码工具真正跑过的一切。归类按**谁造的模型**，而不是按谁收的钱 ——
所以本地跑的 Qwen 仍然算通义千问，经转售渠道调用的 GLM 仍然算智谱。

> Anthropic · OpenAI · Google · DeepSeek · 通义千问 · 智谱 GLM · 月之暗面 Kimi ·
> MiniMax · xAI · 小米 MiMo · NVIDIA · Meta · Mistral

每家都可以单独占一个环，显示它的累计用量和在总量里的占比。这些环**默认全部关闭**，
而且可选列表是由这台 Mac 真实跑过的记录生成的 —— 你没用过的厂商，压根不会出现。

统计由 [tokscale](https://github.com/junhoyeo/tokscale) 完成，它已经内置在 App 里。
不用装，也不用操心更新。

---

## 它待在哪

**四条边随便挑。** 左右是一根细长的竖条，上下是一道横贯的宽条。在带刘海的 MacBook 上，
顶边会一直延伸上去与刘海相接，两者看起来是同一个形状。

**不打扰，要看才出来。** 平时只是边上一枚小药丸，鼠标靠过去才展开。也可以让它一直开着，
或者彻底藏起来 —— 设置里你说了算。

**甚至可以近乎不存在。** Dock 图标、菜单栏图标，或者两个都不要。

它认得你的 Dock 和菜单栏，它们动，它跟着动。

---

## 它说你的语言

English · 简体中文 · 繁體中文 · 日本語 · 한국어 · Deutsch · Français · Español · Русский

不只是文字。数字、金额和日期都按各自语言的习惯来 —— 中文里是万和亿，
英文里是 k/M/B，德文里是 Mrd.。

---

## 装上它

构建版本发布在 [Releases 页面](https://github.com/ReffWu/toknotch/releases)。
把 TokNotch 拖进"应用程序"打开即可，之后它会自己更新。

**需要 macOS 14 (Sonoma) 或更新版本。**

### 自己编译

```sh
brew install xcodegen
make run
```

这会出一个 Debug 构建，ad-hoc 签名，足够本地运行和调试。
其余细节见 [CONTRIBUTING.md](CONTRIBUTING.md)。

---

## 里面是怎么做的

如果你想知道它怎么工作，[ARCHITECTURE.md](docs/ARCHITECTURE.md) 讲了各部分的构成。
一句话版本：一个无边框的 `NSPanel` 画出真实的刘海形状，一个轮询器包着内置的 tokscale
可执行文件，再加一张从边缘展开的 SwiftUI 卡片。

---

## 致谢

TokNotch 起初 fork 自 [vinzdg/codenotch](https://github.com/vinzdg/codenotch)，
后来围绕本地用量统计做了重写。原项目采用 MIT 协议，其版权声明保留在 [LICENSE](LICENSE) 中。

用量数据来自 [tokscale](https://github.com/junhoyeo/tokscale)（MIT），内置于
`Vendor/tokscale/`。自动更新使用 [Sparkle](https://sparkle-project.org)（MIT）。

## 许可

[MIT](LICENSE)。
