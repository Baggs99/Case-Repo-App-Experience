# B2 — Guest Interviewer · Progress Ledger

Branch: `bgap/b2-guest` · Worktree: `/Users/thomaskgould/dev/bgap-b2` · DB: `caserepo_bgap_b2`
Interpreter (`$PY`): `/Users/thomaskgould/dev/Case-Repo-App-Experience/.venv/bin/python`

## Baseline
- 2026-07-17 · commit `edce22c` · DB created, schema + migrations 0*.sql applied (idempotent), `.env` → `caserepo_bgap_b2`, seeded a/b/c@yale.edu via `scripts/seed_caseroom_dev.py`.
- Baseline suite: **418 passed, 0 failed** (175 skipped before seeding → 0 skips of seed-gated tests after). Finish line = 418 + N.
- Command: `DATABASE_URL=postgresql://localhost/caserepo_bgap_b2 $PY -m pytest tests/ -q` → `418 passed`.

## Plan
- Plan written: `docs/superpowers/plans/2026-07-17-bgap-b2-plan.md` (5 tasks, TDD, no placeholders). Commit `8e5f11e`.
- Opus plan-review: PLAN NEEDS FIXES — 1 Critical (C-1: T5 double-upgrade returns 403 via require_guest, not 409 — fixed the assertion; did NOT weaken the guard), 3 Minor (M-1 WS note added; M-2 pair/claim test disambiguated by class; M-3 session-id rotation on upgrade = deferred, low risk, brief doesn't require). All other areas verified sound against live codebase.

## Tasks
- Task 1: pending (migration 025 + User.is_guest plumbing)
- Task 2: pending (guest CRUD + require_guest)
- Task 3: pending (mint guests on claim; N-1 fix)
- Task 4: pending (require_session_participant + guest-reject + is_guest payload)
- Task 5: pending (upgrade endpoint)
