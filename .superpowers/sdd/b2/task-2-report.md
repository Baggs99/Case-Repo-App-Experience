# B2 Task 2 report — Guest CRUD + `require_guest` dependency (`webapp/auth/guest.py`)

**Status:** DONE
**Commit:** bc4ffff220f805fec138352477ab440620ac5f82 — "Add guest CRUD + require_guest dependency"
**Branch:** bgap/b2-guest (worktree /Users/thomaskgould/dev/bgap-b2)

## What changed
- NEW `webapp/auth/guest.py` (4-line header docblock) — `mint_guest_user(display_name="Guest")` inserts an `is_guest=TRUE`, NULL-email/password row and returns the `User`; `upgrade_guest(user_id, email, password)` is a race-safe in-place conversion (`UPDATE ... WHERE id=%s AND is_guest=TRUE`) validating school-domain email + password strength, hashing the password, mapping `UniqueViolation`→`EmailAlreadyRegistered` and zero-rows→`GuestUpgradeConflict`; `GuestUpgradeConflict(Exception)` sentinel; `require_guest(request)` → 401 if no user, 403 if not a guest. Parameterized SQL only.
- NEW `tests/test_b2_guest_crud.py` — 6 tests (mint flags row; upgrade converts in place keeping the same id; upgrade rejects bad domain; double-upgrade second call conflicts; upgrade rejects taken email; `require_guest` returns guest / 403s real user / 401s anon).

## Evidence

(a) Task-2 test — before `guest.py` existed (Step 2): `6 failed` (ModuleNotFoundError: `webapp.auth.guest`). After writing the module (Step 4):
```
$ DATABASE_URL=postgresql://localhost/caserepo_bgap_b2 $PY -m pytest tests/test_b2_guest_crud.py -q
6 passed, 9 warnings in 0.80s
```

(b) Full suite — no regression:
```
$ DATABASE_URL=postgresql://localhost/caserepo_bgap_b2 $PY -m pytest tests/ -q
428 passed, 425 warnings in 5.63s
```
(422 baseline + 6 new = 428, no failures.)

## Concerns
None.
