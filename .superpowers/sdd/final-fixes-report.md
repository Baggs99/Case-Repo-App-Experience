# Final-review fixes — evidence report

Branch: `bgap/b1-scheduling` · cwd `/Users/thomaskgould/dev/bgap-b1`
Commit: `56670a3ee3c05129db27b03b722b4cd5c088c4b6`

## Fixes applied

### FIX 1 — webapp/templates/room.html (line 48)
Changed the proposal case-title output only:
`{{ p.case_title }}` → `{{ p.case_title or "a case (interviewer's choice)" }}`
Stops rendering literal "None" for case-less ("interviewer decides") proposals surfaced by inbox()'s LEFT JOIN. Nothing else in the template touched.

### FIX 2 — tests/test_b1_proposals_open.py (class TestCounter)
Added `test_counter_requires_auth()` after `test_one_round_only()` — an explicit unauthenticated-guard test for `POST /api/proposals/{id}/counter`, asserting 401.

### FIX 3 — webapp/routes/proposals.py (accept handler, line 93)
Comment-only change on the `repo.sweep_expired()` line:
old: `# an 8-day-old proposal must expire, not accept`
new: `# A3: an over-window proposal (now-ping >2h, or past its earliest start) must expire, not accept`
Code unchanged.

### FIX 4 — webapp/push/starting_soon.py (dead code removal)
Reference check (`grep -rn "starting_soon_loop" webapp/ tests/`):
```
webapp/push/starting_soon.py:58:async def starting_soon_loop(interval_seconds: int = 60) -> None:
```
Only hit was the def itself → deleted the whole `starting_soon_loop()` function (lines 58-71).

asyncio check (`grep -n "asyncio" webapp/push/starting_soon.py`) before deletion:
```
14:import asyncio
67:        except asyncio.CancelledError:
71:        await asyncio.sleep(interval_seconds)
```
The only remaining asyncio uses (67, 71) were inside the deleted function → removed `import asyncio` (line 14). Post-edit `grep asyncio|starting_soon_loop` → NONE.

Docblock `Run:` line: already read "notify_starting_soon() now runs each pass of the consolidated background loop in webapp/maintenance.py:maintenance_loop (spawned from webapp.main's lifespan); no CLI entrypoint." — it no longer referenced `starting_soon_loop()` and already reflected the requested state, so no change was needed. `notify_starting_soon()` and all else kept intact.

## Test evidence

Targeted: `pytest tests/test_b1_proposals_open.py tests/test_starting_soon.py tests/test_b1_maintenance.py -q`
→ **23 passed, 59 warnings** (includes new test_counter_requires_auth; test_starting_soon.py green — imports notify_starting_soon only).

Full suite: `pytest tests/ -q`
→ **402 passed, 408 warnings in 5.17s** (401 baseline + 1 new test; zero failures).

## Git
Staged only the 4 edited files (explicit paths, not `git add -A`) because two pre-existing untracked review artifacts (`.superpowers/sdd/diffs/final-wholebranch.diff`, `.superpowers/sdd/final-minor-findings.md`) were present and must not be committed.
Commit SHA: `56670a3ee3c05129db27b03b722b4cd5c088c4b6`
