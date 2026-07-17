# B7 — Timeline & home diagnostic · ledger

Branch: `bgap/b7-timeline` · Worktree: `/Users/thomaskgould/dev/bgap-b7`
DB: `caserepo_bgap_b7` · Interpreter: `/Users/thomaskgould/dev/Case-Repo-App-Experience/.venv/bin/python`

## Bootstrap
- DB created; schema + migrations 002–021 applied; `.env` DATABASE_URL → caserepo_bgap_b7 (gitignored, verified).
- Seeded a/b/c@yale.edu + Dev Dummy Case via scripts/seed_caseroom_dev.py.
- **Baseline: 418 passed** (green) — evidence: `DATABASE_URL=…/caserepo_bgap_b7 $PY -m pytest tests/ -q` → `418 passed, 422 warnings in 5.36s`.
- Finish line = 418 + N new tests.

## Plan
- Written: docs/superpowers/plans/2026-07-17-bgap-b7-plan.md (8 tasks). Migrations 026/027 applied to DB (idempotent, re-applied twice). Deviations DV-B7-1..5 recorded in plan.

## Plan review
- Opus reviewer: VERDICT CHANGES REQUIRED → C1 (Task3/Task4 fixtures seeded only 3 of 5 generic-template dims → insight/synthesis default to 0.0 and steal "weakest" from quant). Fixed: seed all 5 dims (mirror test_dashboard). Also applied M1 (relative snooze date) + M2 (mutating-route auth test). Baseline (M3) already verified = 418.

## Tasks
(executing task-by-task)
