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
- Task 1: complete (commits a982f78..18361a3, review CLEAN) — migration 025 + User.is_guest; suite 422 passed.
- Task 2: complete (commits 18361a3..bc4ffff, review CLEAN) — webapp/auth/guest.py (mint_guest_user, upgrade_guest race-safe, require_guest); suite 428 passed. Minor: test uses inherited datetime.utcnow() deprecation (repo-wide norm, no fix).
- Task 3: complete (commits 169fa5d..cda02a2, review MINOR-ONLY → fixed). Mint scoped guests on unauthenticated proposals-claim + pair-claim; NULL-email invite guard; N-1 claim_token null.
  - Review Important finding: orphan guest rows on FAILED claims (mint-before-validate) = unauthenticated scriptable row-creation vector. FIXED (cda02a2): `discard_minted_guest(request)` reaps the just-minted guest+session at every claim failure path (bad token, empty pair body, TransitionError). Covering tests added (no orphan on failed claim). Minor docblock Run: line updated.
  - Deviation DV-B2-1: N-1 (null claim_token on claim) changes a pre-existing B1 test — `test_b1_proposals_open.py::test_double_claim_409` → `test_double_claim_404_dead_token` (a re-claim of a now-dead token is 404 "No such claim link", not 409). Reviewer APPROVED as the only correct reconciliation. Plus the 3 planned B1 test updates (unauth claim/pair-claim now 200, not 401).
  - Suite: 436 passed (428 + 8: 6 claim tests + 2 orphan-guard tests).
- Task 4: pending (require_session_participant + guest-reject + is_guest payload)
- Task 5: pending (upgrade endpoint)
