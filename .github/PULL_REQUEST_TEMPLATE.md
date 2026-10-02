**What this changes** (one concern per PR)

**What the user sees before / after** (snapshot PNG welcome)

**Checks**
- [ ] `app/tests/smoke.sh` passes against the running app
- [ ] If the shim or `Store.handle` changed: quit Beckon, trigger a permission prompt in `claude`, confirm the native prompt appears
- [ ] No new dependencies; no network calls added
- [ ] If this relies on a Claude Code internal, `SPEC.md §13` is updated
