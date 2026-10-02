# Changelog

## 0.9.1 — 2026-10-03

- New overlay design, "Smoked glass": one glass panel with an active item, a Waiting list that expands on hover, and a footer with key hints. Mint return-key brand mark, Familjen Grotesk + JetBrains Mono (bundled, OFL). See `app/DESIGN-BRIEF.md §6` and `app/Resources/brand/BRAND.md`.
- New app icon and menu-bar mark.
- "Always" shows the rule tail inline and the full rule in the footnote; file paths are shown relative to the project.
- Waiting rows can be promoted to active by clicking them.

## 0.9.0 — 2026-10-02 (public beta)

First release. Toast Stack overlay for Claude Code on macOS.

- Permission cards (Allow / Always / Deny) via the `PermissionRequest` hook; "Always" uses Claude's own suggested rules or a narrow exact-command / project-scoped rule.
- Question cards for `AskUserQuestion` (single-select, multi-select, several questions per call).
- "Finished" cards with a reply field that delivers through the session's messaging socket; no hold on Claude's turn.
- Informational cards for idle / waiting notices.
- Only-when-away rule: silent when the asking terminal is frontmost; hands back instantly when you switch to it.
- Non-focus-stealing overlay over fullscreen apps; ⌥Space to focus, ⌥1/2/3, ⏎, ⌥J "take me to Claude", Esc.
- One-click hook install/uninstall with backups; hooks hot-reload.
- Settings window, hotkey recorder, launch at login, notify-only update checker, diagnostics, uninstaller, log rotation.
- Universal binary (arm64 + x86_64), macOS 14+. C shim with 4 s / 590 s timeouts; instant passthrough when Beckon is absent.
