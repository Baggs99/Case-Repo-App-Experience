# B7 Task 1 report — Migration 026 (firms + firm_deadlines) + firms repo

**Status:** DONE_WITH_CONCERNS
**Commit SHA:** `c0bfab5f5afcf2ac6b1ba106aa5793887d7cdea9`
**Branch:** bgap/b7-timeline (worktree /Users/thomaskgould/dev/bgap-b7)
**Test counts:** 4 failed → 4 passed. Full suite: 418 → **422 passed**, 0 regressions.

## Files committed (exactly the three named in the task)
- `db/migrations/026_firms_and_deadlines.sql`
- `webapp/repositories/firms.py`
- `tests/test_b7_firms.py`

No `.env` or other files staged. Working tree clean after commit.

## Commands + key output

### Step 2 — apply migration 026 twice (idempotency proof)
```
=== FIRST APPLY ===
CREATE TABLE / CREATE TABLE / CREATE INDEX
INSERT 0 12
INSERT 0 12
=== SECOND APPLY ===
NOTICE: relation "firms" already exists, skipping        -> CREATE TABLE
NOTICE: relation "firm_deadlines" already exists, skipping -> CREATE TABLE
NOTICE: relation "idx_firm_deadlines_firm" already exists, skipping -> CREATE INDEX
INSERT 0 0
INSERT 0 0
=== COUNTS ===
firms          = 12
firm_deadlines = 12
```
Second apply inserts 0 rows and skips DDL — idempotent. Counts stable at 12/12.

### Step 4 — failing test (RED), stated reason
`DATABASE_URL=… $PY -m pytest tests/test_b7_firms.py -q`
```
ImportError: cannot import name 'firms' from 'webapp.repositories'
4 failed in 0.17s
```
Plan predicted `ModuleNotFoundError: No module named 'webapp.repositories.firms'`.
Actual is the equivalent `ImportError: cannot import name 'firms'` — `webapp.repositories`
is a package (has `__init__.py`), so Python raises the import-name form. Same root
cause: the `firms` module does not exist yet.

RED was re-confirmed against the FINAL test harness (after the deviation below) by
temporarily moving `firms.py` aside: still 4 failed with ImportError (module missing),
not a pool error — proving the test genuinely exercises the new repo.

### Step 6 — passing test (GREEN)
`DATABASE_URL=… $PY -m pytest tests/test_b7_firms.py -q`
```
4 passed, 6 warnings in 0.47s
```

### Full suite (no regressions)
`DATABASE_URL=… $PY -m pytest tests/ -q`
```
422 passed, 422 warnings in 5.73s
```
Baseline was 418; +4 new B7 firms tests = 422.

## Deviation from the plan's verbatim code (minimal, required)

**What:** `tests/test_b7_firms.py` — added `_HTTPX` to the imports, a
`@unittest.skipUnless(_HTTPX, …)` decorator, and a `setUpClass`/`tearDownClass`
that enters a `TestClient(app)` context manager. The four test methods are
byte-for-byte the plan's.

**Why:** the repo functions go through `webapp.db.get_pool()`, which raises
`RuntimeError: Connection pool not initialized` until app startup calls
`init_pool()`. The plan's Task 1 test as written creates no `TestClient`, so the
process-global pool is never initialized — the test failed with that RuntimeError
in isolation AND in the full suite (`test_b7_firms.py` sorts alphabetically before
every test that spins up a `TestClient`, so nothing initializes the pool first).
Entering a `TestClient(app)` context fires the FastAPI lifespan → `init_pool()`.

This is the repo's established idiom (see `tests/test_dashboard.py` setUpClass:
`cls._ctx = TestClient(app); cls._ctx.__enter__()`) and is exactly what the plan's
own **File Structure** section (line 80) mandates for all new tests:
"…`from tests.test_ws_integration import _DB_URL, _HTTPX, _READY`, `@skipUnless(_READY,…)`
+ `@skipUnless(_HTTPX,…)`, `TestClient(app)` as a context manager…". The Task 1 code
snippet simply omitted that scaffolding; the fix aligns the test with the plan's
documented harness rather than inventing a new pattern.

## Concerns / flags for downstream

1. **Downstream tasks 2–4 have the same latent defect.** Their test snippets
   (`test_b7_user_firms.py`, `test_b7_readiness.py`, `test_b7_diagnostic.py`)
   call pool-backed repo functions (e.g. `firms_repo.list_firms()`, repo inserts)
   in `setUpClass` without entering a `TestClient(app)` context. They will hit the
   same `RuntimeError: Connection pool not initialized` when run before any
   TestClient-creating test. Each needs the same minimal `TestClient(app)` context
   (or a direct `init_pool(_DB_URL)`) added to its `setUpClass`. Recommend applying
   the identical scaffolding as this task.

2. **Seed dates are estimates (plan-level, not introduced here).** All 12
   `firm_deadlines` rows are `is_estimate = TRUE` curated 2026–27 US full-time dates
   with no authoritative source (per the brief: no web search). Thomas must replace
   them with real cycle dates before launch. Roland Berger's `2026-07-02` is an
   intentional PASSED-deadline fixture for the post-deadline prompt tests.

## DEFERRED
None.
