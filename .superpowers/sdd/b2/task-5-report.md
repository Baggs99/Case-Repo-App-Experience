# B2 Task 5 report — Upgrade endpoint (`POST /api/v1/auth/upgrade`)

**Status:** DONE
**Commit:** HEAD of bgap/b2-guest — "Add POST /api/v1/auth/upgrade (guest → real account in place)"
**Branch:** bgap/b2-guest (worktree /Users/thomaskgould/dev/bgap-b2)
**Baseline:** 444 (plan says 440 for this point; extra security-fix tests from Tasks 3-4 landed earlier, so 444 is the real baseline). Finish line = 444 + 6 = 450.

## What changed
- `webapp/routes/guest.py` — NEW. `POST /api/v1/auth/upgrade`, body `{email, password}` (Pydantic `UpgradeBody`, `email` 3–320 / `password` 1–1024). Guarded by `Depends(require_guest)` (401 unauth / 403 real user) and CSRF-guarded by `dependencies=[Depends(require_same_origin)]`. Delegates the in-place conversion to `upgrade_guest(user.id, ...)` and maps its exceptions: `InvalidEmailDomain`→400, `WeakPasswordError`→400, `EmailAlreadyRegistered`→409, `GuestUpgradeConflict`→409. On success returns `200 {upgraded: true, user_id, email}`; the session cookie is untouched and now authenticates the (now-real) user. 4-line header docblock present.
- `webapp/main.py` — MODIFY. Added `from webapp.routes import guest as guest_routes` (with the other route imports) and `app.include_router(guest_routes.router)` (after `proposals_routes`).
- `tests/test_b2_guest_upgrade.py` — NEW, 6 tests: happy-path (guest 403 on `/api/v1/me` before → 200 after upgrade; history FK intact, `interviewer_is_guest` now false); second upgrade rejected **403** as a now-real user (per plan: the 409 GuestUpgradeConflict concurrent-race path is proven at repo level in Task 2, not re-tested here); bad domain → 400; taken email (`a@yale.edu`) → 409; non-guest (real user) → 403; unauthenticated → 401. Module-level `_cleanup_case` helper + dedicated case (source_year 2100) + teardown that also reaps `grad-%@yale.edu` upgraded users for re-runnability.

## Security invariants preserved
- State-changing route carries `require_same_origin` (CSRF).
- Auth guard `require_guest` on the endpoint (401/403 before the handler runs).
- Parameterized SQL only (all DB work is inside the pre-existing `upgrade_guest`, which uses a `WHERE id=%s AND is_guest=TRUE` parameterized UPDATE).
- No placeholders; new module has the 4-line header docblock; repo style matched (mirrors `_MUTATING = [Depends(require_same_origin)]` idiom used elsewhere).

## Evidence

(a) New test — before implementation (Step 2), route not registered:
```
6 failed  (all 404 — route does not exist)
```

After implementation (Step 5):
```
$ DATABASE_URL=postgresql://localhost/caserepo_bgap_b2 $PY -m pytest tests/test_b2_guest_upgrade.py -q -p no:warnings
......
6 passed in 0.76s
```

(b) Full suite (Step 6):
```
$ DATABASE_URL=postgresql://localhost/caserepo_bgap_b2 $PY -m pytest tests/ -q -p no:warnings
450 passed in 6.75s
```
(444 baseline + 6 new = 450, zero failures.)

## Concerns
None.
