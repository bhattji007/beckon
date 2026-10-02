# Beckon.app — Toast Stack (initial draft)

Menu-bar macOS app. When a Claude Code session needs you, a card appears top-right over whatever you're doing, even fullscreen apps. Answer it there; focus goes back to your work.

## Install (plug and play)

```sh
./install.sh            # from the repo root: builds, copies to /Applications, launches
```

First launch opens a window that explains exactly which hook entries will be added to `~/.claude/settings.json` and asks for one click. Existing hooks are preserved, a backup goes to `~/.beckon/backups`, and Claude Code hot-reloads hooks so running sessions pick it up immediately. "Remove hooks" in the menu undoes it.

Requirements: macOS 14+, Xcode Command Line Tools (to build). No Accessibility, Screen Recording or Input Monitoring permissions are needed.

## How it works

```
Claude Code (any terminal / VS Code / JetBrains / Claude Desktop)
   └─ hook ─▶ ~/.beckon/bin/beckon-hook  (C shim, ~1 ms)
                 └─ unix socket ~/.beckon/beckon.sock ─▶ Beckon.app
                                                             ├─ shows a card
                                                             └─ replies with the decision JSON
```

| Claude moment | Hook | What the card offers | What goes back |
|---|---|---|---|
| Tool needs permission | `PermissionRequest` | Allow · Always · Deny | `decision.behavior` allow/deny; "Always" applies Claude's own `permission_suggestions` rules when present, else an exact-command rule for Bash or a project-scoped path rule (`Edit(//<cwd>/**)`) for file tools, written to the project's `.claude/settings.local.json`. Hover the button to see the exact rule; it is also logged. Note: the "project" is the directory the session was started in |
| `AskUserQuestion` | `PreToolUse` (matcher `AskUserQuestion`) | Numbered options, multi-select supported, one question at a time | `updatedInput.answers` keyed by question text |
| Turn finished | `Stop` | Summary + reply field (stays until you dismiss it, send a new prompt in that session, or the session ends) | Nothing to the hook (Claude stops normally). Your reply is sent through the session's cross-session messaging socket (`CLAUDE_CODE_MESSAGING_SOCKET`) as a user message, any time while the session is alive. If the socket is gone, the card offers "Open in <host>" instead |
| Idle / waiting / MCP form | `Notification` | "Open in <host>" | nothing (informational) |
| Lifecycle | `SessionStart/End`, `SubagentStart/Stop`, `UserPromptSubmit` | keeps the session list accurate, clears stale cards | nothing |

Design rules baked in:
- **Never worse than vanilla.** Beckon not running → shim exits 0 instantly → Claude's normal prompt. Beckon quits → every held hook is released first. Any card dismissed → passthrough.
- **Only when you're away.** If the terminal/IDE that asked is the frontmost app, Beckon stays silent (for every card type, including "waiting for input" notices) and Claude's own prompt shows. If you switch to that app while cards are up, they hand back to Claude instantly. This is app-level: a session in a hidden tab of the frontmost terminal is also treated as "you're there". (Menu: "Also show when the terminal is in front" to change this.)
- **No focus stealing.** Cards appear without taking keyboard focus. `⌥Space` focuses the top card (`⌥1/⌥2/⌥3` or `1/2/3` act, `⏎` = primary, `Esc` = back to the previous app). Clicking works without focusing.
- **Multiple sessions.** One card per request, newest on top, older ones fold to one line (hover to expand), "+N waiting" beyond four. Each project gets a stable colour; the host app (Ghostty, iTerm2, VS Code, Claude Desktop…) is shown as a chip.
- **Logged.** Every decision is appended to `~/.beckon/log.jsonl`.

## Settings, updates, uninstall

- **Settings…** (menu, ⌘,): only-when-away rule, sound, pause, hotkey recorder (any modifier + key; default ⌥Space), launch at login, daily update check, Claude Code version with a compatibility note, Copy diagnostics, Open log, Uninstall.
- **Updates** are notify-only: Beckon fetches `BeckonUpdateFeedURL` (Info.plist) once a day, compares versions, and offers the download link. Nothing is installed automatically. Users drag the new app over the old one; hooks and settings persist.
- **Uninstall** removes the hook entries, `~/.beckon`, the login item, and trashes the app. Claude Code keeps working.
- **Diagnostics** copies version, hook status, socket state, prefs, sessions and the last 30 log lines to the clipboard for bug reports. The log rotates at 5 MB.

## Safety properties

- Shim timeouts: blocking events (PermissionRequest, AskUserQuestion, Stop) may wait up to 590 s for the user; every other event gets 4 s, so a hung Beckon can never stall a session for long. A missing Beckon costs ~1 ms.
- Unfamiliar payloads (e.g. a future AskUserQuestion shape) pass straight through to Claude's own prompt.
- The app releases every held hook on quit and on SIGTERM.
- Universal binary (arm64 + x86_64), macOS 14+.

## Tests

`app/tests/smoke.sh` drives the real shim against the running app with sample payloads (passthrough latency, hold + peer-closed, question held, malformed question passthrough, Stop passthrough). The two scripted user rounds are described above.

## Files

- `Sources/beckon-hook/main.c` — the shim.
- `Sources/Beckon/` — `SocketServer` (unix socket, same-uid check), `Store` (sessions, queue, decisions), `MessagingClient` (follow-ups over the session messaging socket), `OverlayController` (non-activating `NSPanel`, `canJoinAllSpaces` + `fullScreenAuxiliary`, hotkey, focus restore), `ToastStackView` (SwiftUI cards), `Installer` (settings.json merge/unmerge), `StatusBar` (menu + onboarding).
- `Sources/Beckon/SettingsWindow.swift` (settings, hotkey recorder, diagnostics, uninstaller), `UpdateChecker.swift`, `MessagingClient.swift`.
- `build.sh` — `swiftc` + `clang` directly, universal arm64 + x86_64, builds `build/Beckon.app`. Uses the 15.x SDK from Command Line Tools because the 26/27 SDKs need Xcode's SwiftUI macro plugin. `BECKON_ARCHS="arm64"` for a faster dev build.
- `Resources/AppIcon.icns` and `Resources/icon/` (HTML source + Playwright renderer for the icon and the menu-bar bell).
- `../release/release.sh` signs, notarizes and packages a DMG/zip; see `../DISTRIBUTION.md`.

## Tested (2026-10-02, Claude Code 2.1.287, Warp)

Two scripted rounds with the user away from the terminal: single-select, multi-select and two-question cards; Allow / Deny (denial message reaches Claude) / Always (rule took effect, no further prompts); a burst of three parallel subagent permission requests; typed follow-ups over the messaging socket into an idle session; idle notice. In **auto** permission mode Claude never asks, so only question, Finished and idle cards appear — start sessions with `--permission-mode manual` if you want permission cards.

## Known limits of this draft

- Signing and notarization need the owner's Apple Developer ID (see ../DISTRIBUTION.md); unsigned downloads require "Open Anyway" on macOS 15+.
- "Open in <host>" activates the app, not the exact tab/pane yet.
- Replies arrive in the session framed as a cross-session peer message (that is how Claude Code labels anything injected through the messaging socket). Claude acts on them, but it is told not to treat them as the user approving a pending permission prompt — answer those from the permission card instead.
- A session with `crossSessionInbound: "hold"` or `"refuse"` in its settings will park or drop replies.
- No Notification Center mirror, no per-project rules UI, no SSH sessions.
