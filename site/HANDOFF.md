# Handoff: build the Beckon website

Context for a fresh Claude Code session started in `~/Developer/claude-overlay` (repo: https://github.com/bhattji007/beckon, public, MIT).

## What Beckon is (use this copy)

Beckon is a free, open-source macOS menu-bar app that lets you answer Claude Code from anywhere on your Mac. When a Claude Code session needs you — a permission prompt, a multiple-choice question, a finished task waiting for a follow-up — a small card appears on top of whatever you are doing, even a fullscreen app. It shows which project is asking and from which terminal or IDE, what Claude wants, and the buttons to answer: Allow, Always, Deny, pick an option, or type a reply. Answer in place; the card disappears; focus returns to your work. Many sessions and subagents become a stack of cards you clear in seconds. One keystroke (⌥J) takes you to the terminal when you do want to go there.

Safe to adopt: one-click hook install into Claude Code's settings (existing hooks preserved, backup kept, one-click removal). If Beckon is not running, Claude Code behaves exactly as before. Never approves anything you did not press. No network except an optional update check. Works with any terminal (Warp, Ghostty, iTerm2, Terminal, kitty, WezTerm), the VS Code and JetBrains extensions, and Claude Desktop. macOS 14+, Apple Silicon and Intel.

## What already exists

- `site/index.html`, `site/style.css` — a first-draft dark landing page (hero, download button → `/latest/Beckon.dmg`, `<video src="./demo.mp4">` placeholder, 3-step how it works, feature strip, FAQ with the Gatekeeper note). Treat it as a starting point, not a constraint.
- `site/appcast.json` (update feed read by the app at `https://beckon.shubham.club/appcast.json`), `site/_redirects` (`/latest/*` → versioned files), `site/_headers`, `site/README.md` (publishing steps).
- Release assets for 0.9.0 (unsigned pre-release): https://github.com/bhattji007/beckon/releases/tag/v0.9.0 — `Beckon-0.9.0.dmg`, `.zip`, `appcast.json`, `SHA256SUMS.txt`. Local copies in `dist/` after `release/release.sh`.
- Brand: app icon `app/Resources/icon/icon-1024.png` (dark charcoal→indigo squircle, white bell, indigo #6366f1 dot); session colour palette indigo #6366f1, emerald #10b981, amber #f59e0b, rose #f43f5e, sky #0ea5e9, violet #8b5cf6. UI is dark glass, SF system font.
- Visual material: six concept videos in `videos/` (`01-toast-stack.mp4` is the shipped design, 43 s, 2880×1800); contact sheets in `render/*-sheet.jpg`; the overlay can be snapshotted from the real app with `BECKON_SNAPSHOT_DIR=/dir open /Applications/Beckon.app` then firing a fake hook (see CONTRIBUTING.md) — use that for real screenshots.
- A video-editor brief for a 45–60 s demo was written earlier; the finished demo should land at `site/demo.mp4` (+ `site/demo-poster.jpg`).
- Product and architecture reference: `README.md`, `app/README.md`, `SPEC.md`, `DISTRIBUTION.md`.

## Hosting

Domain: `beckon.shubham.club` (owner already runs `shubham.club` and `jageshwar.shubham.club` on Cloudflare Pages). Deploy `site/` as a Cloudflare Pages project (git-connected to this repo with build output dir `site`, or `wrangler pages deploy site`). Put release DMGs under `site/releases/` (25 MB/file limit on Pages; DMGs are ~1.5 MB) or link straight to GitHub release assets.

## Must-haves on the page

1. Download button for the latest DMG (and a "or build from source" one-liner: `git clone https://github.com/bhattji007/beckon && cd beckon && ./install.sh`).
2. Gatekeeper note until releases are signed: System Settings → Privacy & Security → Open Anyway.
3. The demo video and at least two real overlay screenshots.
4. How it works in three steps (download → one click "Install hooks" → answer from the overlay) and the safety promises above.
5. FAQ: macOS 14+; which hosts; "what if Beckon isn't running"; privacy; "I'm in auto permission mode and see few cards" (expected — permission cards only appear when Claude asks; use `claude --permission-mode manual`); uninstall.
6. Links: GitHub repo, releases, issues, CONTRIBUTING.
7. Keep `appcast.json` and `_redirects` served at the site root; the app depends on the appcast URL.

## Don't

- Don't change `app/`, `release/`, or the appcast schema (`{"version","url","notes","published"}`).
- Don't promise signing/notarization yet; the Developer ID is pending.
