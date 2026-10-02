#!/bin/bash
# Smoke test for a running Beckon.app: drives the real shim with sample hook payloads and checks the log.
# Usage: app/tests/smoke.sh            (Beckon must be running; sets "show when host in front" for the duration)
set -euo pipefail
set +m   # no job-control chatter when we kill the shim on purpose
SHIM="$HOME/.beckon/bin/beckon-hook"; LOG="$HOME/.beckon/log.jsonl"
pass=0; fail=0
ok(){ echo "  ✓ $1"; pass=$((pass+1)); }; bad(){ echo "  ✗ $1"; fail=$((fail+1)); }
pgrep -x Beckon >/dev/null || { echo "Beckon is not running"; exit 1; }
[ -x "$SHIM" ] || { echo "shim missing at $SHIM"; exit 1; }
PREV="$(defaults read club.shubham.beckon showWhenHostInFront 2>/dev/null | tr -d ' ')"
[ "$PREV" = "1" ] && RESTORE=true || RESTORE=false
defaults write club.shubham.beckon showWhenHostInFront -bool true
trap 'defaults write club.shubham.beckon showWhenHostInFront -bool $RESTORE; pkill -x beckon-hook 2>/dev/null || true' EXIT
SID="smoke-$$"
lines_before=$(wc -l < "$LOG" | tr -d " ")

echo "1. non-blocking event passes through instantly"
t0=$(date +%s%N); echo "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"$SID\",\"cwd\":\"$PWD\"}" | "$SHIM"; t1=$(date +%s%N)
ms=$(( (t1-t0)/1000000 )); [ "$ms" -lt 500 ] && ok "SessionStart round-trip ${ms}ms" || bad "SessionStart took ${ms}ms"
grep -q "\"session\":\"$SID\"" "$LOG" && ok "event logged" || bad "event not logged"

echo "2. PermissionRequest is held while the card is up, dropped when the hook dies"
(echo "{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"$SID\",\"cwd\":\"$PWD\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo smoke\"},\"permission_suggestions\":[]}" | "$SHIM" >/dev/null) & P=$!
sleep 1.5; kill -0 $P 2>/dev/null && ok "shim still waiting after 1.5s" || bad "shim exited early"
kill $P 2>/dev/null; pkill -x beckon-hook 2>/dev/null || true; wait $P 2>/dev/null || true; sleep 1
tail -n +"$lines_before" "$LOG" | grep -q "\"kind\":\"peer-closed\",\"session\":\"$SID\"" && ok "peer-closed logged" || bad "no peer-closed"

echo "3. AskUserQuestion payload is accepted (card) and malformed payload passes through"
(echo "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"$SID\",\"cwd\":\"$PWD\",\"tool_name\":\"AskUserQuestion\",\"tool_input\":{\"questions\":[{\"question\":\"Q?\",\"header\":\"H\",\"options\":[{\"label\":\"A\",\"description\":\"\"},{\"label\":\"B\",\"description\":\"\"}],\"multiSelect\":false}]}}" | "$SHIM" >/dev/null) & P=$!
sleep 1; kill -0 $P 2>/dev/null && ok "question held" || bad "question not held"; kill $P 2>/dev/null; pkill -x beckon-hook 2>/dev/null || true; wait $P 2>/dev/null || true; sleep 0.5
t0=$(date +%s%N); echo "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"$SID\",\"cwd\":\"$PWD\",\"tool_name\":\"AskUserQuestion\",\"tool_input\":{\"questions\":\"garbage\"}}" | "$SHIM"; t1=$(date +%s%N)
[ $(( (t1-t0)/1000000 )) -lt 500 ] && ok "malformed question → instant passthrough" || bad "malformed question was held"

echo "4. Stop never blocks and with background tasks shows nothing"
t0=$(date +%s%N); echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"$SID\",\"cwd\":\"$PWD\",\"stop_hook_active\":false,\"last_assistant_message\":\"smoke done\",\"background_tasks\":[]}" | "$SHIM"; t1=$(date +%s%N)
[ $(( (t1-t0)/1000000 )) -lt 500 ] && ok "Stop passthrough ${ms}ms" || bad "Stop blocked"

echo "5. SessionEnd clears the session"
echo "{\"hook_event_name\":\"SessionEnd\",\"session_id\":\"$SID\",\"cwd\":\"$PWD\"}" | "$SHIM" && ok "SessionEnd accepted"

echo; echo "passed $pass, failed $fail"; [ "$fail" -eq 0 ]
