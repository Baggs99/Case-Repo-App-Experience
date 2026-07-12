# PROGRESS
Updated: 2026-07-12T01:02:00-04:00 · Branch: feature/caseroom

## Now
Phase 6 (in-call reveal system) complete — next is Phase 7: rubric,
feedback, finalize, burn. Interviewer live checklist (PUT /rubric
debounced draft), finalize → grade normalize + feedback.finalized_at +
burned row + want-queue removal + full-PDF release (INV-3 flip),
candidate post-finalize view (grade, breakdown, notes, reveal timeline,
PDF + recording links). Rubric-template EDITOR UI deferred from P5 also
lands here.

## Done — Phase 6 (2026-07-12)
- `webapp/repositories/reveals.py` — INSERT..SELECT computes t_offset_ms
  from started_at inside the same statement that re-checks state='live'
  (no route-check race); ON CONFLICT idempotent (returns original row,
  already_revealed flag); list joins case_exhibits for display idx
- `webapp/routes/practice_exhibits.py` — GET /exhibits (manifest+iv,
  no keys) · GET /exhibit-blob/{eid} (ciphertext, participant) ·
  GET /exhibit-keys (interviewer 403-else) · POST /reveals (system of
  record, live-only 409, Origin CSRF) · GET /reveals (reconcile + T6.4)
  · GET /exhibit-key/{eid} (candidate, key IFF reveal row, else 404).
  DV-11 codes throughout; case_exhibits gained least-privilege
  accessors (list_manifest / list_keys / get_exhibit)
- `webapp/static/js/caseroom/exhibits.js` — ExhibitManager: candidate
  locked tray + preload progress + WebCrypto AES-GCM decrypt + lightbox
  (no download affordance); interviewer strip w/ locally-decrypted
  thumbs, Send (DC fast path + POST), sent-state restore on reload,
  lazy Case-PDF drawer (/api/cases/{id}/open-pdf iframe); DV-4 5s poll
  only while ctrl DC not open; quiet reconcile on reload vs spotlight
  on live reveal; reveal timeline in ended view (T6.4). rtc.js gained
  onCtrlClose; session page boot carries caseId; ?debug=1 now exposes
  window.__caseroom for evidence/debug driving
- **DV-13 (new, in INTEGRATION.md):** re-authoring a case 409s once any
  reveal references its exhibits — reveal timeline is permanent session
  record; found when the browser pass's reveal rows FK-blocked the
  authoring test. Also backfilled the DV-12 entry P5 referenced but
  never wrote. Authoring tests now author their own case row (never the
  shared dev dummy case)
- Tests: tests/test_reveals.py (5 integration tests: manifest leaks no
  keys, blob ≠ WebP magic, keys interviewer-only, full reveal flow incl.
  decrypt roundtrip via fallback key + cross-origin 403 + idempotence,
  debrief semantics) + DV-13 regression in test_exhibits. Suite 214
  passed ×3 consecutive runs
- Browser evidence (Playwright MCP, tabs localhost vs 127.0.0.1 = two
  cookie jars, session 105, ?nomedia=1&debug=1): pre-reveal candidate
  fetches are ciphertext only (first4 ≠ RIFF, no WEBP@8; keys 403,
  fallback 404) · Send 1 unlocked far side via ctrl DC · ctrl.close()
  then Send 2 unlocked via fallback poll ≤5 s (ctrl confirmed closed
  both sides) · candidate reload mid-call restored both slots quietly ·
  ended view timeline "0:33 Exhibit 1 / 1:44 Exhibit 2" matches DB rows
  t_offset_ms 33221/103565 = revealed_at−started_at exactly · shots in
  output/evidence/p6-*.png
- Commits: a169b97 (backend) · d11a435 (frontend) · 88592cc (DV-13)

## Done — Phase 5 (2026-07-12)
- `webapp/exhibits_render.py` — PyMuPDF page → WebP ≤1800px q82 (spec
  §4.4 params) + on-demand JPEG thumbs for the authoring grid (no
  preview-pipeline dependency)
- `webapp/repositories/case_exhibits.py` — encrypt (AES-256-GCM) +
  store under gitignored output/exhibits/ (EXHIBITS_DIR env), atomic
  replace-set with orphan-blob cleanup on both success and failure.
  Note: the Storage abstraction is read-only, hence plain file I/O for
  writes (DV-12a); prod placement is an O1 deploy question
- `/cases/{id}/exhibits` authoring page (myCase light theme): click
  pages in order → numbered badges → save; POST renders+encrypts server-
  side. Any verified user may author (DV-12b: community authoring,
  created_by recorded; no case draft/publish gate — exhibits optional,
  sessions never blocked on them)
- Seed script now generates a real 3-page dummy PDF under
  output/cases/devschool/ (LocalStorage-resolvable)
- Evidence: suite 208 passed ×3 runs (one cold-start flake on the very
  first run — fitz first-import while WS tests ran; not reproducible);
  encrypted blobs on disk with non-WebP magic (ciphertext at rest, INV-6);
  decrypt roundtrip → WEBP magic; direct HTTP to blob path 404;
  page-beyond-range 400; unauth thumb rejected
- Deferred: T5.3 rubric-template EDITOR UI → Phase 7 (where all rubric
  UI lives; generic template + case-override fallback already work
  server-side since Phase 2)

## Done — Phase 4 (2026-07-12)
- `/session/{id}` page (participants only, DV-11) in the myCase brand
  (mycase/myCase Style Guide.html: Archivo, emerald accent, dark call
  theme, square-ish corners). CaseRoom pages carry the myCase look; the
  existing app's pages keep theirs — reconciling brands is an owner call
- Vanilla modules: `signal.js` (WS client, backoff reconnect, 30 s pings,
  fatal-close codes), `rtc.js` (perfect negotiation w/ polite=candidate,
  1.2 Mbps sender cap, negotiated ctrl DataChannel id 0, ICE-restart on
  disconnected/failed, getStats sampler), `ui.js`, `session.js`
  (A7 admit ordering: POST /state→live, only then WS admit; ?debug=1
  stats overlay; ?forceRelay=1; ?nomedia=1 smoke-test flag; no state
  transition on pagehide so mid-call reload can restore — P6 needs this)
- Two real-browser evidence pass (Playwright, two tabs = two cookie
  jars via localhost vs 127.0.0.1, session 48): knock modal on
  interviewer, consent gating, Admit → DB state=live + started_at,
  both tabs flip to call view, **ctrl DataChannel echo RTT 1 ms over the
  P2P connection**, End call → ended view + DB debrief + ended_at
- Bug caught by the browser pass: explicit `display:` on views/modal
  defeated the `hidden` attribute (invisible modal swallowed all clicks).
  Fix: global `[hidden]{display:none!important}`
- Full suite: 201 passed (incl. session-page auth test)
- Deferred (reasons): real camera/mic A/V + bitrate-cap numbers need a
  human with two browser profiles (getUserMedia permission prompts +
  actual devices) — 2-min script below; `?forceRelay=1` needs TURN (O2)
- Manual A/V check for Thomas: server on :8077 → two Chrome profiles →
  log in a@yale.edu / b@yale.edu (pw caseroom-dev-1) → both open
  /session/<new id>?debug=1 → grant cam/mic → consent both → admit →
  confirm video/audio both ways and overlay shows ≤ ~1300 kbps ≤ 1280×720

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
