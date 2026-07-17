# B6 Community — Phase Ledger

Branch: `bgap/b6-community` · Worktree: `/Users/thomaskgould/dev/bgap-b6` · DB: `caserepo_bgap_b6`
Migration numbers: 030 (connections), 031 (groups+members), 033 (leaderboard indexes). 032 VACANT (do not use).

## Bootstrap
- DB `caserepo_bgap_b6` created; schema + migrations 006–027 applied clean.
- `.env` copied from main checkout, `DATABASE_URL=postgresql://localhost/caserepo_bgap_b6`, gitignored (verified).
- Seeded a/b/c@yale.edu + dummy case via `scripts/seed_caseroom_dev.py`.
- **Baseline: 512 passed, 0 failed** (`.superpowers/sdd/b6/baseline.log`). Finish line = 512 + new B6 tests.

## Design deltas binding this phase
- NO FORUM ANYWHERE — no forum_threads/forum_posts, no forum router.
- NO POPULATION COUNTS EVER — percentiles only; literal ranks+points ONLY inside a joined group; school-vs-school = avg member percentile + campus city.
- Guests (users.is_guest) — column does NOT exist on this branch (B2 unmerged). Code against current schema; document the B2 seam.
- swap-invite-pending decoration — B3 swap does not exist yet; design the field nullable and document the seam.

## Tasks
(pending plan)
