# Task 7 — Consolidate all sweeps into the always-on 60-s maintenance loop

**Status:** COMPLETE
**Branch:** bgap/b1-scheduling
**Commit:** 1002191a3b88b9384d30b7e8e44723089d0a0c7e

## What changed

- **Created `webapp/maintenance.py`** — `run_maintenance_pass(settings) -> dict`
  (order: `sweep_expired` → `sweep_missed` → `sweep_stale_sessions` →
  `await notify_starting_soon`; returns counts `expired/missed/aborted/starting_soon`)
  and a **sleep-FIRST** `maintenance_loop(interval_seconds=60)` — `await asyncio.sleep`
  runs BEFORE the pass so a short-lived TestClient lifespan never fires a sweep.
  4-line Purpose/Inputs/Outputs/Run header docblock. CancelledError re-raised;
  all other exceptions logged + swallowed so a bad pass can't kill the loop.
- **`webapp/main.py`** — dropped `from webapp.push.events import push_enabled` and
  `from webapp.push.starting_soon import starting_soon_loop`; added
  `from webapp.maintenance import maintenance_loop`. Lifespan now spawns
  `maintenance_task = asyncio.create_task(maintenance_loop())` UNCONDITIONALLY
  (DD-3), with `cancel()` + awaited-CancelledError teardown before `close_pool()`.
  `push_enabled` was used only inside the removed push-gated block, so the import
  was dropped (verified via grep — no other reference in main.py).
- **`webapp/push/starting_soon.py`** — M-7: header `Run:` line updated to note
  `notify_starting_soon()` now runs each pass of
  `webapp/maintenance.py:maintenance_loop` (was: "starting_soon_loop() spawned
  when push is enabled"). `starting_soon_loop()` itself left in place (unused by
  main now, no test removed).
- **Created `tests/test_b1_maintenance.py`** — exact Task 7 Step 1 code
  (1 IsolatedAsyncioTestCase, 1 async test seeding an expired proposal + a
  missed session, patching `webapp.push.starting_soon.push_to_user`).

## Evidence

### Step 2 — test fails before implementation (webapp.maintenance missing)
```
>       from webapp import maintenance
E       ImportError: cannot import name 'maintenance' from 'webapp' (.../webapp/__init__.py)
tests/test_b1_maintenance.py:55: ImportError
1 failed, 6 warnings in 0.66s
```

### Step 5 — FULL suite green after implementation (DD-3: loop starts on every lifespan)
```
DATABASE_URL=postgresql://localhost/caserepo_bgap_b1 $PY -m pytest tests/ -q
390 passed, 384 warnings in 5.43s
```
389 prior + 1 new = 390. Zero failures. Sleep-first loop confirmed: `test_starting_soon`
and all other short-lifespan tests stayed green — no cross-test sweep interference.

### Step 6 — commit
```
git add webapp/maintenance.py webapp/main.py webapp/push/starting_soon.py tests/test_b1_maintenance.py
git commit -m "Consolidate all sweeps into the always-on 60-s maintenance loop"
1002191  (4 files, +154 / -16)
```
Working tree clean after commit.

## Concerns

None. Clean fail→pass, full suite +1, no regression.
