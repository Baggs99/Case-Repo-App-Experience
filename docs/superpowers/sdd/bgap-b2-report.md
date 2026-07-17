# B2 — Guest Interviewer: Phase Report

**Status: DONE** · Branch `bgap/b2-guest` · Head `43cfb7e` · Date 2026-07-17
Worktree: `/Users/thomaskgould/dev/bgap-b2` · DB: `caserepo_bgap_b2`

Delivered the guest-interviewer path: an unauthenticated visitor claims an open-link/QR session, is minted as an `is_guest` user + session cookie scoped to exactly that one session, drives the full console through finalize (rendered as "Guest"), then upgrades the row to a real account in place with history FKs intact. The guest cookie scoping is airtight — a guest 403s on every non-session endpoint, every other session, and the entire case library except its own session's case PDF.

## Suite counts

| | Passed |
|---|---|
| Baseline (before, seeded) | 418 |
| After B2 | **451** |

+33 net. Command: `DATABASE_URL=postgresql://localhost/caserepo_bgap_b2 .venv/bin/python -m pytest tests/ -q` → `451 passed`. Migration 025 re-applies idempotently (only a harmless "already exists" NOTICE). **Tests skip without the dev seed** (`scripts/seed_caseroom_dev.py`) — seed a/b/c@yale.edu first (baseline is 243 passed / 175 skipped unseeded).

## Tasks (all reviewed)

| Task | Deliverable | Commit range | Review |
|---|---|---|---|
| 1 | Migration 025 + `User.is_guest` plumbing | a982f78..18361a3 | CLEAN |
| 2 | Guest CRUD (`mint_guest_user`, `upgrade_guest` race-safe, `require_guest`) | 18361a3..bc4ffff | CLEAN |
| 3 | Mint guests on both claim endpoints; NULL-email invite guard; N-1 claim_token null | 169fa5d..cda02a2 | MINOR-ONLY → **orphan-guest vector fixed** |
| 4 | Session scoping (`require_session_participant` ×19), guest-reject, `is_guest` payload | cddd471..80ce68a | **CRITICAL library-leak fixed** → re-review MINOR-ONLY |
| 5 | `POST /api/v1/auth/upgrade` (in-place, FKs intact) | d377048..9c74542 | MINOR-ONLY |
| — | Final whole-branch review fixes (M-1..M-4) | 61a8ffe..43cfb7e | applied, 451 green |

Ledger + per-task diff packages under `.superpowers/sdd/b2/`.

## Two security findings caught and fixed (the phase's security surface)

- **CRITICAL (Task 4) — library leak.** The guest-reject was on `require_auth_api`, but the case-library / file / search / page / room endpoints use `require_auth`, which does NOT reject guests. A guest could iterate `case_id` and download every case PDF + exhibits (live-proven). Nuance: the guest console legitimately loads its OWN case PDF via `/api/cases/{caseId}/open-pdf` → `/files/cases/{caseId}`. **Fixed case-scoped:** new `require_case_access` (guest allowed only for a case it has a session on) on those two; new `require_auth_no_guest` (guest 403; real/anon behavior identical to `require_auth`) on all other library/case/search/pages/rooms/change-password endpoints. Adversarially re-verified CLOSED.
- **IMPORTANT (Task 3) — orphan guest rows.** Minting happened before the claim validated the token, so an unauthenticated bad-token POST persisted an orphan `users`+`sessions` row (scriptable row-creation vector). **Fixed:** `discard_minted_guest(request)` reaps the just-minted guest at every claim failure path.

## New / modified endpoints

| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/api/v1/auth/upgrade` | `require_guest` + `require_same_origin` | **New.** Guest→real in place. 400 bad-domain/weak-pw, 409 taken-email/already-real, 403 non-guest, 401 anon. Returns `{upgraded, user_id, email}`. |
| POST | `/api/proposals/claim/{claim_token}` | `require_auth_or_mint_guest` + CSRF | **Auth changed.** Unauth → mints guest + cookie. Guests may claim ONLY an instant case-set "now" link; scheduled/case-less → 409 (+ reaped). Already-guest re-claim → 403. N-1: nulls dead `claim_token`. |
| POST | `/api/practice/pair/claim` | `require_auth_or_mint_guest` + CSRF | **Auth changed.** Unauth → mints guest (candidate seat). |
| GET/POST/PUT | 19 `/api/practice/{session_id}/*` + `/ics/session-{id}.ics` | `require_session_participant` | **Auth changed.** Behavior-neutral for real users (non-participant still 404); guest 403 on any session it is not a participant of. |
| GET | `/api/practice/{session_id}` | `require_session_participant` | Payload gains `interviewer_is_guest`, `candidate_is_guest`. |
| GET | `/api/cases/{id}/open-pdf`, `/files/cases/{id}` | `require_case_access` | **Auth changed.** Guest allowed only for its own session's case; 403 on any other case. |
| GET | library/file/search/pages/rooms + change-password (`require_auth` before) | `require_auth_no_guest` | **Auth changed.** Guest 403; real/anon unchanged. |
| — | `require_auth_api` (all non-session `/api/*`) | — | **Behavior changed.** Now 403s guests (the choke point). |

WebSocket `/ws/practice/{session_id}` unchanged — already scopes via cookie + `role_of` (guest-agnostic; foreign → CLOSE_FORBIDDEN).

## New migration

- **025_guest_users.sql** — `users.is_guest BOOLEAN NOT NULL DEFAULT FALSE`; `email`/`password_hash` `DROP NOT NULL`; `users_email_allowed` CHECK re-added as `is_guest OR (email IS NOT NULL AND <domain arms>)` — guest NULL-email allowed; non-guest NULL-email or bad-domain rejected. Idempotent (ADD COLUMN IF NOT EXISTS; DROP NOT NULL no-op; DROP CONSTRAINT IF EXISTS + re-ADD).

## Interfaces delivered (later phases build against these)

- **`users.is_guest: bool`** (on `User` dataclass, default False; in all 3 user SELECTs).
- **`require_session_participant(session_id: int, request: Request) -> User`** (`webapp/auth/guest.py`) — B3 uses this for any new session-scoped endpoint that guests may drive.
- **`interviewer_is_guest` / `candidate_is_guest`** on `get_practice_session(...)` → surfaced in `GET /api/practice/{id}`. **B3 gates swap on these** (swap must never be offered to a guest).
- **`POST /api/v1/auth/upgrade`** + `upgrade_guest(user_id, email, password) -> User` (race-safe `UPDATE ... WHERE id=%s AND is_guest=TRUE`) + `GuestUpgradeConflict`.
- **`mint_guest_user(display_name="Guest") -> User`**, **`require_guest`**, **`require_auth_or_mint_guest(request, response)`**, **`require_auth_no_guest`**, **`require_case_access(case_id, request)`**, **`discard_minted_guest(request)`** — all in `webapp/auth/guest.py`.
- **`require_auth_api` now 403s guests** — any future non-session `/api` endpoint is guest-safe by default; session/case-content endpoints must opt into the guest-aware guards above.
- **`claim_proposal(token, user_id, is_guest=False)`** — the `is_guest` param rejects guest claims of scheduled/case-less proposals (409).

## Cross-phase notes for the orchestrator (before merging)

- **Shared files touched additively:** `webapp/auth/dependencies.py` (guest-reject branch in `require_auth_api`), `webapp/auth/users.py` (`User.is_guest` + 3 SELECTs — **expect a merge touch with B5**, which also edits users.py heavily), `webapp/main.py` (one `include_router(guest_routes.router)` line — expect touch with other phases adding routers), `webapp/repositories/proposals.py` (`claim_proposal` gains `is_guest` param + nulls `claim_token`), `webapp/repositories/practice_sessions.py` (`get_practice_session` SELECT gains 2 columns), the 4 `practice_*` route files + `proposals.py`/`practice.py` (auth-dep swaps), and the library/file route files `files.py`/`exhibits.py`/`search.py`/`pages.py`/`rooms.py`/`auth.py` (auth-dep swaps).
- **New module:** `webapp/auth/guest.py` (guest identity + deps). **New router:** `webapp/routes/guest.py` (registered in `main.py`).
- **Migration 025** is the only B2 migration; applies after 021.
- **Intentional existing-test changes (expect these diffs):** 3 B1 tests now assert 200 (not 401) for unauthenticated claim/pair-claim (guests now mint) — `test_b1_proposals_open.py`, `test_pairing.py` (`TestPairingTokenClaim` only), `test_b1_pairing_shortcode.py`; and `test_b1_proposals_open.py::test_double_claim_409` → `test_double_claim_404_dead_token` (a re-claim of a now-nulled token is 404 "No such claim link", not 409 — a consequence of the mandated N-1 fix). `TestPairingTokenMint` (pair/create) and `TestPairingTokenStatus` (pair/status) stay 401 — guests can't mint/poll.
- **DD-1 honored:** B2 inserts no case-less `practice_session` and adds no negotiating logic (that's B3). Guests reach a live console only via a case-set "now" open-link claim.

## Assumptions / DEFERRED

- **Upgrade leaves the account unverified** (`email_verified_at` NULL), matching a fresh password signup — inbox control is proven later by the existing verification flow / B5. No verification email sent from B2 (B5 owns email infra); the OTP upgrade path named in the brief is B5 territory.
- **Guest role direction:** a guest becomes *interviewer* via a proposal claim where the creator's `from_role='candidate'` (the spec §6.2 console path), or *candidate* via `pair/claim` (B1 makes the claimer the candidate). B2 mints a guest on both per the brief and did not re-plumb pairing role direction.
- **Guest is scoped to ONE session** (re-claim → 403; can only claim an instant ready-to-run link). No cross-session history accrues until upgrade.
- **M-5 (accepted, cosmetic):** `POST /api/cases/{id}/exhibits` (`require_verified_user`) returns a login redirect (not 403) to a guest — the guest is still blocked (never verified); status-code inconsistency only. Left as-is to avoid changing shared `require_verified_user` semantics.
- **Pre-existing (not B2):** `datetime.utcnow()` deprecation warnings in `webapp/auth/sessions.py` and `email_sender.py` remain (out of scope).

## ESCALATIONS

None. No Fable consults were made or are queued.
