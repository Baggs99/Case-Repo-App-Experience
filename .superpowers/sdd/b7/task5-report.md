# B7 Task 5 report — timeline_service + timeline router + registration

**Status:** DONE (green)
**Branch:** bgap/b7-timeline (worktree /Users/thomaskgould/dev/bgap-b7)
**Commit:** 9bd3e3727b671e91a2e6f7cc5871fe4228388ae8 (`9bd3e37`)
**Date:** 2026-07-17

## What was built
- `webapp/timeline_service.py` — assembly layer (verbatim from plan). Composes
  firms + user_firms repos + readiness swap-point into `timeline_view`,
  `firm_catalog`, `next_deadline_summary`. No raw SQL — calls repos only.
- `webapp/routes/timeline.py` — `APIRouter(prefix="/api/v1")`, verbatim.
  `_MUTATING = [Depends(require_same_origin)]` on POST /timeline/firms,
  DELETE /timeline/firms/{id}, POST /timeline/firms/{id}/result.
  `require_auth_api` on every endpoint (incl. the two GETs).
- `webapp/main.py` — two ADDITIVE lines only: import
  `from webapp.routes import timeline as timeline_routes` (next to the other
  route imports, after `search`); include `app.include_router(timeline_routes.router)`
  immediately before `app.include_router(api_v1_routes.router)`. No reorder/remove.
- `tests/test_b7_timeline_api.py` — verbatim, TestTimelineApi only (11 tests).
  TestDashboardTimelineKeys (Task 6) intentionally NOT added.

## TDD evidence (RED → GREEN)
Command (both phases):
`DATABASE_URL=postgresql://localhost/caserepo_bgap_b7 $PY -m pytest tests/test_b7_timeline_api.py -q`

- **RED (test written, impl absent):** `10 failed, 1 passed`. The lone pass was
  `test_track_unknown_firm_404` — returned 404 only because the route did not
  exist yet (right result, wrong reason); it passes for the correct reason
  post-impl.
- **GREEN (after service + router + registration):** `11 passed, 33 warnings in 0.71s`.

## Broader guard (router registration didn't break app startup)
`DATABASE_URL=postgresql://localhost/caserepo_bgap_b7 $PY -m pytest tests/test_api_v1_sessions.py tests/test_b7_timeline_api.py -q`
→ **19 passed, 39 warnings in 0.73s** (8 sessions + 11 timeline).

## Security contract (§2) confirmation
- **Parameterized SQL:** service and router build zero SQL strings — all DB
  access is delegated to firms_repo / user_firms_repo (already parameterized).
- **Auth guard:** `require_auth_api` on all 5 endpoints. Verified by
  `test_timeline_requires_auth` (401) and `test_track_requires_auth` (401).
- **CSRF/same-origin:** `_MUTATING` on all 3 state-changing routes.
- **Server-side validation:** bad `outcome` → 400 (`test_bad_outcome_400`);
  unknown firm on track → 404 (`test_track_unknown_firm_404`).
- **IDOR guards (both pass):**
  - `test_result_on_untracked_firm_404` — Bob POSTing a result on a firm only
    Alice tracks gets 404; Alice's row stays `tracking`. PASS.
  - `test_untrack_is_per_user` — Bob DELETE on Alice-tracked firm is a 204
    per-user no-op; Alice still tracks 1 firm. PASS.
- **Auth test:** `test_track_requires_auth` (401 without session cookie). PASS.

## Deviations
None. All four files written verbatim from the plan; the two main.py edits are
strictly additive. Commit carries the plan's exact message (plus the standard
Co-Authored-By trailer per repo git rules). No `.env` staged or committed.

## Deferred
- TestDashboardTimelineKeys class is appended to this same test file in Task 6
  (not part of Task 5, per instructions).
