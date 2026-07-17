# Task 2 — Env-tunable expiry settings

**Status:** DONE
**Branch:** bgap/b1-scheduling
**Commit:** ab30892 — "Add env-tunable PROPOSAL_NOW_EXPIRY_MIN / SESSION_MISSED_AFTER_MIN settings"

## Scope
Added two env-tunable settings to `webapp/settings.py`:
- `proposal_now_expiry_min: int` — env `PROPOSAL_NOW_EXPIRY_MIN`, default 120
- `session_missed_after_min: int` — env `SESSION_MISSED_AFTER_MIN`, default 60

Edit was additive: both dataclass fields placed immediately after `turn_token`, both
`load_settings()` args placed immediately after `turn_token=...`, so the frozen-dataclass
field order stays aligned with the `Settings(...)` call. No other fields reformatted.

## TDD evidence

### RED — `tests/test_b1_settings.py` before the change (Step 2)
Command: `DATABASE_URL=postgresql://localhost/caserepo_bgap_b1 $PY -m pytest tests/test_b1_settings.py -q`

```
FF                                                                       [100%]
E       AttributeError: 'Settings' object has no attribute 'proposal_now_expiry_min'
tests/test_b1_settings.py:30: AttributeError
...
E       AttributeError: 'Settings' object has no attribute 'proposal_now_expiry_min'
tests/test_b1_settings.py:38: AttributeError
FAILED tests/test_b1_settings.py::TestExpirySettings::test_defaults
FAILED tests/test_b1_settings.py::TestExpirySettings::test_env_override
2 failed in 0.02s
```

### GREEN — after adding the two fields (Step 4)
Command: `DATABASE_URL=postgresql://localhost/caserepo_bgap_b1 $PY -m pytest tests/test_b1_settings.py -q`

```
..                                                                       [100%]
2 passed in 0.01s
```

### Full-suite regression (Step 5)
Command: `DATABASE_URL=postgresql://localhost/caserepo_bgap_b1 $PY -m pytest tests/ -q`

```
362 passed, 330 warnings in 4.53s
```

Baseline was 360 passed → 360 + 2 = **362 passed, 0 failed**. No regressions.

## Files changed
- `webapp/settings.py` (modified, additive: 2 dataclass fields + 2 load_settings args)
- `tests/test_b1_settings.py` (created)

## Concerns
None. `.env` not touched/committed. Working tree clean after commit.
