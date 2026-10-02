# Beckon — answer Claude Code from anywhere on your Mac

> Status: concept + UX drafts (2026-10-02). Nothing here is built yet. Six mockup videos live in `videos/`.

## 0. One-paragraph pitch

Claude Code is great until it needs you. With three sessions in three terminals plus the VS Code extension, every permission prompt, question, or "I'm done" becomes a context switch: notification → find the window → read → answer → find your way back. Beckon is a macOS menu-bar app that turns those moments into a small overlay *on top of whatever you're doing, even a fullscreen app*. You answer in place (allow / pick an option / type a reply), the overlay disappears, and focus returns to your work. It works with every Claude Code host on the machine, handles many sessions and subagents at once, and installs with one click.

## 1. Problem, precisely

| Today | Cost |
|---|---|
| Hooks can only *notify* (`osascript display notification`). Notifications are not actionable. | You must switch windows to answer, then switch back. |
| Each terminal / IDE is its own island. | No single place lists what's waiting on you. |
| Subagents and parallel sessions multiply prompts. | Prompts arrive in bursts; you lose track of which window asked. |
| macOS fullscreen Spaces hide everything else. | The switch is a full Space swipe, not a window click. |

The user already runs notification-only hooks (permission_prompt / idle_prompt / Stop → `osascript`). Beckon replaces those with the same hook points but makes them two-way.

## 2. Principles

1. **Plug and play.** One download, one click to install the hook, zero config files to edit. If Beckon is quit, Claude Code behaves exactly as before — the shim exits immediately and Claude falls back to its normal terminal prompt. Beckon can never make Claude Code worse.
2. **Never steal focus unless asked.** The overlay appears without taking keyboard focus. The user opts in with a global hotkey (default ⌥Space) or a click. Esc or answering returns focus to the previous app, deterministically.
3. **Answer, don't navigate.** Every alert carries the decision already framed. If it cannot be acted on from the overlay, it does not ship as an alert.
4. **Host-agnostic.** Terminal (any), VS Code / JetBrains extension, Claude Desktop. The same hook JSON arrives from all of them; Beckon only differs in how it labels and, when needed, how it focuses the source window.
5. **Many at once.** Sessions, subagents, and bursts are the normal case, not the edge case. Every UX draft must show two pending items.
6. **Safe by default.** No auto-approval unless the user creates an explicit rule. Decisions are logged. The socket is user-only (0600).

## 3. What Claude Code actually gives us (verified against the hooks reference, 2026-10)

Hook events we use and what they let us return:

| Moment | Hook | Blocks Claude? | What Beckon returns |
|---|---|---|---|
| Tool needs permission | `PermissionRequest` | Yes | `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"\|"deny"}}}`; "allow always for this project" uses `updatedPermissions` |
| Claude asks a multiple-choice question | `PreToolUse` with matcher `AskUserQuestion` | Yes | `permissionDecision: "allow"` + `updatedInput` carrying the chosen answers (exact `answers` shape to be captured via `claude --debug-file` and pinned in a fixture test) |
| Claude finished a turn | `Stop` / `SubagentStop` | Yes | Nothing (let it stop) — or, if the user typed a follow-up inside the overlay within the hook's wait, `{"decision":"block","additionalContext":"<user text>"}` so Claude continues with that instruction. Must honour `stop_hook_active` to avoid loops. |
| Claude idle, waiting | `Notification` matcher `idle_prompt`, `agent_needs_input`, `permission_prompt`, `elicitation_dialog` | No | Nothing; used to show/refresh the card and as a fallback when a blocking hook was not reached |
| Background session done | `Notification` matcher `agent_completed` | No | Nothing; informational card |
| Session lifecycle | `SessionStart`, `SessionEnd`, `SubagentStart`, `SubagentStop` | No | Nothing; keeps the session registry accurate |
| MCP form | `Elicitation` | No | Informational; v2 may answer forms |

Facts that shape the design:
- Every hook stdin includes `session_id`, `cwd`, `hook_event_name`, `permission_mode`; `transcript_path` is present on most events (used to render a transcript tail and a one-line summary).
- Default command-hook timeout is **600 s** and is configurable per hook. That is long enough for a human to answer; Beckon sets its own explicit timeouts (see §5.4).
- **Hooks hot-reload.** Adding Beckon's hook to `~/.claude/settings.json` takes effect in running sessions. No restart needed — this is what makes install frictionless.
- Hooks from `~/.claude/settings.json` **do run inside the VS Code and JetBrains extensions**. Claude Desktop's local Code sessions are expected to run them too (same local runtime) but this is not documented; Beckon's install flow verifies it empirically on first launch and reports the result.
- Each session exports `CLAUDE_CODE_MESSAGING_SOCKET` (+ `CLAUDE_CODE_MESSAGING_TOKEN`), the cross-session messaging socket. Hook processes inherit the environment, so the shim can forward the socket path to Beckon. This is the second transport for free-text follow-ups (§5.3), subject to the receiving session's `crossSessionInbound` setting.
- No `preferredNotifChannel` for native macOS alerts exists; Beckon owns native notifications itself (Notification Center mirror, optional).

## 4. Architecture

```
┌──────────────── Claude Code hosts ────────────────┐
│ Terminal (Ghostty, iTerm2, Terminal.app, kitty,…) │
│ VS Code / JetBrains extension                     │   same hooks, same JSON
│ Claude Desktop (local Code sessions)              │
└───────────────┬───────────────────────────────────┘
                │ runs hook command on each event (stdin JSON)
                ▼
┌───────────────────────┐   Unix socket ~/.beckon/beckon.sock (JSON lines)
│  beckon-hook (shim)   │ ───────────────────────────────────────────┐
│  static binary, <5ms  │                                            │
│  exits 0 instantly if │   ◄── decision JSON (or nothing) ──────────┤
│  Beckon isn't running │                                            ▼
└───────────────────────┘                             ┌──────────────────────────┐
                                                      │  Beckon.app (menu bar)   │
                                                      │  • Session registry      │
                                                      │  • Event queue & rules   │
                                                      │  • Overlay windows       │
                                                      │  • Transports            │
                                                      │  • Settings / installer  │
                                                      └──────────────────────────┘
```

### 4.1 Hook shim (`beckon-hook`)
- Single static binary (Swift or Rust), installed by the app to `~/.beckon/bin/beckon-hook`. One hook entry per event, all pointing at the same binary; event type comes from `hook_event_name`.
- Behaviour: read stdin JSON → enrich (ppid chain, `$TERM_PROGRAM`, `$TMUX_PANE`, `$CLAUDE_CODE_MESSAGING_SOCKET`, `$TERM_SESSION_ID`, `$VSCODE_PID`) → connect to socket. If connect fails (app not running): **exit 0 with no output within ~2 ms**. Claude Code then shows its normal prompt. This is the no-regret guarantee.
- For blocking events (PermissionRequest, PreToolUse/AskUserQuestion, Stop) it waits for Beckon's reply, prints the decision JSON, exits 0. If Beckon replies `passthrough` (user dismissed, or timeout), it prints nothing → Claude's normal prompt appears in the terminal, so nothing is ever lost.
- For non-blocking events it fires and exits.

### 4.2 Session registry
Key = `session_id`. Each record: project (basename of `cwd`), stable color (hash of cwd → palette), host (Ghostty / iTerm2 / Terminal / VS Code / JetBrains / Claude Desktop, inferred from env + ppid chain), window handle hints (pid, `TERM_SESSION_ID`, tmux pane), messaging socket path, parent session (for subagents, via SubagentStart/Stop correlation), last activity, transcript path, pending items. Sessions age out on `SessionEnd` or when the owning pid disappears.

### 4.3 Event queue & rules
- Items: `permission`, `question`, `finished`, `idle`, `info`. Each has a session, a payload, and a transport that can resolve it.
- Ordering: blocking items first, newest-first within a session, sessions grouped. The UX draft decides presentation (stack / queue / rail / island / PiP / bubble) but the model is shared.
- Rules engine (opt-in, visible in the overlay as "Allow always for this project"): persisted as Claude-native permission rules via `updatedPermissions` so they also work when Beckon is off. Beckon never keeps a private allow-list that Claude Code can't see.
- Quiet hours / Focus: respects macOS Focus (DND) by collapsing to the ambient indicator only; never auto-answers.

### 4.4 Overlay windows (macOS specifics)
- `NSPanel`, non-activating (`.nonactivatingPanel`), level `.statusBar`/`.popUpMenu`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` → visible over fullscreen Spaces without leaving them.
- Appear without focus. Focus on ⌥Space (global hotkey via `CGEvent` tap or `NSEvent.addGlobalMonitor`) or click. Before taking focus, record `NSWorkspace.frontmostApplication`; on dismiss, `activate()` it again so focus returns deterministically.
- "Jump to source" action: bring the originating terminal tab/window to the front (per-host adapter: iTerm2 AppleScript, Terminal.app `TERM_SESSION_ID`, Ghostty/kitty via their remote-control CLIs where available, VS Code via `code -r <cwd>`, tmux `select-pane`). Always offered as the escape hatch.
- Multiple overlays: one window per draft-defined container; items within are views. Max visible configurable; the rest summarised ("+2 waiting").

### 4.5 Menu bar
Icon = Beckon mark with a badge count. Dropdown = inbox: all pending items, all sessions with status, quick toggles (Pause, Focus mode, Mirror to Notification Center), Settings, "Install hooks" health check.

## 5. Transports (how an answer gets back)

| # | Transport | Covers | Reliability | Notes |
|---|---|---|---|---|
| 1 | **Hook reply** (shim prints decision JSON) | Permission allow/deny/always, AskUserQuestion answers, Stop follow-up | Deterministic, official, host-independent | Primary. Works identically in terminal, IDE extensions, Desktop. |
| 2 | **Messaging socket** (`CLAUDE_CODE_MESSAGING_SOCKET`) | Free-text follow-ups after a Stop has already completed; nudges to an idle session | Official mechanism, protocol details to be pinned by inspection; honours `crossSessionInbound` | Secondary. Used when the user types a reply after the Stop hook window closed. |
| 3 | **Focus jump** | Anything | Always available | Fallback: bring the source window forward. Still better than today (right window, one keystroke). |
| 4 | **Terminal injection** (tmux `send-keys`, iTerm2 `write text`, kitty/WezTerm remote control) | Free text in terminals that support it | Host-specific, opt-in | Last resort, off by default; requires Accessibility only for the generic typing path. |

Design rule: Beckon shows a reply field only when transport 1 or 2 is available for that item; otherwise it shows "Open in <host>".

### 5.1 Permission flow
PermissionRequest → shim → Beckon card (tool, command, cwd, session) → user: Allow / Allow always (project) / Deny → shim prints decision → done. Dismiss/timeout → passthrough → normal terminal prompt.

### 5.2 Question flow
PreToolUse(AskUserQuestion) → card renders questions/options (single or multi-select) → `updatedInput` with answers → Claude proceeds. Dismiss → passthrough → Claude's own TUI question appears.

### 5.3 Finished / follow-up flow
Stop → shim connects; Beckon shows "Finished: <summary from transcript tail>" with a reply field. The shim waits up to N seconds (default 20 s) for a typed follow-up; if one arrives → `block` + `additionalContext` → Claude continues in the same turn. If not → shim prints nothing → Claude stops normally, card stays as an inbox item; a reply typed later goes via transport 2 (messaging socket) or, if unavailable, "Open in <host>".

### 5.4 Timeouts
Per-hook `timeout` set by the installer: PermissionRequest 300 s, PreToolUse(AskUserQuestion) 300 s, Stop 25 s, others 5 s. Beckon itself replies `passthrough` 2 s before each deadline so Claude never sees a hook timeout error.

## 6. Plug-and-play install

1. `brew install --cask beckon` or drag the DMG. Signed + notarized; Sparkle updates.
2. First launch: menu bar icon appears; onboarding sheet shows a **diff** of the hook entries about to be added to `~/.claude/settings.json` (merged, never overwriting existing hooks; backs up the file). One click "Install". Hooks hot-reload, so the next Claude prompt already routes through Beckon — the sheet proves it with a live "Test alert" button that runs `claude -p` in the background and shows the resulting card.
3. Permissions requested lazily: Notifications (optional mirror), Accessibility only if the user enables terminal injection. No Screen Recording, no Input Monitoring for the default path.
4. Health panel: shows each detected host (terminal apps, VS Code, Claude Desktop) and whether a hook from it has been seen. Missing one → one-line fix.
5. Uninstall: removes exactly the entries it added; restores backup if unchanged.
6. Zero project setup: nothing is written to repos. Teams can optionally commit a `.claude/settings.json` pointer, but it is not required.

## 7. Multi-session & multi-agent model

- **Identity:** session_id. **Grouping:** project (cwd) → color. **Hierarchy:** subagents shown as children of the main session (correlated via SubagentStart/Stop timing on the same session_id; the hook payload itself does not carry an agent id, so Beckon labels them "tm-reco-app › subagent" and, where a Task tool_input is visible via PreToolUse, by the Task description).
- **Bursts:** items coalesce per session; identical permission requests across subagents are shown once with a count and a single answer applies to all (each shim gets the same decision).
- **Presentation** is the UX question explored by the drafts; the data model is the same for all.

## 8. Security

- Socket at `~/.beckon/beckon.sock`, mode 0600, same-uid check on connect. Shim and app verify a shared per-install nonce in `~/.beckon/token`.
- Decisions are never stored as a private allow-list; only Claude-native permission rules via `updatedPermissions`.
- Every decision is appended to `~/.beckon/log.jsonl` (session, tool, command, decision, timestamp). Visible in the app.
- Secrets: command text shown in the card is read from the hook payload only; never sent anywhere. No network except Sparkle updates.

## 9. Non-goals (v1)

Remote machines over SSH (v2: shim on remote + reverse tunnel), Windows/Linux, answering MCP elicitation forms, replacing the terminal UI, team/shared dashboards.

## 10. MVP cut

| Milestone | Scope |
|---|---|
| M0 (1–2 days) | Shim + socket + menu-bar inbox; PermissionRequest allow/deny from a plain panel; passthrough on quit. Proves the loop. |
| M1 | AskUserQuestion answers; Stop follow-up via `block`; session registry with colors/hosts; non-activating overlay over fullscreen; ⌥Space + focus restore. |
| M2 | Chosen UX draft polished; multi-item handling; "Allow always" via `updatedPermissions`; focus-jump adapters for iTerm2/Terminal/Ghostty/VS Code. |
| M3 | Messaging-socket follow-ups; health panel; Sparkle; Homebrew cask; Notification Center mirror. |

Open items to pin with `claude --debug-file`: exact `AskUserQuestion` tool_input/`updatedInput` shape; Notification payload fields beyond `notification_type`; messaging socket wire format; whether Claude Desktop local sessions run user hooks (empirical check in installer).

## 11. Tech stack

Swift 6 / SwiftUI + AppKit for panels; shim in Swift (static, no Foundation startup cost) or Rust; JSON-lines over Unix socket; Sparkle; XCTest fixtures recorded from real hook payloads.

## 12. The six UX drafts (videos in `videos/`)

| # | Draft | Core idea | Best when |
|---|---|---|---|
| 1 | Toast Stack | Native-looking notification cards, top-right, actionable inline, group when many | You want it to feel like macOS, not a new app |
| 2 | HUD | Spotlight-style center palette, keyboard-first, explicit "1 of 3" queue | You answer with the keyboard and want one thing at a time |
| 3 | Edge Rail | Always-visible slim rail with one chip per session; panel slides out on demand | You run many sessions and want ambient status without interruptions |
| 4 | Notch Island | Lives in the MacBook notch, Dynamic-Island expand/contract | Laptop-first, minimal footprint, delightful |
| 5 | PiP Agents | A small live transcript window per session, lights up when it needs you | You want to *see* what agents are doing, not just be asked |
| 6 | Cursor Bubble | Alert anchored to the mouse cursor, shrinks to a dot if ignored | Zero eye travel; you're mid-task and don't want to look away |

Recommendation after watching: pick one primary (likely 1 or 2) and keep the rail/dot as the ambient layer from 3 or 6.

---

## 13. Verified on 2026-10-02 (Claude Code 2.1.287) while building the Toast Stack app

Captured from real hook runs and the Claude Code binary; these supersede the "open items" in §10.

- `PermissionRequest` stdin carries `tool_name`, `tool_input`, `permission_mode`, and **`permission_suggestions`**: an array already in `updatedPermissions` shape (e.g. `addDirectories`, `setMode`, `addRules`). "Always" in Beckon applies the `addRules` suggestions when present, else an exact-command rule to `localSettings`.
- `AskUserQuestion` can be answered from a `PreToolUse` hook via `updatedInput.answers`: an object keyed by the **question text**; value is a string label for single-select, an array of labels for `multiSelect`. The hook must not alter the shown fields (`questions`). Not available in `-p` mode (tool is absent there), so it is only exercised in interactive sessions.
- `Stop` stdin carries **`last_assistant_message`** (no transcript parsing needed), `stop_hook_active`, and **`background_tasks`** (running subagents). Beckon does not show "Finished" while `background_tasks` is non-empty. `{"decision":"block","reason":…}` is used to continue with the user's reply.
- `SubagentStart/Stop` carry `agent_id` and `agent_type`.
- Hooks hot-reload: the app's Install button took effect without restarting any session.
- Shell commands considered safe by Claude (e.g. `echo`) never reach `PermissionRequest`.
- **Only-when-away rule** (new, from testing): Beckon stays silent when the app that owns the asking session is frontmost, and hands a held item back to Claude the moment the user switches to that app. Otherwise Beckon would hold Claude's native prompt hostage while the user is sitting right there.
- Shim protocol gotcha: the shim must not half-close its socket after sending; the app treats EOF as "hook process died" and drops the card (used for Ctrl-C / killed sessions).
- Build gotcha: with Command Line Tools only, SwiftUI's `@State` on the macOS 26/27 SDK needs Xcode's macro plugin; building against the bundled 15.x SDK works for a 14.0 target.
- **Messaging socket wire format** (from Claude Code's own debug log, verified live 2026-10-02): the session listens on `/tmp/cc-socks/<pid>.sock` (`CLAUDE_CODE_MESSAGING_SOCKET`). Newline-delimited JSON: optional `{"type":"auth","token":"<CLAUDE_CODE_MESSAGING_TOKEN>"}` then `{"type":"user","message":{"role":"user","content":"…"}}`. No ack is sent. An idle interactive session picks the message up immediately, framed as a cross-session peer message, and answers. This replaced the Stop-hook hold: Beckon never delays Claude's turn end any more and the "Finished" card has no timer.
