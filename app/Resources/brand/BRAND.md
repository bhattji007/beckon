# Beckon — brand spec (direction 2b, Smoked glass)

Beckon: free, open-source macOS menu-bar app to answer Claude Code from anywhere.

## Mark
Return-key arrow (⏎), mint, with soft mint glow, on smoked glass. Files: mark-mint.svg, app-icon.svg (1024), menubar-template.svg (monochrome template image, 18pt).
Arrow path (64 viewBox): M46 14 V34 H18 M27 25 L18 34 L27 43 — stroke 6.5, round caps/joins.
Wordmark: "beckon", lowercase, Familjen Grotesk 700, letter-spacing -0.035em.

## Colour
- Mint #3DDC97 — the only accent. Primary action (Allow, ⏎), glyph, waiting states.
- Smoke #0F1114 — base/background.
- Ink #F2EFE8 — text on dark. Secondary text #B5B3AD.
- Deny #E5484D — destructive only.
- Glass fill rgba(28,30,34,.45); secondary buttons rgba(255,255,255,.12).

## Type
- UI + wordmark: Familjen Grotesk (400/600/700)
- Commands/paths: JetBrains Mono 400

## Glass material (overlay card)
background: rgba(28,30,34,.45);
backdrop-filter: blur(24px) saturate(1.6);
border-radius: 16px; padding: 14px;
box-shadow: inset 0 1px 0 rgba(255,255,255,.25), inset 0 0 0 1px rgba(255,255,255,.1), 0 12px 30px rgba(0,0,0,.4);
Buttons: radius 9px, 13px/600. Primary = Mint bg + Smoke text. Secondary = white 12%.
Mint glow: drop-shadow(0 0 10px rgba(61,220,151,.7)).

## Card anatomy
Header row (12px, #B5B3AD): project · terminal/IDE … counter ("1 of 3").
Body: command in JetBrains Mono 13px, or question in Familjen 15px.
Actions: Allow ⏎ · Always · Deny | options as pills | reply field + ⏎.

## Voice
Plain, short. Tagline: "Press return. Get back to work."
