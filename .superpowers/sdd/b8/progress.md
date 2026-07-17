# B8 — Drills aggregation & gauntlet seams · progress ledger

Branch: bgap/b8-drills-agg · Worktree: /Users/thomaskgould/dev/bgap-b8 · DB: caserepo_bgap_b8
Interpreter ($PY): /Users/thomaskgould/dev/Case-Repo-App-Experience/.venv/bin/python
Run suite: DATABASE_URL=postgresql://localhost/caserepo_bgap_b8 $PY -m pytest tests/ -q  (no `timeout` binary on this mac → run detached)

## Baseline
- Bootstrap DONE — createdb caserepo_bgap_b8, schema.sql + migrations 0*.sql applied clean, .env copied (DATABASE_URL→caserepo_bgap_b8, gitignored), users a/b/c@yale.edu seeded via scripts/seed_caseroom_dev.py.
- Baseline suite: **585 passed, 0 failed** (evidence: pytest tail "585 passed, 630 warnings in 8.69s"). Finish line = 585 + N new.

## Now
- Writing plan: docs/superpowers/plans/2026-07-17-bgap-b8-plan.md

## Done
- (none yet)

## Assumptions
- (recorded as they arise)
