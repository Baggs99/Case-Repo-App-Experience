# B7 Task 3 — readiness.py (OD-B7-1 swap-point + reweight) — REPORT

**Status:** COMPLETE
**Branch:** bgap/b7-timeline (worktree /Users/thomaskgould/dev/bgap-b7)
**Commit SHA:** a734e3802f537f85b42f4cde433ef1fecd9c8fc0
**Message:** `Add readiness swap-point (OD-B7-1 stand-in) and reweight payload`

## Files committed (only these two — no .env)
- `webapp/readiness.py` (79 lines, incl. 4-line Purpose/Inputs/Outputs/Run header docblock)
- `tests/test_b7_readiness.py` (136 lines)

## TDD sequence (evidence)

### RED — test written first, module missing
Command:
`DATABASE_URL=postgresql://localhost/caserepo_bgap_b7 $PY -m pytest tests/test_b7_readiness.py -q`
Result: **4 failed** — `ImportError` (no module `webapp.readiness`), as expected:
```
FAILED tests/test_b7_readiness.py::TestReadiness::test_reweight_payload_shape
FAILED tests/test_b7_readiness.py::TestReadiness::test_signal_needs_work_focus_quant
FAILED tests/test_b7_readiness.py::TestReadiness::test_signal_no_data_is_needs_work
FAILED tests/test_b7_readiness.py::TestReadiness::test_suggested_drill_type_mapping
4 failed, 6 warnings in 0.67s
```

### GREEN — module written, test passes
Command:
`DATABASE_URL=postgresql://localhost/caserepo_bgap_b7 $PY -m pytest tests/test_b7_readiness.py -q -p no:warnings`
Result: **4 passed in 0.53s**

### No regressions — full suite
Command:
`DATABASE_URL=postgresql://localhost/caserepo_bgap_b7 $PY -m pytest tests/ -q -p no:warnings`
Result: **434 passed in 5.89s**
(Baseline 418 + Task 1 firms 4 + Task 2 user_firms 8 + Task 3 readiness 4 = 434.)

## Fixture correctness (per instructions)
The committed test's `_SESSIONS` fixture seeds ALL FIVE generic-template
dimensions (structure, quant, insight, communication, synthesis) with points
that make **quant strictly weakest (1.0/5)**. Verified: `focus_dimension ==
'quant'` and `label == 'needs_work'` in the passing run — no dimension dropped,
no assertions altered.

## Mandatory pool-init scaffolding (applied)
Mirrors the committed `tests/test_b7_firms.py` / `tests/test_b7_user_firms.py`:
- `from tests.test_ws_integration import _DB_URL, _HTTPX, _READY`
- added `@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")` under `_READY`
- `setUpClass`: `cls._ctx = TestClient(app); cls._ctx.__enter__()` entered FIRST,
  before the pool-backed `get_or_create_room` / `get_default_rubric_template_id`
  and fixture inserts
- `tearDownClass`: `cls._ctx.__exit__(None, None, None)` AFTER the psycopg
  practice_sessions/cases cleanup

## Contract compliance
- Parameterized SQL only (named `%(...)s` placeholders in `_recent_case_count`).
- 4-line header docblock present on `webapp/readiness.py`.
- No placeholders/TODOs. Repo style matched (plan module used verbatim).
- Signatures verified against live repo before writing:
  `dashboard.dimension_averages(user_id, window=TREND_WINDOW)` returns ascending
  /5 rows; `dashboard.recommendations(user_id, exclude_case_ids=[], limit=5)`
  items carry `case_id` (dashboard.py:274).

## Deviations
None. Plan module code used verbatim; test uses only the four mandated
pool-init modifications plus the pre-approved 5-dimension `_SESSIONS` fixture.
