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

## Plan
- Plan written + committed `e554705`: `docs/superpowers/plans/2026-07-17-bgap-b6-plan.md`.
- 6 tasks: (1) 030 connections mig+repo, (2) connections router, (3) 031 groups mig+repo, (4) 033 leaderboards mig+repo (scoping CTEs), (5) groups router, (6) leaderboards router+no-count audit.
- Migration plan: 030 connections; 031 groups+group_members+school_leaders+groups.invite_code+schools.campus_city; 033 feedback finalized index. 032 vacant.
- Plan-review round 1 (Opus): REQUEST_CHANGES — 2 CRITICAL, 1 IMPORTANT, 7 MINOR.
  - C1: repo tests never init db pool → added TestClient(app) bootstrap + `@skipUnless(_HTTPX)` to Tasks 1/3/4 repo test classes.
  - C2: `join_by_code` read role on a 2nd connection (uncommitted INSERT invisible) → read role on same cursor.
  - I1: `transfer_admin` to self orphaned group → repo no-op on from==to + router 400 + tests.
  - M1: activity points window finalized sessions to 30 d (matches brief + design "this week").
  - M2: all percentiles over one population (30-day-active users) for surface consistency.
  - M3: leaderboard fixture looks up case id dynamically (no hardcoded id=1).
  - M4: shared `_assert_no_counts` (defined in connections API test) applied to group + connections payloads too.
  - M6: doc key `school:{id}` → `school_id`. M7: tie-semantics comment.
  - M5 (extra cross-origin asserts) consciously deferred — uniform `_MUTATING`, one 403 test per router already.
  - Reviewer pre-declared APPROVE-ready once C1/C2/I1 fixed; fixes applied verbatim → no Critical/Important remain.

## Tasks
(executing task-by-task; fresh Opus implementer + Opus task-reviewer each)

- Task 1: complete (commits 65bbb8b..162e27f, review SPEC+CODE PASS). Connections migration 030 + repo. 7/7 tests green, migration idempotent.
  - Deferred MINORs (final-review triage): (a) theoretical opposite-direction request() race under READ COMMITTED → two pending rows, non-corrupting, matches plan; (b) ORDER BY not covered by a multi-element assertion.
