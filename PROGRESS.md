# PROGRESS
Updated: 2026-07-12T00:20:00-04:00 · Branch: feature/caseroom

## Now
Phase 3 (in-app WebSocket signaling) complete — next is Phase 4: the call
experience. Session page `/session/{id}` with lobby (device pickers,
consent checkbox, knock state) and live view; `signal.js` / `rtc.js` /
`ui.js` vanilla modules; perfect negotiation (interviewer impolite);
1.2 Mbps bitrate cap; negotiated `ctrl` DataChannel; ICE-restart banner;
teardown → debrief. Thomas keeps a style guide at
`mycase/myCase Style Guide.html` — consult it for the UI.

## Done — Phase 3 (2026-07-12)
- `webapp/signaling.py` — process-local hub: one socket per (session,
  role) with newest-wins replacement (old closed 4000), knock only from
  candidate (relayed with display name), admit/deny only from
  interviewer, sdp/ice relayed only post-admit and only between the two
  participants, extra fields stripped on relay, unknown types dropped,
  message contents never logged, `admitted` survives reconnect,
  peer-joined/peer-left presence, room GC when empty
- `webapp/routes/signal_ws.py` — `/ws/practice/{id}`: cookie auth done
  in-route (SessionMiddleware is BaseHTTPMiddleware → never runs for
  WebSockets), participant + joinable-state gate (4401/4403), DB lookups
  via threadpool, 60 s receive timeout kills dead sockets (clients ping
  every 30 s per §4.2)
- Tests: 19 fake-socket unit tests (every §4.2 rule) + 4 REAL end-to-end
  WebSocket integration tests via TestClient against the live app + dev
  DB (skip cleanly when no DB): full knock→admit→sdp/ice→bye flow,
  pre-admit sdp proven blocked by ordering, outsider 4403 / anon 4401 /
  aborted-session 4403, reconnect closes old socket 4000 and new socket
  relays. Full suite: 200 passed
- TestClient quirk documented in test: its synthetic client host
  "testclient" violates sessions.ip_address INET, so tests mint session
  cookies via create_session(ip_address=None) instead of POST /login
- httpx installed in .venv (dev-only, like pytest — NOT in
  requirements.txt)

## Done — Phase 2 (2026-07-11)
- Migration 012 `state_changed_at` — applied twice cleanly (idempotent)
- `webapp/practice_states.py` pure state machine + 14 unit tests covering
  every edge/actor/consent combination, incl. a contextmanager-re-raise
  regression test (see bug note below)
- `webapp/repositories/rooms.py` (auto-create, slug dedupe, races settled
  by UNIQUE constraints) and `webapp/repositories/practice_sessions.py`
  (create/get/consent/transition under FOR UPDATE, A4 stale sweep)
- Routes: `/room`, `/room/{slug}` page shell; `/api/practice` create/read,
  `/consent`, `/state`, `/join-config` (ICE from `ICE_SERVERS_JSON`,
  STUN default); Origin-check CSRF on all mutating routes
- `scripts/seed_caseroom_dev.py` — 3 verified dev users + dummy case
- Evidence (curl against live dev server, session 2):
  scheduled→lobby 200 · live w/o consents **409** · consent A/B 200 ·
  live by candidate **403** · live by interviewer 200 (started_at set) ·
  live→lobby **409** · finalized via /state **409** · outsider **404** ·
  unauthenticated **401** · cross-origin POST **403** · join-config 200
  (ws_path + ice_servers) · live→debrief 200 · consent post-start **409** ·
  DB row: state=debrief, both consents, started/ended/state_changed stamped
- Full suite: 177 passed (`pytest tests/ -q`)

## Bug fixed en route
`TransitionError` was a frozen dataclass; contextlib `__exit__` assigns
`exc.__traceback__` on re-raise, frozen `__setattr__` raised
FrozenInstanceError, and every 403/409 became a 500 — but only on paths
crossing a DB context manager, which plain unit tests never did.
Regression test added (`TestExceptionMechanics`).

## Done — Phase 1 (2026-07-11)
- INTEGRATION.md (mappings, DV-1..11, A1..A9, O1..O4); spec at
  docs/caseroom-spec.md; migration 011 (idempotent, 18 tables);
  helpers exhibit_crypto/csrf/upload_limits + 25 tests; local Postgres 17
  dev DB; `.gitignore` covers `.env`/`.venv` (verified pre-commit)

## Environment warning — iCloud eviction (READ FIRST)
~/Documents is iCloud-synced with Optimize Mac Storage; it evicted repo
contents TWICE in one session (second time: 224 files, killing git and
pytest mid-phase). The working copy now lives at
`/Users/thomaskgould/dev/Case-Repo-App-Experience` (non-synced), with a
symlink left at the old Documents path. Do all work in ~/dev. The stale
copy `Case-Repo-App-Experience.icloud-stale` in Documents can be deleted.
Permanent fix is Thomas's call: keep projects out of iCloud paths,
disable Optimize Mac Storage, or Finder → "Keep Downloaded".

## Blocked / decisions needed
- O1 prod host / deploy flow / main auto-deploy? — default: owner merges
- O2 TURN provider before launch — default: Cloudflare TURN; dev is
  STUN-only either way
- O3 final consent copy (spec D3) — placeholder ships meanwhile

## Assumptions
- A1..A9 in INTEGRATION.md §5; DV-11 status-code semantics
- Dev password for seeded users: caseroom-dev-1 (local DB only)
