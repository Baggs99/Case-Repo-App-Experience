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
- Task 4: complete (commits cddd471..80ce68a, review NEEDS-FIXES → CRITICAL fixed → re-review MINOR-ONLY). Session scoping: require_session_participant on 19 session endpoints; guest-reject in require_auth_api; is_guest in session payload.
  - Review CRITICAL (live-proven): guests could browse/download the ENTIRE case library — those endpoints use `require_auth` (not require_auth_api), which doesn't reject guests. Nuance: the guest console legitimately loads its OWN case PDF via /api/cases/{id}/open-pdf → /files/cases/{id}. FIXED (80ce68a) case-scoped: new `require_case_access` (guest allowed only for a case it has a session on) on open-pdf + /files/cases/{id}; new `require_auth_no_guest` (guest 403, real/anon unchanged) on all other library/case/search/pages/rooms/change-password endpoints. `/session/{id}` console page stays require_auth. Re-review CONFIRMED CLOSED (adversarial re-probe: guest 403 on full library, own-case PDF still reachable, real/anon unchanged).
  - Suite: 444 passed (436 + 8: 6 scoping + 2 library-scope tests).
  - MINOR (defer to final-review fix pass): 9 dead imports — `require_auth` unused in exhibits/files/pages/search/rooms/auth.py; `require_auth_api` unused in practice_exhibits/feedback/recordings.py. Plus Task 2's inherited datetime.utcnow() in a test.
- Task 5: pending (upgrade endpoint)
