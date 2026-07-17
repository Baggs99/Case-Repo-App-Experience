# B5 Identity/Profile/Onboarding — Execution Ledger

Branch: bgap/b5-identity · Worktree: /Users/thomaskgould/dev/bgap-b5
DB: caserepo_bgap_b5 · PY: /Users/thomaskgould/dev/Case-Repo-App-Experience/.venv/bin/python

## Baseline
- Env bootstrapped: DB caserepo_bgap_b5 created, schema + migrations 002-018 loaded, .env copied + DATABASE_URL repointed, dev users a/b/c@yale.edu + dummy case seeded.
- Baseline suite (seeded): 360 passed, 0 skipped, 0 failed. Finish line = 360 + new tests.
  (Before seed: 241 passed / 119 skipped — all skips gated on the dev seed, now applied.)

## Tasks
(pending plan)

## Plan
- Plan written + committed (5040c4e), reviewed by fresh Opus reviewer (round 1: REQUEST_CHANGES — 1 CRITICAL email_verified gate, 2 IMPORTANT), fixed (1e94ae9), re-reviewed round 2: APPROVE.

## Execution ledger
- BASE for Task 1 = 1e94ae9
- Task 1: complete (commits 451913d..83f7da6, review APPROVE). MINORs (ledger): FK guard matches conname globally not scoped to users.conrelid (implausible collision); test doesn't assert the sub unique indexes / FK exist.
- BASE for Task 2 = 83f7da6
