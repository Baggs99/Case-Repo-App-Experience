# B2 Task 3 report — Mint guests on claim endpoints (`require_auth_or_mint_guest`)

**Status:** DONE_WITH_CONCERNS (one necessary test edit beyond the plan's Step-7 list — see Concerns)
**Commit:** b9294d02564d0f78c0a2ab5955e74277fec24858 — "Mint scoped guests on unauthenticated claim endpoints; null dead claim_token (N-1)"
**Branch:** bgap/b2-guest (worktree /Users/thomaskgould/dev/bgap-b2)

## What changed
- `webapp/auth/guest.py` — extended imports (`Response` from fastapi; `attach_session_cookie, create_session` from `webapp.auth.sessions`) and added `require_auth_or_mint_guest(request, response)`: returns the current real user unchanged; **403** when the current user is already a guest (scoped to one session); when unauthenticated, mints a guest, creates a server session, and sets the cookie on the injected `Response`, returning the guest.
- `webapp/routes/proposals.py` — `claim_proposal` auth dep → `require_auth_or_mint_guest` (added import). NULL-email guard: `_participant_emails` uses `.get()`; `_build_ics_for` falls back to `"guest@caseroom.invalid"` for ORGANIZER/ATTENDEE; `_send_invites` skips participants with no address.
- `webapp/routes/practice.py` — `claim_pair_token` auth dep → `require_auth_or_mint_guest` (added import).
- `webapp/repositories/proposals.py` — `claim_proposal` UPDATE now also sets `claim_token = NULL` (B1 report N-1: kills the dead token on the claimed row).
- `tests/test_b2_guest_claim.py` — NEW, 6 tests (unauth proposal claim mints guest interviewer + session cookie; authenticated real-user claim unchanged; guest can't reclaim a 2nd link → 403; unauth pair claim mints guest; guest-interviewer claim doesn't blow up on NULL-email invite path + .ics still fetchable; claim nulls dead claim_token). Module-level `_cleanup_case` helper + dedicated case in setUpClass + teardown for re-runnability.
- Updated 3 existing B1 tests that encoded the pre-B2 401: `tests/test_b1_proposals_open.py::test_requires_auth` → `test_unauthenticated_claim_mints_guest` (200); `tests/test_pairing.py` `TestPairingTokenClaim::test_unauthenticated_returns_401` → `test_unauthenticated_claim_mints_guest` (200) — pair/create + pair/status copies left at 401; `tests/test_b1_pairing_shortcode.py::test_claim_requires_auth` short_code claim → 200.
- **Extra (necessary) edit:** `tests/test_b1_proposals_open.py::test_double_claim_409` → `test_double_claim_404_dead_token` asserting 404. See Concerns.

## Evidence

(a) Task-3 test — before implementation (Step 2): `5 failed, 1 passed` (the authenticated-real-user regression already green; unauth paths 401'd, `require_auth_or_mint_guest` absent). After implementation (Step 8):
```
$ DATABASE_URL=postgresql://localhost/caserepo_bgap_b2 $PY -m pytest tests/test_b2_guest_claim.py -q
6 passed, 30 warnings in 0.77s
```

(b) New + 3 edited B1 files together (Step 8):
```
$ DATABASE_URL=postgresql://localhost/caserepo_bgap_b2 $PY -m pytest \
    tests/test_b2_guest_claim.py tests/test_b1_proposals_open.py \
    tests/test_pairing.py tests/test_b1_pairing_shortcode.py -q
47 passed, 131 warnings in 1.12s
```
(pair/create + pair/status `test_unauthenticated_returns_401` still present at lines 89 & 306 of test_pairing.py; only the pair/claim copy at line 212 changed.)

(c) Full suite (Step 9):
```
$ DATABASE_URL=postgresql://localhost/caserepo_bgap_b2 $PY -m pytest tests/ -q
434 passed, 453 warnings in 5.65s
```
(428 baseline + 6 new = 434, no failures.)

## Concerns
- **One test edit beyond the plan's Step-7 list.** The N-1 fix (Step 6) nulls `claim_token` on claim. A pre-existing B1 test, `test_b1_proposals_open.py::test_double_claim_409`, asserted that a second claim of an already-claimed token returns **409**. After the token is nulled, the second claim's lookup (`WHERE p.claim_token = %s`) finds no row and returns **404 "No such claim link"** — 404, not 409. The plan mandates both the N-1 fix and a green 434-passed suite, which are only reconcilable by updating this test. 404 is the semantically correct outcome (a claimed link's token is dead; it is no longer a claimable resource). Edit: renamed to `test_double_claim_404_dead_token`, assertion 409→404, with an inline comment. This is the only change made beyond the plan's explicit file list.
