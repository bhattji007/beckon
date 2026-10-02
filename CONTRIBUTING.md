# Contributing to Beckon

Thanks for helping. Beckon is small on purpose: a C shim, ~2,000 lines of Swift, no dependencies. Keep it that way.

## Ground rules that protect users

1. **Never make Claude Code worse.** If Beckon is not running, crashes, or sees a payload it does not understand, the hook must return nothing so Claude's own prompt appears. Any change to `beckon-hook/main.c` or `Store.handle` must keep this property. `app/tests/smoke.sh` checks it; run it.
2. **No auto-approval.** Beckon only ever returns what the user pressed. Rules written by "Always" must be the narrowest useful rule and must be logged.
3. **No network** except the opt-in update check. No analytics, no telemetry.
4. **Mouse works unfocused.** Cards appear without stealing keyboard focus; every action must be clickable before ⌥Space is pressed.

## Dev setup

```sh
git clone https://github.com/bhattji007/beckon && cd beckon
cd app && ./build.sh --run          # builds build/Beckon.app with swiftc + clang and launches it
BECKON_ARCHS=arm64 ./build.sh --run # faster single-arch dev build
```

Requirements: macOS 14+, Xcode Command Line Tools (`xcode-select --install`). No Xcode project, no SwiftPM. The build uses the 15.x SDK bundled with CLT because the 26/27 SDKs need Xcode's SwiftUI macro plugin.

Useful while developing:
- Launch with `BECKON_SNAPSHOT_DIR=/some/dir open build/Beckon.app` to get a PNG of the overlay on every relayout (handy because screen recording permission is a pain from a terminal).
- Fire fake hooks at the running app: `echo '{"hook_event_name":"PermissionRequest","session_id":"dev","cwd":"'$PWD'","tool_name":"Bash","tool_input":{"command":"npm test"},"permission_suggestions":[]}' | ~/.beckon/bin/beckon-hook`
- `app/tests/smoke.sh` — end-to-end checks against the running app.
- The only-when-away rule hides cards when the asking terminal is frontmost; turn on "Also show when the terminal is in front" in Settings while testing from your own terminal.
- To watch the real messaging-socket transport: `claude` in one terminal, then send `{"type":"user","message":{"role":"user","content":"hi"}}` to `/tmp/cc-socks/<pid>.sock`.

## Where things live

| Area | File |
|---|---|
| Hook shim (C) | `app/Sources/beckon-hook/main.c` |
| Socket server | `app/Sources/Beckon/SocketServer.swift` |
| Sessions, queue, decisions, away rule | `app/Sources/Beckon/Store.swift` |
| Data model, host detection, prefs, log | `app/Sources/Beckon/Models.swift` |
| Overlay window, hotkey routing, focus restore | `app/Sources/Beckon/OverlayController.swift` |
| Cards (SwiftUI) | `app/Sources/Beckon/ToastStackView.swift` — see `app/DESIGN-BRIEF.md` before redesigning |
| Follow-up replies | `app/Sources/Beckon/MessagingClient.swift` |
| settings.json install/uninstall | `app/Sources/Beckon/Installer.swift` |
| Menu bar, onboarding | `app/Sources/Beckon/StatusBar.swift` |
| Settings window, diagnostics, uninstaller | `app/Sources/Beckon/SettingsWindow.swift` |
| Update notifier | `app/Sources/Beckon/UpdateChecker.swift` |
| Architecture and verified Claude Code facts | `SPEC.md` (§3, §13) |
| Release pipeline | `release/`, `.github/workflows/release.yml`, `DISTRIBUTION.md` |

## Making a change

- Open an issue first for anything user-visible; small fixes can go straight to a PR.
- One concern per PR. Describe what the user sees before and after; a snapshot PNG from `BECKON_SNAPSHOT_DIR` is worth a lot.
- Run `app/tests/smoke.sh` and, if you touched the shim or `Store.handle`, the manual passthrough check: quit Beckon, run a `claude` command that needs permission, confirm the normal prompt appears.
- Code style: Swift 5 language mode, no new dependencies, no force-unwraps on data from hooks. Keep functions short enough to read in one screen.
- Claude Code internals we rely on (hook payload fields, `updatedInput.answers`, the messaging socket protocol) are documented in `SPEC.md §13`. If you discover a change in a new Claude Code version, update that section in the same PR.

## Good first issues

Look for the `good first issue` label. Typical ones: a new terminal in `Host.detect`, a tab-level "take me to Claude" adapter for a specific terminal, a design polish from `app/DESIGN-BRIEF.md`, or a test case in `smoke.sh`.

## Release

Maintainers tag `vX.Y.Z` (matching `app/Info.plist`); the workflow builds a universal app, signs and notarizes when secrets are present, and attaches the DMG/zip/appcast to the GitHub release. See `DISTRIBUTION.md`.

By contributing you agree your contributions are licensed under the MIT licence in `LICENSE`.
