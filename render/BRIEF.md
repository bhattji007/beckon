# Mockup video brief (shared by all drafts)

Product: **Beckon** — a macOS menu-bar app. When any Claude Code session (terminal, VS Code/JetBrains extension, Claude Desktop) needs the human — permission prompt, multiple-choice question, "I'm done, what next?" — Beckon shows a small overlay ON TOP of whatever fullscreen app the user is in. The user answers in the overlay, the overlay disappears, focus returns to their work. Multiple sessions / agents = multiple events, possibly at once. No focus stealing by default: the overlay appears without taking keyboard focus; the user opts in with a global hotkey (⌥Space) or a click; Esc hands focus straight back.

## Shared story (every draft shows exactly this sequence, so the UX can be compared)
Two Claude Code sessions are running in the background:
- `tm-reco-app` — color indigo (#6366f1) — running in Ghostty/terminal, main agent + 1 subagent ("tests")
- `portfolio` — color emerald (#10b981) — running in the VS Code extension

Beats (approximate; adjust timing so pacing feels natural, total 38–48 s):
0. 0.0–2.2 s  Title card via H.titleCard: kicker "BECKON · DRAFT N", title = concept name, sub = one sentence.
1. Working in the fullscreen app (pick bg: 'figma' | 'docs' | 'browser' | 'video'). Caption: "You're in <app>, fullscreen. Two Claude Code sessions run in the background."
2. EVENT A — permission request from tm-reco-app: Claude wants to run `npm test -- --coverage` (tool: Bash). Overlay appears WITHOUT stealing focus (show the cursor still in the app / app caret still blinking). Caption: "Claude needs permission. The overlay appears — your app keeps focus."
3. User presses ⌥Space (show a small key hint) or clicks the overlay → it becomes active. Picks **Allow** (options: Allow · Allow always for this project · Deny). Overlay dismisses. Caption: "Answer inline. Esc or Enter returns focus to your app."
4. EVENT B — AskUserQuestion from portfolio: header "Deploy target", question "Where should I deploy the preview?", options: "Cloudflare Pages (recommended)", "Vercel", "Skip deploy". User picks Cloudflare Pages. Show that this came from a different session (emerald, VS Code glyph).
5. EVENT C — "Finished" from tm-reco-app: summary "Fixed 3 failing tests · coverage 71% → 84% · 4 files changed". The overlay offers a text field "Reply to tm-reco-app…". User types: "great — also update the README test section" (use H.typed), presses Enter. Show a tiny confirmation ("Sent → tm-reco-app") then dismiss. Caption: "Type a follow-up without switching windows."
6. MULTI — two events land within a second: tm-reco-app/tests subagent needs permission (`rm -rf .coverage`) AND portfolio finished. Show how THIS concept handles several at once (stack / queue counter / rail chips / island swipe / grid). Caption explains it. User resolves one, the other stays.
7. Quiet again: the app is undisturbed, cursor back at work. Caption: "Back to work. Nothing to switch to."
8. End card (last ~3.5 s) via H.titleCard: title = concept name, sub = 3 short strengths separated by " · ", note = "Mockup — not a real app yet".

## Visual bar
- Must look like a real, polished macOS app: SF system font, 12–16 px radii, glass (rgba dark or light + backdrop-filter blur), 1px hairline borders at 10–14% white/black, soft layered shadows, 13 px body / 11 px meta text. Session color appears as a dot or stripe. Show the source host with a short tag: "Ghostty" / "VS Code" / "Claude Desktop".
- Legible at 1440×900 (the video is rendered at 2× so it's crisp). No text clipping, no overflow.
- Motion: springy enter (H.ease.back or spring, 350–500 ms), quick fade-out (200 ms). Cursor moves via H.cursor with eased paths; clicks ripple.
- Keep the fake background app mostly static; a blinking caret or subtle progress is enough to show it's "live".

## Technical contract (non-negotiable)
- File: `drafts/0N-slug.html`. Load `../render/harness.css` and `../render/harness.js`. Define `window.DRAFT = { title, duration, bg, markup, setup(H), render(t,H) }`.
- `render(t,H)` must set the DOM purely as a function of `t` (ms). The renderer seeks to arbitrary t and screenshots. **Therefore: NO CSS `transition`, NO CSS `animation`, no setTimeout/requestAnimationFrame-driven state.** Compute every opacity/transform from t with `H.prog`, `H.window`, `H.lerp`, `H.typed`, `H.caret`.
- Use `H.caption(t,[{from,to,text}])`, `H.titleCard(t,{from,to,kicker,title,sub,note})`, `H.cursor(t,path,clicks)`.
- Elements you animate should exist in `markup` (or be created in setup) and be toggled via style/classes in render.
- Render: `node render/render.mjs drafts/0N-slug.html` → writes `videos/0N-slug.mp4` and `render/0N-slug-sheet.jpg` (12-frame contact sheet). Look at the sheet (Read tool on the jpg) and fix anything clipped, misaligned, or illegible. For a close look at a specific moment, open `render/frames/0N-slug/NNNNN.jpg` (frame = t_ms/1000*30). Iterate at least once. Rendering takes ~1–2 min.
- Preview in a browser: open the html with `#play` appended to loop it live.
