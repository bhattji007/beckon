# Security

Beckon sits between Claude Code and the user's decisions, so it is security-relevant by nature.

## What it does and does not do

- Listens on a Unix socket at `~/.beckon/beckon.sock` (mode 0600, same-uid check on every connection). Any process running as you could connect and show a fake card; the reply only goes back to that process, so this is not an escalation.
- Writes permission rules only when the user presses "Always", only the narrowest rule it can (exact command, or project-scoped path), and logs every rule written.
- Sends typed replies to Claude Code's own per-session socket under `/tmp/cc-socks/`; that is the same access any local process already has.
- Makes exactly one kind of network request: the opt-in update check to the URL in `Info.plist`. No analytics.
- Edits `~/.claude/settings.json` only to add or remove its own hook entries, with a backup first.

## Reporting a vulnerability

Please do not open a public issue. Use GitHub's private vulnerability reporting on this repository ("Security" tab → "Report a vulnerability"), or email the maintainer via the address on @bhattji007's GitHub profile. You will get an acknowledgement within a few days. Fixes ship as a patch release with credit if you want it.
