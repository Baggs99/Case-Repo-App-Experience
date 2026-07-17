# B2 — Guest Interviewer · Progress Ledger

Branch: `bgap/b2-guest` · Worktree: `/Users/thomaskgould/dev/bgap-b2` · DB: `caserepo_bgap_b2`
Interpreter (`$PY`): `/Users/thomaskgould/dev/Case-Repo-App-Experience/.venv/bin/python`

## Baseline
- 2026-07-17 · commit `edce22c` · DB created, schema + migrations 0*.sql applied (idempotent), `.env` → `caserepo_bgap_b2`, seeded a/b/c@yale.edu via `scripts/seed_caseroom_dev.py`.
- Baseline suite: **418 passed, 0 failed** (175 skipped before seeding → 0 skips of seed-gated tests after). Finish line = 418 + N.
- Command: `DATABASE_URL=postgresql://localhost/caserepo_bgap_b2 $PY -m pytest tests/ -q` → `418 passed`.

## Tasks
(pending plan)
