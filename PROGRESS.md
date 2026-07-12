# PROGRESS
Updated: 2026-07-12T02:20:00-04:00 · Branch: feature/caseroom

## Now
Phase 10 + Interviewer Console + conformance sweep complete — next is
Phase 11: hardening (verify script T11.1, cross-browser Chrome+Safari
pass T11.2 incl. the Safari audio/mp4 recording path, failure-mode
pass T11.3: wifi drop → ICE restart, signal-server restart → WS
reconnect, candidate mid-call reload re-verify). Owner decisions O1–O3
still open; rubric-template editor UI still deferred (P11 polish or
cut for v1 — generic template works server-side).

## Done — Browse results back to a GRID (2026-07-12, owner call)
- Owner: results should stay grid-like. Rows → guide-styled tiles
  (md:2 / xl:3): .case-card square hairline + school accent bar, caps
  kicker w/ difficulty badge, 16px/700 title (hover green), serif firm,
  color-coded usefulness, mt-auto pinned hairline footer w/ "Open case
  →"; container 5xl→6xl. Hero/filter band unchanged from the redesign.
  Shots: output/evidence/browse-grid-{light,dark}.png. Commit 1c902e2

## Done — Browse rows unnumbered + demo data (2026-07-12, owner call)
- Result rows lost the %02d index column (owner: position isn't worth
  numbering). Rows now kicker+title-led, grid [1fr auto]. Commit 8fb0f60
- 7 realistic DEMO cases seeded in dev (ids 354–360: Nordic Skies /
  Copper Creek / MedLink / Harbor & Vine / Atlas Freight / Stern Ridge
  / Brightline Grid) + 11 votes so all three usefulness colorings show.
  Remove with: DELETE FROM case_votes WHERE case_id BETWEEN 354 AND 360;
  DELETE FROM cases WHERE id BETWEEN 354 AND 360;
  Shots: output/evidence/browse-7cases-{light,light-2,dark}.png

## Done — Browse page redesign (2026-07-12, owner-directed)
- index.html + _search_results.html moved from card grid to the
  guide-native casebook pattern: hero = green eyebrow + Archivo-800
  display ("Find your next case.") + Source-Serif lede; stats as
  rule-topped columns (no boxes); filter band under a 2px ink section
  opener w/ serif aside (search icon dropped per rule 05); results as
  numbered editorial rows — %02d faint index (position in the result
  slice), caps kicker w/ 7px square school swatch (accent data kept),
  19px/700 title (hover → green), meta line w/ color-coded usefulness
  TEXT (pills dropped), square difficulty badge + "Open case →".
  Empty state in guide voice. htmx contract untouched (form ids,
  #results target, setDifficulty) — filter round-trip verified in
  browser (Hard → empty state → Any → row restored)
- Shots: output/evidence/browse-rows-light.png / -dark.png. Suite 234
  passed. Commit a317d04
- Domains sign-in note now renders only when logged out

## Done — Interviewer Console + conformance sweep (2026-07-12,
owner-directed)
- Console per mycase/myCase Interviewer Console.html (same __bundler
  format; template decoded like the guide's): top bar (staircase +
  wordmark · case kicker/title · CANDIDATE name · INTERVIEW master
  clock counting from server started_at with 45-min cap remaining +
  2px green progress rule · REC badge · End call), left column tabs
  [Score & exhibits | Case PDF (lazy iframe)] — exhibit RELEASE rows
  ("Release to candidate" → "SENT · m:ss" from t_offset_ms; NO Recall:
  a revealed key can't be un-sent, spec's accepted tradeoff), rubric
  score-cell strips (1..max_points ink cells, click-again clears,
  autosaves through the P7 draft endpoints) + Source-Serif italic
  evidence inputs + overall notes; right rail: candidate feed (306px,
  LIVE badge, self-view PiP, mute/cam), SEGMENT TIMER with logged
  editable laps (client-side tool, page-memory only), RUBRIC — SUMMARY
  mirror + running average. Candidate call view unchanged
- session.html now theme-aware: guide light tokens default, body.dark
  mirrors the app toggle (localStorage 'theme'); old interviewer
  drawers/panel removed; debug overlay moved bottom-right
- Evidence (session 596, real call): console live with master clock
  ticking, scored structure4/quant3/insight5 → "Draft grade: 2.4/5
  Saved ✓" (12/25 ✓) mirrored in rail; Release → candidate slot
  unlocked via DC + "SENT · 0:27"; segment logged; End from console →
  debrief editor restored the console scores (grade prefill 2.4).
  Shots: output/evidence/console-light.png / console-dark.png
- Conformance sweep: 47 leftover rounded-* classes are inert (config
  zeroes those scales); no Inter font remnants; exhibits.html tokens
  fixed earlier; school accent bars on case cards KEPT (data encoding,
  not decoration); emerald-600/700 darkened (#157A4C/#116340) — brand
  green #1B9A5F is 3.7:1 on chalk and WCAG AA text floor (4.5:1) wins
  over token purity; fills/dots stay on #1B9A5F via emerald-500.
  Privacy test hardened to assert on <main> (the Tailwind config
  comment "4.5:1" tripped the old whole-page substring check)
- Still open vs guide rule 05: a few Lucide icons (search, votes, PDF
  buttons, theme toggle) + favicon is still the browser default —
  staircase favicon is a P11 nicety
- Commit: 7ef9b88

## Done — Phase 10 (2026-07-12)
- `webapp/repositories/recordings.py` — chunk append under FOR UPDATE
  w/ strict seq (409 names the expected seq so client retries can tell
  "already applied" from "gap"), row created on seq 0, complete()
  idempotent-ish, files rec_{sid}_{uid}_{rand16}.{ext} under
  RECORDINGS_DIR (default output/recordings/, gitignored). T10.4
  deny-all equivalent: FastAPI mounts only /static — recording files
  are simply never web-served (test-proven 404)
- `webapp/routes/practice_recordings.py` — POST chunk (multipart
  seq/mime/blob; live|debrief only; INV-5 via Phase-1 upload_limits:
  8 MB chunk / 150 MB total / chunk-0 container sniff; mime whitelist;
  Origin CSRF), POST complete, GET list (no paths leaked), GET
  /{user_id} download passthrough (either participant, spec §5)
- `recorder.js` — feature-detected mime (webm/opus, mp4 Safari path
  untested here), 60 s timeslice, sequential upload queue w/ 5-step
  backoff; 409 "expected seq N>mine" treated as already-applied; A9:
  permanent failure stops capture + flags badge, call unaffected;
  stopAndComplete flushes final chunk then completes. REC badge
  (blinkdot) in call view; recording list w/ download links in ended
  + feedback views. nomedia mode now synthesizes an oscillator track
  (AudioContext resumed eagerly + on first click — Chrome autoplay
  policy stalled the first evidence run until a real click)
- Tests (tests/test_recordings.py, 4): ordered appends + exact-byte
  downloads, gap/dup/pre-seq0 409s, 413 chunk + total caps, 415
  container/mime, 403 CSRF, state/role gates, files-never-web-served.
  Suite 234 passed
- Evidence (session 568, two tabs, oscillator audio): REC badge live →
  3 chunks/side at 738 KB ≈ 32 kbps math → candidate tab KILLED →
  candidate 4 chunks (final partial flushed on pagehide) completed=f,
  loss < 60 s → interviewer End → 5 chunks, 1 079 760 B, completed=t →
  ended view lists "Bob (candidate) incomplete · Alice (interviewer)
  1.0 MB" → downloaded blob plays in-browser: canplay=true, duration
  263 s (≥ 3 min ✓), 1 079 760/263 ≈ 32.8 kbps ✓ → direct file URL 404
  → 9 MB chunk POST → 413
- Commits: 53197c2 (backend) · 7b25628 (recorder.js) · this block's
  autoplay fix

## Done — myCase brand restyle (2026-07-12, owner-directed)
- Source: mycase/myCase Style Guide.html (React bundle; tokens
  extracted from its Implementation-spec section — "tokens are the
  contract"). Light chalk #F3F5F8 / dark midnight #081222, surface
  #FFFFFF/#101E36, ink #0D1C31/#E9EEF5, uptick #1B9A5F/#2FC07E,
  cobalt links, hairlines #C9D2DF/#24365A
- Mechanism: Tailwind slate/emerald ramps REMAPPED in base.html config
  so every existing utility lands on brand tokens; fonts → Archivo +
  Source Serif 4; radius scale zeroed (guide rule 01, rounded-full
  kept for dots); shadows zeroed (rule 02); btn-secondary → underlined
  text (rule 03); badges → square caps labels; rise motion 16px/420ms
  cubic-bezier(0.22,1,0.36,1) (rule 07); staircase wordmark
  (serif-italic "my" + Archivo-800 "Case", theme-aware gradient stops)
  in nav + footer; titles "Case Repo" → "myCase" across templates;
  session/exhibits pages squared + light --muted token fixed; 🔒
  emoji → LOCKED caps label (rule 05)
- Evidence: screenshots output/evidence/restyle-*.png (browse
  light+dark, case detail dark, room light); computed-style check
  confirmed dark pill = chalk block; suite stayed green
- Known deviations from the guide, deliberate: Lucide icons remain on
  a few controls (search, votes, PDF buttons — rule 05 wants none;
  sweep later), amber/rose semantic ramps kept for Medium/Hard/errors
  (accessibility floor > brand purity), theme toggle stays an icon
  button not the guide's labeled pill
- Also fixed: test_ws_integration now deletes its sessions (each suite
  run was piling scheduled sessions on the dev dummy case → 143 stale
  rows purged from dev DB)

## Done — Phase 9 (2026-07-12)
- `webapp/repositories/dashboard.py` — history (finalized, both roles,
  grade visible to both participants per A10, LIMIT 50);
  dimension_averages = AVG(points/max_points)×5 over last 10
  finalized-as-candidate, one GROUP BY over feedback.rubric_json ×
  template items (A11); the three §4.8 rules as bounded queries with
  shared eligibility (published, non-duplicate, not burned, not in
  either queue): coverage-gap (fewest finalized candidate-sessions per
  type, alphabetical tie-break, then highest usefulness % per DV-6),
  difficulty-ladder (mean of last 3 grades ≥ 4.0 → next rung of
  most-practiced (type,difficulty), Easy→Medium→Hard per DV-7),
  weak-dimension (lowest trend dimension → case whose case-specific
  template gives it the largest max_points share, >0.2 floor).
  Union/dedupe/cap 5 with rule attribution
- GET /api/dashboard (identity from session — no user param, T9.3);
  own-room page grew Recommended-next / Your-trend (hairline bars,
  weakest first) / History table panels, myCase-styled; visiting view
  untouched (stats + intersections only)
- A10/A11 recorded in INTEGRATION.md
- Tests (tests/test_dashboard.py, 4): trend numbers equal the
  hand-computed table in the module docstring (structure 4.00, quant
  1.00, insight 3.67, communication 4.33, synthesis 2.00 — done-when's
  hand-computed comparison); all three rules fire on the fixture
  (gap→B1 over unrated B2 via DV-6 rating, ladder→TypeA Medium rung
  at mean 4.23, weak-dim→quant-heavy template share 0.8); T9.3
  privacy audit: other user's dashboard excludes the subject's
  sessions, feedback/rubric endpoints 404 for non-participants,
  visiting room HTML carries no grades/History/Recommended markers,
  anonymous /api/dashboard 401. Suite 230 passed
- Dev-room evidence: seeded 2 finalized demo sessions → dashboard
  screenshot output/evidence/p9-dashboard.png (trend bars weakest-
  first, spot-checked 2.5 = (3+2)/2/5×5; history w/ green tabular
  grades); Recommended empty for Alice is CORRECT (only dev case is in
  her Give queue → excluded); demo rows deleted after
- Commits: 2dd3bdf (restyle) · 7708c38 (dashboard backend+tests) ·
  4d194cf (dashboard panels)

## Done — Phase 8 (2026-07-12)

## Done — Phase 8 (2026-07-12)
- `webapp/repositories/queues.py` — want/give add(idempotent)/remove/
  list/membership + the two §4.7 intersection queries (one join each,
  burned-for-would-be-candidate excluded via NOT EXISTS)
- `webapp/repositories/proposals.py` — create (self-propose 400, >3
  times 400, A6 burned 409), inbox, pending_count, 7-day sweep_expired,
  respond() under FOR UPDATE: decline, or accept → practice_session
  INSERT + proposal link IN THE SAME TRANSACTION (room/template ids
  resolved beforehand; racing double-accept → 409)
- `webapp/ics.py` — dependency-free RFC 5545 builder: METHOD:REQUEST,
  stable UID caseroom-{id}@{host}, UTC DTSTART/DTEND (45-min default),
  §3.3.11 TEXT escaping, §3.1 75-octet folding, CRLF
- EmailSender grew optional attachments (console backend writes them
  to output/emails/; Resend backend base64s them); accept emails BOTH
  parties w/ invite.ics attached — mail failure logged, never fails
  the accept. GET /ics/session-{id}.ics download (participants only)
- Routes: /api/queues (+kind/case add/remove, Origin CSRF),
  /api/proposals (+/inbox w/ sweep, /{id}/accept, /{id}/decline);
  room page context (own: upcoming/inbox/queues; visiting: public
  stats + intersections); nav "My room" + pending-proposal badge via
  templating.render (indexed COUNT/page)
- `public_stats` (finalized count + A8 streak: consecutive calendar
  weeks, current-week grace) + `list_upcoming_for_user`
- **A4 sweep extended** (found via the Upcoming panel): 'scheduled' is
  also pre-debrief — no-shows 6 h past scheduled_at and never-opened
  unscheduled sessions now abort; future-scheduled survive. 98 stale
  dev rows cleaned
- UI: room.html full rewrite (own panels + visiting intersections +
  propose modal w/ message + ≤3 datetime-local times), room.js
  (localized time pills, accept w/ time pick → redirect to session,
  decline, unqueue), case_detail Want/Give buttons (Give = client-side
  honesty confirm per spec), base.html My-room badge
- Tests: tests/test_queues_proposals.py (8): queue CRUD/gating/CSRF,
  intersection fixture per done-when (3 users, 6 cases, C2 burned for
  Bob → excluded; verified at repo level AND through the rendered room
  page), create validation, decline + recipient-only 404s, expiry
  sweep (accept of 8-day-old → 409 + state=expired), accept → session
  row links proposal w/ correct role mapping + scheduled_at + 2 emails
  + 2 .ics files, ics escaping/folding, A4 scheduled-sweep. Suite 226
  passed ×2. **.ics validator: parsed by the `icalendar` 7.2.0 library**
  (dev-only install, like pytest/httpx — NOT in requirements.txt) +
  structural asserts (CRLF, ≤75-octet lines, METHOD/UID/DTSTART)
- Browser evidence (Playwright MCP, two tabs): Alice visits /room/
  bob-dev → intersection panels + Propose modal (message + time) →
  "Proposed ✓" → Bob's nav badge "1", inbox shows proposal w/
  localized time pills → picks time → Accept → redirected to
  /session/314. SQL: proposal 16 accepted, session_id=314,
  interviewer=1/candidate=2, scheduled_at Jul 14 15:30 → .ics
  DTSTART 20260714T193000Z / DTEND 20150Z+45min, folded DESCRIPTION.
  Emails: 2×.txt + 2×invite.ics in output/emails/. Shot:
  output/evidence/p8-bob-inbox.png
- Commits: 7ee8fec (P8 feature) · af6841a (A4 sweep + test isolation)

## Done — Phase 7 (2026-07-12)

## Done — Phase 7 (2026-07-12)
- `webapp/repositories/feedback.py` — draft validation against the
  session's template (unknown ids/out-of-range 400), A5 grade = 5·Σp/Σmax
  (Decimal, half-up to 1 dp), save_draft upsert guarded by
  `WHERE finalized_at IS NULL` (a racing finalize can't be overwritten),
  finalize as ONE transaction under FOR UPDATE: debrief+interviewer
  check → grade (override or computed) + finalized_at → burned insert →
  queue_want delete → state='finalized' (edge deliberately outside the
  generic /state endpoint, as practice_states documents). is_burned for A6
- `webapp/routes/practice_feedback.py` — GET/PUT /rubric (interviewer
  only; PUT allowed until finalize, incl. pre-call prep; 409 after),
  POST /finalize (optional grade override, pydantic 0–5 → 422 outside),
  GET /feedback (both participants, 409 pre-finalize; payload = grade,
  per-item breakdown w/ labels, notes_md, reveal timeline, case link).
  A6 in POST /api/practice: burned case for candidate → 409
- Frontend: `rubric.js` RubricPanel — in-call left drawer (mutually
  exclusive w/ PDF drawer), 800 ms debounced autosave w/ Saved ✓ + live
  draft-grade, debrief editor w/ prefilled editable grade + two-click
  armed Finalize; renderFeedbackView (grade hero, per-item bars, notes,
  timeline, PDF link). session.js boot branches: debrief → editor/
  waiting (candidate polls 15 s and auto-flips), finalized → feedback
  view, aborted → notice; no media/WS in post-call states. exhibits.js:
  interviewer panel now shows with 0 exhibits (hosts PDF/Rubric btns),
  timeline extracted as standalone renderRevealTimeline
- Tests: tests/test_feedback.py (4 tests: role gating + draft
  persistence + preview math 18/25→3.6; validation 400s; full finalize
  transaction incl. burned row, queue_want removal, released payload,
  read-only draft, double-finalize 409, A6 409 + per-candidate scope;
  debrief-requirement + override range). Suite 218 passed ×3 total runs
- Browser evidence (Playwright MCP, session 206, two tabs, nomedia):
  rubric drawer filled → "Saved ✓, draft 3.6/5" → interviewer reload
  mid-live → all five scores + notes restored (draft survives reload ✓)
  → Send exhibit → End call → debrief editor grade prefilled 3.6,
  timeline "0:52 Exhibit 1" → candidate End → waiting note, GET
  /feedback 409 pre-finalize → armed confirm "Confirm 3.6 / 5" →
  interviewer flips to released view → candidate auto-flips ≤15 s (poll)
  → candidate reload boots straight into feedback view w/ PDF link →
  A6 fetch: new session on burned case → 409 "burned for the candidate".
  DB: state=finalized · grade 3.6 · finalized_at set · burned_via=206 ·
  want_queue_cleared=t. Shot: output/evidence/p7-candidate-feedback.png
- Dev-data hygiene: evidence sessions 105/206 deleted + dummy case
  unburned afterwards, so A6/DV-13 don't wedge future dev sessions on
  the single seeded case
- Spec's P7 done-when "candidate PDF 403 pre-finalize" is impossible
  here by DV-5 (repo serves all PDFs to any authed user; no new gate
  added, none removed) — the release gate is enforced on FEEDBACK
  instead (409→200 evidenced above)
- Commits: c0cbe73 (backend) · 3b8d2d1 (frontend) · ce4c877 (evidence)

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
