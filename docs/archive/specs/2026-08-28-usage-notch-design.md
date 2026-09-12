# Codenotch — Design Spec

> Working name. `Codenotch` is a placeholder, same as `NotchApp` in the other repo.
> Source of truth for the UI: `docs/design/frame-124-hover-tooltip.png` and
> `docs/design/frame-125-detail.png`.

## One-liner

A macOS agent app that pins a small black **side notch** to the right edge of the
screen showing, at a glance, how much of each LLM's session limit you have burned —
and whether you have hit the wall yet.

## The problem

Claude, ChatGPT and friends all meter you on rolling session windows. Today the only
way to know where you stand is to open the app, dig into a settings/usage screen, or
find out the hard way mid-thought. If you run two or three assistants in parallel
(which is the actual working pattern), there is no single place that answers "which
one still has room right now?"

## The shape of the thing

A vertical pill welded to the right edge of the display, drawn with **inverse rounded
corners** at top and bottom so it reads as part of the hardware bezel — the same trick
`~/notch-app` uses for the top notch, rotated 90°. Pure black (`#000`), no border, no
shadow of its own.

### Collapsed (resting) state

Stacked vertically, one **provider cell** per tracked LLM:

```
┌──────────┐
│   ◯ ✳    │   ← 44pt circle, dark grey fill (#2A2A2A), provider glyph centered
│   73%     │   ← percent label, white, ~15pt semibold, below the circle
│           │
│   ◯ ⌾    │
│   21%     │
│           │
│   ◯ ✦    │
│   52%     │
└──────────┘
```

- Each circle is wrapped by a **progress ring** — a stroked arc starting at 12 o'clock,
  sweeping clockwise, length = percent used.
- Ring track: `#3A3A3A`. Ring fill colour is state-driven (below).
- Percent label is *used*, not remaining. 73% means 73% burned.
- Three providers in the mockup: Claude, OpenAI, and a third slot (glyph TBD —
  Gemini / Cursor / whatever the user actually pays for). The stack is data-driven,
  so 1–5 cells all lay out the same way.

### Ring colour states

| Used      | Colour            | Meaning                        |
|-----------|-------------------|--------------------------------|
| 0–49%     | green `#28E07B`   | plenty of room                 |
| 50–79%    | yellow `#F5E400`  | getting close                  |
| 80–99%    | orange `#FF4500`  | nearly out                     |
| 100%      | orange, full ring + dimmed glyph | limit hit, waiting for reset |

The mockup shows exactly this: 21% green, 52% yellow, 73% orange.

### Hover state — the detail tooltip

Hovering a provider cell pops a rounded black card to the **left** of the notch, with a
speech-bubble tail pointing at the hovered cell:

```
┌────────────────────────────────────────────┐
│  ✳  Claude Usage                           │
│                                            │
│  Current session          Resets in 51 min │
│  ████████████████████░░░░░░░░░             │
│  73% Used                                  │
│                                            │
│  All models            Resets Thu 12:00 AM │
│  ██░░░░░░░░░░░░░░░░░░░░░░░░░░░             │
│  7% Used                                   │
└────────────────────────────────────────────┘
```

- Header: provider glyph + "<Provider> Usage".
- One block per **limit window** the provider exposes. Claude has two: the rolling
  session window and the longer all-models window. Layout is a list, so a provider
  with one window or three windows renders fine.
- Each block: label (left) + reset copy (right), a 4pt rounded track bar, then
  "N% Used" underneath.
- Bar fill uses the same state colour as the ring for that window.
- Reset copy is relative under an hour ("Resets in 51 min"), absolute beyond that
  ("Resets Thu 12:00 AM").
- Card: `#0A0A0A`, 16pt corner radius, ~16pt padding, tail is a solid triangle.

### Interaction rules

- The notch is **always visible**, click-through everywhere except its own bounds.
- Hover in → tooltip fades/springs in over ~180ms. Hover out → 250ms grace, then out.
  The grace matters because the pointer has to cross the gap between card and cell.
- Click a cell → opens that provider's usage page in the browser (secondary, cheap).
- Right-click anywhere on the notch → menu: Settings…, Refresh now, Hide for 1 hour, Quit.
- Auto-hide options (never / on fullscreen / on any window over it) live in Settings.

## Data model

```
Provider   { id, displayName, glyph, accentColor, enabled, sortIndex }
LimitWindow{ id, providerID, label, usedFraction, resetsAt, windowKind }
Snapshot   { providerID, windows: [LimitWindow], fetchedAt, status }
Status     = .ok | .stale(since:) | .needsAuth | .unsupported | .error(String)
```

The notch cell shows the **most-constrained** window for that provider — the one with
the highest `usedFraction`. That is what "am I about to get cut off" actually means.

## Where the numbers come from — the honest part

This is the real risk in the project, so it is stated up front rather than discovered
in week two.

**No provider publishes a clean "your session limit is N% used" API.** So the data
layer is a protocol with per-provider adapters, and each adapter declares how
trustworthy it is:

```swift
protocol UsageProvider {
    var id: ProviderID { get }
    var fidelity: Fidelity { get }   // .official | .derived | .manual
    func fetchSnapshot() async throws -> Snapshot
}
```

Planned adapters, in the order they are worth building:

1. **Claude Code (local, `.derived`)** — parse `~/.claude/projects/**/*.jsonl` for token
   usage per message and bucket it into the 5-hour rolling window. No auth, no network,
   no ToS surface. This is the first adapter and the one that proves the UI.
2. **Manual (`.manual`)** — user types their plan's limits and the app tracks its own
   counter. Ugly but honest, and it makes every unsupported provider still useful.
3. **Anthropic API key (`.official`)** — for API-billed users, real usage/cost endpoints.
4. **Web-session adapters (`.derived`)** — read the logged-in session from the browser
   to hit the same internal endpoints the web app uses. **Fragile and ToS-adjacent for
   every vendor.** Gated behind an explicit opt-in per provider, kept out of v1, and
   the app must degrade gracefully to `.needsAuth` rather than pretending.

The UI never lies about fidelity: a `.derived` or `.manual` number gets a subtle
"~" prefix in the tooltip, and `.stale` data dims the ring.

## Non-goals for v1

- No history graphs, no weekly reports, no cost tracking.
- No writing to any provider, no proxying prompts.
- No menu bar item — the notch *is* the UI (a menu bar fallback is a later escape hatch
  for people without space on the right edge).

## Platform notes

- macOS 26, Swift/SwiftUI + AppKit, `LSUIElement: true` (agent app, no Dock icon).
- `NSPanel` with `.nonactivatingPanel`, `level = .statusBar`, `collectionBehavior`
  including `.canJoinAllSpaces` and `.fullScreenAuxiliary`.
- The panel is sized to the notch plus enough left margin to host the tooltip; the
  tooltip area is transparent and click-through until it is shown.
- Multi-display: the notch follows the screen with the menu bar, and re-anchors on
  `NSApplication.didChangeScreenParametersNotification`.
