# Beckon overlay — design brief

This document describes exactly what the overlay is, what data it has, what it must do, and where the design freedom is. The current implementation is `app/Sources/Beckon/ToastStackView.swift` (SwiftUI, ~330 lines). A redesign replaces that file; everything else (data, actions, window, keyboard routing) stays and is described below as the contract.

## 1. What the overlay is

A floating macOS panel in the top-right of the screen the mouse is on. It appears over everything, including fullscreen apps, **without taking keyboard focus**. It shows one card per thing a Claude Code session is waiting on. When there is nothing pending, the panel is hidden.

Users are mid-task in another app. The overlay has to be readable in one glance, answerable in one click or one keystroke, and gone the moment it is answered. It must look native on both light and dark backgrounds (it floats over anything: Figma, a white doc, a video).

## 2. Window contract (fixed, not part of the redesign)

- Panel width is 440 pt; the content is laid out inside that and the panel height follows the content (`intrinsicContentSize`). The panel is anchored to the top-right of the screen with ~6 pt margin.
- The window background is fully transparent; the design draws its own surfaces and shadows. Behind-window blur is available via the `Glass` view (an `NSVisualEffectView`, hudWindow material, with a dark tint).
- Dark appearance is forced (`.preferredColorScheme(.dark)` on the root). The design may use colour, but text must stay legible over any background.
- Mouse: clicks and hover work while the panel is **not** focused. Buttons must therefore be real hit targets, not keyboard-only.
- Keyboard: nothing reaches the overlay until the user presses the global hotkey **⌥Space** (or clicks into a text field). Then: `⌥1 ⌥2 ⌥3` (and plain `1 2 3` when no text field is present) act on the **top** card, `⏎` is the primary action, `⌥J` is "take me to Claude", `Esc` returns focus to the previous app. Key routing is already implemented; the design only needs to **show** these affordances and reflect the focused state.
- No CSS-like implicit animation: SwiftUI `withAnimation` is fine and encouraged for enter/exit/fold.

## 3. Data available to the design

Each card is a `PendingItem` with:

- `session` — `projectName` (folder name, e.g. `tm-reco-app`), `cwd`, `color` (stable per project, 6-colour palette), `host` (`name` like Ghostty / iTerm2 / Warp / VS Code / Claude Desktop, plus an SF Symbol `glyph`), `isSubagentActive` (bool), `canReceiveMessages` (bool: a typed reply can be delivered).
- `kind` — one of four:
  1. `.permission(tool, input, suggestions)` — Claude wants to use a tool. Derived strings: headline (`PermissionSummary.headline(tool:)`, e.g. "Claude wants to run a command."), chip (`PermissionSummary.chip(tool:input:)`, e.g. `npm test -- --coverage` or `~/src/app.py`), and the exact rule "Always" will write (`PermissionSummary.describeAlways(...)`).
  2. `.question(questions, …)` — one or more questions, each with `header` (≤12 chars, e.g. "Deploy target"), `text`, `options` (label + optional description, 2–4 typically), `multiSelect`. State: `currentQuestion` (index), `answers` (selected option indexes per question).
  3. `.finished(summary)` — Claude ended its turn; `summary` is the last assistant message, flattened, ≤220 chars. State: `replyText`, `sent` (bool), `sendError` (string or nil).
  4. `.info(text)` — informational (idle, waiting in terminal, MCP form). No reply possible.
- `createdAt` — for a relative time label ("now", "12s", "3m").
- `eyebrow` and `oneLine` — ready-made strings for a compact/folded representation.

Cards are ordered newest first. There can be 0–N; today four are shown and the rest summarised as "+N waiting".

## 4. Actions the design must expose (the only ways out of a card)

| Card | Actions (call on `Store.shared`) | Keyboard |
|---|---|---|
| permission | `allow(item, always: false)` · `allow(item, always: true)` · `deny(item)` · `jump(to: item)` | ⌥1 / ⌥2 / ⌥3 / ⌥J, ⏎ = Allow |
| question | `choose(item, option: i)` (single-select answers immediately; multi toggles) · `advanceQuestion(item)` (multi "Answer/Next") · `jump(to:)` | 1–9 pick, ⏎ confirm multi |
| finished | `sendReply(item)` (uses `replyText`) · `dismiss(item)` · `jump(to:)`; if `!canReceiveMessages`, offer "Open in <host>" (= `jump`) and Dismiss instead of a reply field | ⏎ send, ⌥1 Done, ⌥J |
| info | `jump(to: item)` · `dismiss(item)` | ⌥1 Open, ⌥2 Dismiss |

Semantics to communicate visually:
- **Dismiss / Esc never loses anything**: the request falls back to Claude's own prompt in the terminal.
- **"Always"** writes a permission rule; the design should make the scope visible (tooltip or secondary text with `describeAlways`).
- **"Take me to Claude"** opens the owning app and hands the card back to the terminal.
- **Sent** state after a reply, then the card leaves (~1 s).
- **Send error** (session gone) must be visible without being alarming.

## 5. States to design

- Card **enter** (new request), **exit** (answered/dismissed), **re-order** (older cards shift down).
- **Unfocused** (default: mouse only, show "⌥Space to focus") vs **focused** (keyboard hints visible, top card clearly marked, text field has focus ring only now).
- **Folded** older cards (one line: project · eyebrow · oneLine) and **expanded on hover**.
- **Many sessions at once**: colour and host chip must make it obvious which project is asking. Two cards from the same project should read as grouped.
- **Subagent** indicator when `isSubagentActive`.
- **Overflow** ("+N waiting").
- **Long content**: a 3-line shell command, a 220-char summary, 4 options with descriptions, 2+ questions ("Question 1 of 2").
- Optional **empty/quiet** state is not needed: the panel hides.

## 6. Current design: "Smoked glass" (direction 2b, shipped in 0.9.1)

One 440 pt glass panel (rgba(28,30,34,.45) over blur, 16 pt radius, inset top highlight, hairline, soft shadow) instead of separate cards. Brand spec: `app/Resources/brand/BRAND.md`. Fonts: Familjen Grotesk (UI) and JetBrains Mono (commands), bundled under `app/Resources/Fonts`, OFL.

- **Active item** at the top (padding 14): header row (session dot · project · host glyph box + name · "subagent" pill · time · "1 of N" in mono), 15 pt semibold title ("Run a shell command" / the question), body (mono command, option rows, summary + reply field, or info text), action row (Allow with the return mark in mint, Always with the rule tail in mono, Deny that tints red on hover, "Claude ↗" ghost button), and the footnote "Always writes Bash(…) to this project". A 2 pt mint bar with glow on the left marks keyboard focus.
- **Waiting list**: "WAITING · N" label, then 36 pt rows (dot · project · host glyph · one-line summary · time). Hovering a row expands it inline with its full body and actions; clicking the row header promotes it to active.
- **Footer** (38 pt): the mint return mark, key hints in mono (focused: "⏎ allow ⌥2 always ⌥3 deny ⌥J claude … esc"; unfocused: "⌥Space to use keys"), and "+N more" when the list is truncated at five rows.
- Mint #3DDC97 is the only accent; session colours are amber, blue, lavender, yellow, coral, teal. Deny red #E5484D is destructive-only.

The previous Toast Stack design (separate cards, indigo accent, SF fonts) is preserved in `videos/01-toast-stack.mp4` and git history before 0.9.1.

## 7. Deliverable

Either:
- (a) a new `ToastStackView.swift` that keeps the type `struct ToastStackView: View { @ObservedObject var store: Store }` as the root and the `Store`/`PendingItem` API above (build with `cd app && ./build.sh --run`; set `BECKON_SNAPSHOT_DIR=/some/dir` in the environment when launching to get PNGs of the overlay for review), or
- (b) a static mock in the existing HTML harness (`render/harness.js`, see `render/BRIEF.md`) rendered to a video with `node render/render.mjs drafts/<file>.html`, if you want to iterate on look before touching Swift.

Constraints recap: 440 pt panel, transparent window, dark scheme, mouse works unfocused, every action in §4 reachable by click, hints for the keys in §2, legible over any background, no text clipping with the long-content cases in §5.
