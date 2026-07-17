# B2 Task 1 report — Migration 025 + `User.is_guest` plumbing

**Status:** DONE
**Commit:** 18361a3059464655a73419a9ad1e3bc91d891da4 — "Add guest identity: migration 025 + User.is_guest"
**Branch:** bgap/b2-guest (worktree /Users/thomaskgould/dev/bgap-b2)

## What changed
- NEW `db/migrations/025_guest_users.sql` — `users.is_guest BOOLEAN NOT NULL DEFAULT FALSE`; drop NOT NULL on `email`/`password_hash`; replaced `users_email_allowed` CHECK with a guest-aware version (guests bypass the school-domain gate; non-guests still require a non-null yale/umich/booth-guest email).
- MODIFY `webapp/auth/users.py` — `User.email` → `Optional[str]`; added `is_guest: bool = False` to the dataclass; `_row_to_user` reads `row.get("is_guest", False)`; added `is_guest` to the SELECT column lists in `get_user_by_email`, `get_user_by_id`, `authenticate`.
- NEW `tests/test_b2_guest_users.py` — 4 tests (guest NULL email/password allowed; non-guest NULL email rejected; non-guest bad domain rejected; `User.is_guest` plumbing).

## Evidence

(a) Migration double-apply (idempotency) — both runs exit 0, second emits only a harmless NOTICE:
```
=== FIRST APPLY ===
ALTER TABLE  (x5)
=== SECOND APPLY (idempotent re-run) ===
psql:db/migrations/025_guest_users.sql:15: NOTICE:  column "is_guest" of relation "users" already exists, skipping
ALTER TABLE  (x5)
=== EXIT 0 ===
```

(b) Task-1 test — before users.py edit: `1 failed, 3 passed` (test_user_dataclass_exposes_is_guest → `AttributeError: 'User' object has no attribute 'is_guest'`, exactly as the plan predicted). After edit:
```
tests/test_b2_guest_users.py ... 4 passed, 6 warnings in 0.52s
```

(c) Full suite:
```
422 passed, 422 warnings in 5.71s
```
(418 baseline + 4 new = 422, no failures.)

## Concerns
None.
