# PROGRESS
Updated: 2026-07-15T15:30:00-04:00 · Branch: **feature/caseroom** (the iOS chain merged into it). iOS P3 (remote WebRTC media) built + reviewed + **merged**; on-device call test paused mid-way (see handoff). Fuller P3 detail in the "P3 (remote WebRTC media) — DONE · HANDOFF" section further down.

## SESSION HANDOFF — 2026-07-15 (P3 merged into feature/caseroom; device call test PAUSED)

### Verified state (commands run at handoff, not recalled)
- On **`feature/caseroom` @ `2a2302e`**, working tree clean. `git merge --ff-only feature/ios-p3` fast-forwarded caseroom `b37bc0c → ae41550`; then commit `2a2302e` (test fix, below). **69 commits ahead of `origin/feature/caseroom` — NOT pushed** (Thomas pushes). `feature/ios-app`/`ios-p2`/`ios-p3` are now ancestors of caseroom (redundant; safe to delete when wanted).
- Backend `pytest tests/` = **311 passed / 1 failed**. iOS `xcodebuild test iPhone 17` = **155 passed / 0** (at `d02752d`; iOS code unchanged since — later commits are docs/backend-test only).
  - The 1 backend failure is **`test_api_v1_sessions.py::test_dashboard_shape`** — a PRE-EXISTING non-hermetic test (predates P3), NOT a code defect: the dashboard "next session" query returns an ACCUMULATED dev scheduled-session (id 2547) that sorts before the test's freshly-created one (RHS changes every run: 2547 != 2682). Passes on a clean DB. Fix = make the test hermetic (scope/clean the user's other upcoming sessions) — a follow-up, session-model tier.
- **TURN verified working:** `.env` has `TURN_PROVIDER/TURN_KEY_ID/TURN_TOKEN` (Cloudflare, gitignored); `mint_turn_credentials(load_settings())` mints real short-lived stun/turn/turns creds. Source txt: `mycase/Cloudflare Turn Credentials.txt` (plaintext secret — Thomas should delete it; not in any git repo).
- **Dev server RUNNING:** `nohup python main.py serve --host 0.0.0.0 --port 8077` (pid was 70355), reachable at `192.168.0.200:8077` (LAN) + localhost. Stop with `pkill -f "main.py serve"`.

### What happened this session
- Merged the iOS chain into `feature/caseroom` (fast-forward, local, not pushed) at Thomas's request.
- Put the Cloudflare TURN creds into `.env` and proved they mint real relay creds.
- Started the on-device call test (same-WiFi LAN) but **PAUSED it**: Thomas hit "no camera/mic permission popup" in **Safari-mobile on iPhone**. ROOT CAUSE (not a bug): browser `getUserMedia` requires a **secure context (HTTPS)** — allowed only over HTTPS or `localhost`. Safari on the iPhone at `http://192.168.0.200:8077` (LAN IP, plain HTTP) is insecure → the page can't request camera/mic → no popup. macOS firewall is OFF (not the cause).
- Fixed a test I broke by adding TURN to `.env`: `test_turn.py` STUN-only test now overrides settings instead of reading ambient env (commit `2a2302e`).
- The 3 temporary LAN-test edits (project.yml/Info.plist API_BASE_URL → LAN IP; RemoteMediaSession forceRelay → true) were **REVERTED**; `.xcodeproj` regenerated to the committed config.

### Handoff partition
| Chunk | Spec state | Tier | Next concrete action |
|---|---|---|---|
| Resume the on-device remote call test (item 3) | complete | Thomas (+ worker to set up tunnel) | NOTE: the 2 temp LAN edits are currently REVERTED (tree clean) — Path A RE-APPLIES them. Pick a path: (A) NATIVE iOS app over LAN — no HTTPS needed (native camera perms), build in Xcode, sign BOTH `CaseRoom` + `CaseRoomWidgets` targets with Thomas's team, re-apply `ios/project.yml` API_BASE_URL→`http://192.168.0.200:8077` + `RemoteMediaSession.swift` forceRelay→true, `xcodegen generate`, ⌘R; OR (B) `brew install cloudflared` → `cloudflared tunnel --url http://localhost:8077` → open the https URL in Safari-mobile (and/or point the app at it for a true CELLULAR test). Then verify: remote video renders both ways, video-off, camera-dot-off after finalize, call routes through Cloudflare TURN. |
| Push feature/caseroom | complete | Thomas | `git push origin feature/caseroom` when ready (69 commits ahead; I never push). |
| Apple portal + APNs .p8 | manual | Thomas | App ID `studio.ogee.caseroom` + Push (+Time-Sensitive) capability; `.p8` → `.env` (`APNS_*`). Only needed for Live Activity push UPDATES + notifications — NOT the core call. |
| Make test_dashboard_shape hermetic | needs-spec | session-model | Decide the fix: scope the dashboard "next session" query in the test to the user's freshly-created session, or clean the user's other upcoming sessions in setUp. Non-hermetic against shared dev DB; not P3 code. |
| Execute P4 | complete (roadmap) | session-model → worker | P4 = Foundation-Models drills, widgets, App Intents/Entities, "free now" instant-match. Plan not yet written (brainstorm/writing-plans first). |

### Gotchas learned this session (not already in the repo)
- **Browser media needs HTTPS on a phone.** getUserMedia is blocked over http://LAN-IP on iPhone Safari (no secure context, no popup). Use a tunnel (https) for Safari-web/cellular, OR the NATIVE app (uses native AVFoundation perms, not getUserMedia — works over http-LAN with `NSAllowsLocalNetworking`).
- **Adding real TURN_* to .env breaks env-dependent tests.** `test_turn.py`'s STUN-only test read ambient env — fixed to override `app.state.settings`. Watch for the same pattern elsewhere.
- The final adversarial review's 6 real-device fixes (Unified-Plan remote track, 1.2Mbps cap, ICE restart, finalize broadcast+LA-end, media teardown, timestamp truncation) are CODE-verified but only truly proven on the (paused) device test — see the P3 HANDOFF section's "Known real-device RISKS".

## Now — TWO parallel tracks. Route by what Thomas asks for; if the
session prompt doesn't say, ASK which track before touching anything.
- WEB track (this branch, feature/caseroom): phases 1–10 done + brand
  complete. P11 T11.1 verify script DONE (2026-07-14). P11 guide rule-05
  polish DONE (2026-07-14, commit 872d1e7 — favicon + swept votes/PDF/
  back-arrow; theme toggle reverted to sun/moon per owner, b9097db).
  P11 T11.2 cross-browser DONE (2026-07-14 — real Chrome 149 ↔ Safari 27
  call, all 4 legs pass; findings CB-1..4 in INTEGRATION.md §9; knock-race
  bug CB-2 fixed in session.js). P11 T11.3 failure-mode DONE (2026-07-14 —
  candidate-reload + server-restart PASS; wifi/ICE-restart not reproducible
  on one Mac (loopback); finding FM-1 hub-state-loss on restart; §10). P11
  T11.5 housekeeping DONE + follow-up fixes CB-3 (recording keepalive,
  329d959), FM-1 (hub rebuild admitted from DB, b3c0508) SHIPPED; suite 235
  green. Branch **pushed to GitHub 2026-07-14** (origin/feature/caseroom @
  5b0e782; Baggs99/Case-Repo-App-Experience). NOW: owner call — **no prod
  deploy yet, just uploaded to GitHub for later deployment**, so T11.4
  DEPLOY.md is DEFERRED (still needs O1 host + O2 TURN when it happens).
  Web build otherwise complete. Open decisions (usefulness-color, O1–O3,
  demo-case deletion, rubric-editor spec). Full table: "Handoff partition (web track)".
- iOS track (branch feature/ios-app off feature/caseroom):
  approved spec docs/superpowers/specs/2026-07-12-caseroom-ios-app-design.md,
  P1 plan docs/superpowers/plans/2026-07-12-caseroom-ios-app-plan.md.
  Task 9 (XcodeGen scaffold + Info.plist keys) DONE, commits e9391bd/431647e.
  Task 10 (networking layer: Models/APIClient/SessionStore/LoginView) DONE
  2026-07-14, commit affea8b — 15/15 xcodebuild tests pass (8 URLProtocol-
  stub + 7 real-fixture decode; fixtures under ios/CaseRoomTests/Fixtures/);
  custom `.custom` date-decoding strategy verified against real
  fractional-seconds backend output (sessions_recent.json fixture: `ended_at:
  "2026-07-14T03:48:00.927225-04:00"`). Two fixtures (proposals,
  sessions_upcoming) came back empty for the seeded user — decode-tested as
  empty arrays, not a code gap. Full report: .superpowers/sdd/task-10-report.md.
  **Task 15 (P1 capstone: end-to-end verification) DONE 2026-07-14** — P1 is
  COMPLETE. Backend suite 269 passed, iOS suite 36 passed, live backend
  E2E (8 HTTP calls: 7 GET + 1 proposal POST) all 2xx, 5/5 simctl push
  kinds delivered with no crash. Full evidence: "P1 (iOS app) — DONE"
  section below.
  **P2 (in-person session core) DONE 2026-07-14** (branch `feature/ios-p2`,
  commit `2529a93` + this PROGRESS.md commit) — backend suite 290 passed,
  iOS suite 112 passed, and a full live in-person-flow E2E over real HTTP +
  WebSocket (pairing→consent→live→reveal→rubric→debrief→finalize→history,
  all steps PASS incl. a real AES-GCM decrypt of the revealed exhibit).
  Full evidence: "P2 (in-person session core) — DONE" section below and
  .superpowers/sdd/task-15-report.md. Next: **P3 — remote WebRTC media +
  Live Activities + TURN provider decision**.

## P3 (remote WebRTC media) — DONE (2026-07-14) · HANDOFF
Supersedes the P1+P2 HANDOFF below. **iOS P3 built + fully reviewed on branch
`feature/ios-p3` (off `feature/ios-p2`), NOT pushed — Thomas merges.**
Executed subagent-driven (SDD): all 12 tasks TDD'd + per-task reviewed; Tasks 6
and 8 each took an adversarial-review fix cycle (see below). Plan:
`docs/superpowers/plans/2026-07-14-caseroom-ios-p3-remote-media-plan.md`.

### Verified state (commands run this session)
- Branch tip **`d02752d`** (16 commits off `feature/ios-p2`). Backend suite
  `pytest tests/` = **312 passed / 0 failed**. iOS suite `xcodebuild ...
  -destination 'platform=iOS Simulator,name=iPhone 17' test` = **155 passed /
  0 failed (TEST SUCCEEDED)**.
- Migrations through **016**. Dev-DB test pollution reset at session start
  (sessions 2192/2193 + burned row purged — the non-hermetic-suite issue).

### Final whole-branch review (adversarial, 4-dimension) — 6 findings, ALL FIXED
A final adversarial review over the whole branch caught 6 Critical/Important
defects invisible to the config-only unit suite (all real-device-only in
effect). All fixed + re-reviewed clean (backend `f2810d9`, iOS `d02752d`):
- **CRITICAL** remote video never surfaced — the remote-track delegate was
  Plan-B `didAdd stream:` but the PC is Unified Plan (never fires). Fixed:
  Unified-Plan `didAdd rtpReceiver:streams:` (signature confirmed vs the WebRTC
  header). Without this the whole call would have shown a black remote view.
- No 1.2 Mbps outbound video cap (rtc.js/spec §1) → uncapped cellular uplink. Fixed.
- Empty ICE-state stub → no ICE restart; a cellular blip killed the call. Fixed
  (restartIce on failed / 3s-grace on disconnected).
- Finalize sent no `broadcast_session_update` + no Live-Activity `end` push →
  candidate stuck on debrief + stale lock-screen banner. Fixed.
- Media torn down only on view-disappear → camera/mic streamed through the
  debrief grading phase (privacy/battery). Fixed (teardown on leaving `live`).
- Live-Activity timer parsed microsecond timestamps with a fractional-blind
  formatter → timer never rendered. Fixed (truncate sub-seconds server-side).

### What shipped
- **Phase A (backend):** session `mode` col (migration 015 `remote|in_person`,
  exposed in join-config + session detail); short-lived TURN credential minting
  (`webapp/turn.py`, **Cloudflare** provider, STUN-only degrade); `/join-config`
  merges STUN+TURN for remote sessions only (handler now async +
  `run_in_threadpool`).
- **Phase B (iOS media):** WebRTC via SPM **`stasel/WebRTC` pinned 150.0.0**
  (Package.resolved force-committed; the one sanctioned heavy dep — OD-1);
  `RTCPeerConnectionWrapper` behind a framework-neutral `MediaTransport`;
  `Negotiator` mirroring `rtc.js` perfect negotiation byte-for-byte
  (polite=candidate; collision/ignoreOffer; sdp/ice over the existing signaling
  WS); camera/mic capture (`WebRTCMediaCapture`) + `VideoCallView` (remote
  full-screen + local PIP + mute/cam); wired into the session screen for
  `mode=='remote'` only (in-person stays media-free), video-off = audio-only.
- **Phase C (Live Activities):** backend ActivityKit push-token registration
  (migration 016 `live_activity_tokens`, `POST /api/v1/live-activity`) + update
  pushes on state change (reuses P1 APNs, `liveactivity` push type); iOS Live
  Activity widget (`CaseRoomWidgets` extension) — lock-screen banner + Dynamic
  Island, lobby countdown / live elapsed timer rendered CLIENT-SIDE.

### Review catches (fixed this session)
- **Task 6 CRITICAL threading race:** WebRTC delegate callbacks fire on a bg
  thread; `makingOffer` was set late (glare race) + `sendICE` crossed into the
  `@MainActor` signaling client off-thread (data race). Fixed: marshal delegate
  callbacks to main + set `makingOffer` synchronously (`0fb1024`); + `@unchecked
  Sendable` TrackHandle for the safe delegate→main track handoff (`417c4d2`).
- **Task 8 Important:** video-off toggle was dead VM code (UI toggled a separate
  unsynced `@State`) → routed through the VM as single source of truth; also
  closed a wrapper leak on capture-start failure + surfaced media-start errors
  with retry (`e16a6cb`).

### ⚠️ THOMAS — manual, in order (P3 not done-done until these pass)
1. **OD-2 TURN provider (Cloudflare Calls default):** create the account/key,
   put `TURN_KEY_ID` + `TURN_TOKEN` (and optional `TURN_PROVIDER=cloudflare`)
   in `.env`. Required before real-device CELLULAR testing (a same-LAN/sim
   session works STUN-only). Alternatives if you veto: self-hosted coturn (VPS
   ~$5/mo) or Twilio — code implements Cloudflare only.
2. **Carried from P1 (still open):** Apple portal App ID `studio.ogee.caseroom`
   + Push (+ Time-Sensitive) capability, APNs `.p8` → `.env` — needed for real
   push (incl. Live Activity updates) on a device.
3. **Real-device verification (the phase's "done when"):** iPhone (on CELLULAR,
   not wifi) ↔ desktop-web run a full remote case → both see/hear each other,
   video-off toggles audio-only, the Live Activity shows in the Dynamic Island,
   finalizes into history. Also verify **QR-pair + room-mic** from P2 (no sim
   camera).
4. **Merge the branch chain (Thomas merges):** `feature/ios-app` →
   `feature/ios-p2` → `feature/ios-p3`.

### Known real-device RISKS to watch (unit tests can't reach these)
- **Perfect-negotiation rollback:** the polite side's implicit rollback via
  `setRemoteDescription(offer)` during a collision assumes native libwebrtc
  supports implicit rollback like browsers. Documented in `Negotiator.handleSDP`.
  If a real-device call deadlocks at start (glare), an explicit
  `setLocalDescription(rollback)` on the polite path is the fix.
- **App Store size:** the WebRTC binary adds tens of MB — note for submission.

### Owner sign-off pending (non-blocking, defaults applied)
- Live Activity has **no periodic server push**; the elapsed/countdown timer
  renders client-side (idiomatic ActivityKit; the plan's "periodic timer" prose
  was interpreted this way). Confirm this is the desired behavior.

### Carried Minors (final-cleanup sweep — none blocking)
- `turn.py` normalization assumes Cloudflare `urls` is a list, not a bare string
  (cheap 1-line hardening; only bites on real Cloudflare).
- `live_activity_tokens.delete_token(push_token)` unscoped vs the codebase's
  `token+user_id` convention.
- `VideoCallView.swift` docblock stale after its init-signature change (CLAUDE.md
  header rule). Fresh `ISO8601DateFormatter` per widget render. `ContentState`
  marked `public` inconsistently. join-config test stub JSON omits the `mode` key.

### Next: **P4 — Foundation-Models drills, widgets, App Intents/Entities, "free
now" instant-match** (session-spine roadmap P1→P2→P3 done → P4).

---

## HANDOFF — P1+P2 (2026-07-14, superseded by the P3 section above)
Three iOS phases now exist:
**P1 DONE · P2 DONE · P3 PLANNED (not started).**

### Verified state (re-checked with commands THIS session — not recalled)
- **Branch chain (NOT pushed — Thomas merges in order):**
  `feature/caseroom` (web, b37bc0c) → `feature/ios-app` (P1; tip 084c0de is
  the P2-plan doc commit, P1 CODE ends at 4a74d8e) → `feature/ios-p2` (P2;
  tip 1816c33 is the P3-plan doc commit, P2 CODE ends at a7a97fe). `git log`
  confirms lineage; working tree clean.
- **Plans (all committed):** docs/superpowers/plans/2026-07-12-caseroom-ios-app-plan.md
  (+ .RECON.md), 2026-07-14-caseroom-ios-p2-session-core-plan.md,
  2026-07-14-caseroom-ios-p3-remote-media-plan.md. Migrations through 014.
- **Tests were GREEN on these exact commits this session:** backend **290**,
  iOS **112** (Task 15 capstone AND both final whole-branch reviews ran them
  green independently). All 30 tasks (P1×15, P2×15) were TDD'd + individually
  reviewed; both final whole-branch reviews returned **READY TO MERGE**.
- ⚠️ **CURRENT `pytest tests/` = 6 failed / 284 passed — VERIFIED this is
  dev-DB DATA POLLUTION, NOT a code regression.** 5 failures are
  `409 "This case is burned for the candidate"`; 1 is a row-count assertion
  (`2192 != 2349`). Root cause (verified): `is_burned` reads the `burned`
  table; `finalize` permanently INSERTs a `burned` row; this session's live
  E2E runs + repeated suite runs accumulated `burned` rows for the seeded
  candidate on shared dev cases. **The suite is not hermetic against the
  shared dev Postgres.** Clearing the pollution is EXPECTED to restore green
  but is **UNVERIFIED** — the cleanup DELETE was blocked by the sandbox this
  session.

### Handoff partition
| Chunk | Spec state | Tier | Next concrete action |
|---|---|---|---|
| Reset dev-DB test pollution | complete | worker | With DB-write permission: `export $(grep -E '^DATABASE_URL=' .env \| xargs); psql "$DATABASE_URL" -c "DELETE FROM burned;"` then delete the E2E finalized session id 2193 (feedback/reveals/recordings/practice_sessions rows), then `.venv/bin/python -m pytest tests/ -q` → expect ~290 green. |
| Harden test hermeticity (follow-up) | needs-spec | session-model | Decide: make finalize-touching tests (`test_ws_integration.py` + the count test) clean up their `burned` rows in tearDown, OR run the suite against a per-run fresh DB. Ambiguous → session-model. |
| Merge branch chain | complete | Thomas | Merge `feature/ios-app` → `feature/ios-p2` → (later) `feature/ios-p3`. |
| Execute P3 (remote WebRTC media) | complete (plan) | session-model → worker | FIRST resolve the plan's OWNER DECISIONS **OD-1** (iOS WebRTC framework) + **OD-2** (TURN provider) — session-model. THEN subagent-driven per the P3 plan: backend Tasks 1–3 = worker; iOS media Tasks 5–10 = worker once OD-1 is set. |
| Apple portal .p8 → .env (real push) | manual | Thomas | Carried from P1; not blocking sim/backend work. |
| Real-device P2/P3 manual checks | manual | Thomas | P2: QR scan + room-mic (no sim camera). P3: iPhone↔desktop video over cellular (needs OD-2 TURN key). |

### Gotchas learned this session (not recorded elsewhere in the repo)
- **Non-hermetic tests + shared dev Postgres:** running the suite / the E2E
  FINALIZES sessions, which inserts permanent `burned` rows for the seeded
  users; enough accumulation makes `test_ws_integration.py` + a count test
  fail with data-shaped 409s. Reset `burned` (+ stray finalized sessions)
  before ever trusting a red suite as a code regression.
- **iOS-build subagents sometimes BACKGROUND `xcodebuild`** and return a
  non-terminal "waiting" message without committing. Verify (`git log`, no
  running xcodebuild), then resume the agent instructing it to run the build
  in the FOREGROUND and commit — do NOT assume it committed.
- Recon-verified P2/P3 interface names (WS message shapes, `/api/practice/*`,
  `rtc.js` perfect-negotiation candidate=polite/interviewer=impolite,
  `ice_servers`/`join-config`, session `mode` is MISSING and added by P3
  Task 1) live in the P2/P3 plans' "Verified existing interfaces" blocks —
  re-verify if backend files change before P3 execution.
- `/api/practice/*` endpoints are native-compatible (cookie +
  `require_same_origin` passes on a missing Origin header) — the iOS session
  screen reuses them directly; no `/api/v1` mirror needed.
- P3 has TWO consequential owner decisions that GATE tasks (full options +
  tradeoffs in the P3 plan's "⚠️ Owner decisions" block at the top):
  **OD-1 = iOS WebRTC framework** — default: the `WebRTC` Swift-Package
  binary (the one unavoidable heavy ~30–70 MB dependency; there is no
  dependency-free real-time-media option). Gates P3 Task 5.
  **OD-2 = TURN provider** — default: Cloudflare Calls TURN (free tier, no
  server ops; alternatives: self-hosted coturn on a VPS, or Twilio). Gates
  P3 Tasks 2–3 and needs `TURN_*` in `.env` before real-device cellular
  testing. Both have recommended defaults, so P3 execution CAN proceed on
  the defaults if Thomas doesn't override — but confirm with him first since
  each is a real dependency/cost commitment.

## P1 (iOS app) — DONE (2026-07-14, Task 15 capstone verification)

Branch `feature/ios-app`, commit `3ea8dc2` (Add Today and You tabs) plus
this PROGRESS.md commit. Full evidence + curl/simctl output:
`.superpowers/sdd/task-15-report.md`.

- **Backend suite** — `.venv/bin/python -m pytest tests/ -q` → **269
  passed**, 0 failures (238 pre-existing deprecation warnings only).
- **iOS unit suite** — `cd ios && xcodegen && xcodebuild -project
  CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS
  Simulator,name=iPhone 17' test` → **36 tests, 0 failures** (APIClient 17,
  CasesViewModel 3, PushRoute 9, SessionsViewModel 3, Smoke 1,
  TodayViewModel 3).
- **Live backend E2E via HTTP** (`main.py serve --port 8077`, seeded via
  `scripts/seed_caseroom_dev.py`; a@yale.edu=uid 1, b@yale.edu=uid 2):
  login as a → `/api/v1/me`, `/cases?limit=3`, `/cases/358`, `/proposals`,
  `/sessions?scope=upcoming`, `/sessions?scope=recent`, `/dashboard` — all
  **200** with expected keys. Login as b → `POST /api/proposals`
  (`to_user_id:1, case_id:358, from_role:candidate`) → **200**, proposal id
  164 created pending. No push log line: expected, `push_enabled` is False
  with no `APNS_*` env set (dev); fan-out logic covered by
  `tests/test_push_events.py` (in the 269).
- **Push delivery smoke** — built + installed CaseRoom.app on iPhone 17
  sim (bundle `studio.ogee.caseroom`), launched it, then `xcrun simctl
  push booted studio.ogee.caseroom -` for all 5 kinds (proposal w/
  proposal_id 164; accepted/knock/feedback/starting_soon w/ session_id
  1012) → **5/5 accepted** (`Notification sent...`, exit 0), app process
  still alive after all 5 (no crash).
- Cleanup done: sim app terminated, simulator shut down, dev server
  killed, port 8077 confirmed free.

### Remaining / manual (not blocking — P1 is otherwise complete)

(a) **Thomas**: Apple Developer portal — register App ID
`studio.ogee.caseroom` with Push Notifications (+ Time-Sensitive)
capability, generate an APNs `.p8` key, put paths/ids into `.env`
(`APNS_KEY_PATH`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`,
`APNS_USE_SANDBOX=1`).
(b) Real-device push test (needs (a) plus a physical iPhone on a free
provisioning profile for install; push itself needs the paid account).
(c) Interactive UI walkthrough (login → 4 tabs → Cases search/detail →
send proposal as b → accept as a → calendar event → web dashboard shows
same session, no fork) — not automated this pass per the watchdog rule
against flaky sim tap-through; exact steps were in the P1-era
`.superpowers/sdd/task-15-report.md` (that file now holds the P2 capstone
report instead — each phase's Task 15 reuses the same report path; see
"P2 (in-person session core) — DONE" below for the current one).
(d) Prod deploy — deferred, same as the web track (no host/TURN decision
yet, see "Handoff partition (web track)").
(e) DONE 2026-07-14: P2 (session core — WS lobby/knock/admit, exhibit
decrypt, WS key-reveal, rubric/timer, recording upload, QR pairing) shipped
and verified — see "P2 (in-person session core) — DONE" below.

## P2 (in-person session core) — DONE (2026-07-14, Task 15 capstone verification)

Branch `feature/ios-p2`, commit `2529a93` (Add QR pairing: create
(interviewer) + scan-to-claim (candidate)) plus this PROGRESS.md commit.
Full evidence: `.superpowers/sdd/task-15-report.md`.

- **Backend suite** — `.venv/bin/python -m pytest tests/ -q` → **290
  passed**, 0 failures (279 pre-existing deprecation/SWIG warnings only, no
  flake — single run).
- **iOS unit suite** — `cd ios && xcodegen && xcodebuild -project
  CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS
  Simulator,name=iPhone 17' test` → **`** TEST SUCCEEDED **`, 112 tests, 0
  failures** (24.5s) — SessionViewModel (admit/knock/consent/recorder-
  lifecycle), SignalMessage (outbound JSON + inbound parse incl. reveal/
  session-update), Today/Sessions/Cases/APIClient/PushRoute/Smoke suites.
- **Live in-person flow E2E over real HTTP + WebSocket** (new script
  `tests/e2e_inperson_flow.py`, kept in the repo; `main.py serve --port
  8077` against the dev seed, case 1 "Dev Dummy Case" which already had 2
  exhibits + a default rubric template from prior dev/test use — no
  fixture seeding needed): interviewer `pair/create` → token (200) →
  candidate `pair/claim` → session_id (200) → both open
  `/ws/practice/{id}` and get correct roles → `state:lobby` → both
  `consent` → `state:live`, each step producing a `session-update` WS
  frame on **both** sockets (proves the candidate socket advances live,
  not just the HTTP response) → `POST /reveals` (200) → candidate's WS
  received `{"type":"reveal","exhibit_id":216,"key_b64":...}` and the key
  + manifest IV **actually decrypted** the fetched exhibit-blob via
  `webapp.exhibit_crypto.decrypt_exhibit` back to its original WebP bytes
  (RIFF magic intact) → `PUT /rubric` (5 template items scored, 200,
  `grade_preview:5.0`) → `state:debrief` (200 + session-update both sides)
  → `finalize {grade:null}` → `finalized:true`, server-computed
  `grade:5.0` → the finalized session then appeared in the candidate's
  `/api/v1/sessions?scope=recent` history. Every step PASS; full transcript
  in the report. Server stopped after the run, port 8077 confirmed free.
- **Optional simulator smoke** — built (`xcodebuild ... build` →
  **BUILD SUCCEEDED**), installed, and launched `studio.ogee.caseroom` on
  the iPhone 17 sim: process stayed alive (no crash-relaunch), no new
  DiagnosticReports. Only proves boot-to-root-view; does not exercise QR
  scan or the session flow. Simulator shut down afterward.

### Remaining / manual (not blocking — P2 is otherwise complete)

- **Real-device QR-scan walkthrough** — `DataScannerViewController` needs a
  camera; no simulator equivalent.
- **Real-device room-mic capture check** — live in-person recording needs a
  physical mic.
- **Interactive 2-device walkthrough** (two physical iPhones, or sim + real
  device, through the full claim→lobby→consent→live→reveal→rubric→debrief→
  finalize UI) — not automated this pass per the watchdog rule against
  fragile 2-sim UI tap-through; the HTTP/WS E2E above proves the backend
  contract the UI drives, not the SwiftUI views/gestures/VisionKit layer.
- **Still open from P1**: Apple Developer portal App ID Push (+
  Time-Sensitive) capability + APNs `.p8` → `.env` for real push; merge
  `feature/ios-app` (P1) then `feature/ios-p2` into the base branch.

Next: **P3 — remote WebRTC media + Live Activities + TURN provider
decision** (spec P3 section: WebRTC audio/video for remote sessions, the
video-off remote toggle, Dynamic Island/Live Activities, and the TURN
provider owner decision — the `sdp`/`ice` WS relay already exists in the
signaling hub but has stayed unused through P2).

WEB TRACK — verified state at session end (2026-07-12 ~14:30 ET, all
checked by command, not memory):
- branch feature/caseroom @ a8968e5, `git status` clean
- `pytest tests/ -q` → 234 passed (fresh run at handoff time)
- dev server RUNNING on :8077 (curl /login → 200); restart with
  `pkill -f "main.py serve"; cd ~/dev/Case-Repo-App-Experience &&
  nohup .venv/bin/python main.py serve --port 8077 >
  output/devserver.log 2>&1 & disown`
- dev DB: 8 cases (id 1 dummy + demo 354–360), 0 stale scheduled
  sessions; demo-removal SQL in the "unnumbered + demo data" section
- spec phases 1–10 of 11 DONE (evidence per phase in sections below);
  whole app on the myCase brand; browse tiles final form = transparent
  square tiles w/ full hairline outline (commit a8968e5)
- 26 evidence screenshots in output/evidence/ (gitignored)

## Handoff partition (web track, written 2026-07-12)
| Chunk | Spec state | Tier | Next concrete action |
|---|---|---|---|
| P11 T11.1 verify script | ✅ DONE 2026-07-14 — script committed, ran clean (exit 0), 13 advisory hits all JUSTIFIED (details in "Done — Phase 11 T11.1") | — | — |
| P11 T11.2 cross-browser Chrome+Safari | ✅ DONE 2026-07-14 — real Chrome 149 ↔ Safari 27, all 4 legs pass (call/reveal/recording/authoring). Findings CB-1..4 in INTEGRATION.md §9: CB-1 Safari 27 records webm not mp4 (mp4 fallback now dead code); CB-2 knock-race FIXED (session.js re-knock on peer-joined); CB-3 interviewer recording completed=f on immediate-navigate (TO FIX, keepalive); CB-4 stale-page "not joinable" (minor) | — | CB-3 + CB-4 are follow-up fixes (not blocking) |
| P11 T11.3 failure-mode pass | ✅ DONE 2026-07-14 (session 1012, INTEGRATION.md §10): candidate-reload/P6 reconciliation PASS; signaling-server restart PASS (WS reconnect + media survived) w/ finding FM-1 (process-local hub loses `admitted` on restart → spurious admit prompt + sdp/ice relay gated until re-admit); wifi-drop/ICE-restart NOT reproducible on one Mac (P2P on loopback) — ICE-restart code path confirmed wired (rtc.js:75-81) | — | FM-1 is a prod-hardening follow-up (rebuild admitted from DB on WS connect) |
| Guide rule-05 polish: staircase favicon + Lucide icon sweep | ✅ DONE 2026-07-14 — commit 872d1e7 (favicon + swept votes/PDF/back-arrow). Theme toggle briefly went to a text label; **owner reverted it to sun/moon** (commit b9097db) — the icon stays as the documented rule-05 exception. Nothing outstanding. | — | — |
| Rubric-template editor UI (deferred since P5) | needs-spec (which fields, who may author, where it lives) | session-model | Draft 10-line spec w/ Thomas, THEN implement (generic template already works server-side) |
| Usefulness % color calming | needs-decision (owner flagged it as loudest remaining color; no call made) | Thomas → worker | If yes: mute emerald/amber/rose usefulness text in _search_results.html + case_detail to the calm band |
| Owner decisions O1 (prod host/deploy), O2 (TURN), O3 (consent copy) | needs-decision | Thomas | Answers unblock deploy runbook (T11.4-ish) and real launch |
| Demo cases 354–360 keep-or-delete | needs-decision | Thomas | Delete SQL recorded in "unnumbered + demo data" section |

Web-track gotchas (this session, not recorded elsewhere):
- Dev server has NO reload — after ANY backend/template change, restart
  it (command above) or you'll debug phantom stale behavior (bit twice
  this session: P9 dashboard panels, P10 routes).
- Tailwind CDN recompiles after a JS theme toggle — screenshots taken
  immediately after toggling can show pre-recompile colors. Trust
  getComputedStyle checks, not pixels, right after a toggle.
- The two design HTMLs in mycase/ are React bundles: decode
  `<script type="__bundler/template">` JSON for markup; brand tokens
  verbatim in the guide's Implementation-spec section.
- Browser-automation two-user trick: same Chrome, tab A localhost /
  tab B 127.0.0.1 = separate cookie jars. `?nomedia=1&debug=1` gives an
  oscillator mic (records for real) + window.__caseroom debug hook.
  element.click() via evaluate is NOT a user gesture (AudioContext).
- Playwright-MCP screenshots save to the CWD of the MCP server
  (~/Documents/Projects/mycase) — move them to output/evidence/.
- httpx, pytest, icalendar are dev-only in .venv, deliberately NOT in
  requirements.txt.
- .venv one-off scripts touching the DB must init_pool first (see any
  seeding snippet in the Done sections); pool-shutdown warnings on exit
  are harmless.

## Done — Phase 11 T11.5 housekeeping + CB-3/FM-1 fixes (2026-07-14)
- T11.5: TODO/stub sweep of CaseRoom code — only real hit was a stale
  docstring calling `ResendEmailSender` a "TODO stub … uncomment below" when
  it's fully implemented (Phase 8); corrected (commit 7566b32). All other
  `placeholder`/`stub` matches are legit HTML/CSS. Commit log clean.
- CB-3 FIXED (329d959): `/recordings/complete` POST now `{keepalive:true}` so
  the completion marker survives page unload (was leaving interviewer
  recording `completed=f`). Not on chunk POST (keepalive ~64 KB body cap).
- FM-1 FIXED (b3c0508): WS route passes `admitted=(state=='live')` to
  `hub.connect()` so a reconnect after a server restart rebuilds the admit
  from the DB (no spurious admit prompt, no relay gate). Test added.
- Suite **235 passed** (was 234 + the FM-1 test). Dev server restarted onto
  the fixed code.
- Dev-data hygiene: session 1012 was finalized during the T11.3 wrap-up, which
  burned candidate b(2) on case 1 and broke the ws-integration tests (A6 409);
  cleared that burn (`DELETE FROM burned WHERE user_id=2 AND case_id=1`).
  Throwaway T11.2/T11.3 sessions 983/984/1012 still linger in dev
  (debrief/finalized) — harmless; delete if desired.

## Done — Phase 11 T11.3 failure-mode pass (2026-07-14)
- Session 1012, Chrome (interviewer) ↔ Safari (candidate). Agent drove +
  verified server-side; Thomas ran the browsers. Full detail INTEGRATION.md §10.
- **Candidate reload / P6 reconciliation — PASS:** reloaded Safari mid-call
  with exhibit revealed → call view + exhibit restored, no re-admit; session
  stayed `live`, WS reconnected, reveals/exhibits re-fetched.
- **Signaling-server restart — PASS:** agent `pkill`+relaunch mid-call → both
  sides "reconnecting…" banner → WS reconnect; P2P media kept flowing; session
  stayed `live`. **FM-1:** process-local hub loses `admitted` on restart →
  spurious admit prompt + sdp/ice relay gated until re-admit (prod fix: rebuild
  `admitted` from DB session on WS connect).
- **Wifi-drop / ICE-restart — NOT reproducible on one Mac:** P2P chose loopback,
  so wifi-off did nothing (call continued). Reconnect-UI half covered by the
  server-restart test; ICE-restart code path confirmed wired (rtc.js:75-81,
  restartIce on disconnected/failed). A live ICE-restart needs 2 devices/WAN.
- Session 1012 left `live` (throwaway); will age out via the A4 sweep, or End it.

## Done — Phase 11 T11.2 cross-browser pass (2026-07-14)
- Real two-browser call, session 984 on case 1: **Chrome 149 (interviewer) ↔
  Safari 27 (candidate)** — browsers verified via stored session User-Agents,
  not assumed. Agent drove the checklist + verified every leg server-side
  (DB state, reveals, recordings mime/bytes, exhibit rows); Thomas ran the
  two browsers. All 4 legs pass: call (cross-browser WebRTC + media both
  ways), reveal (Safari WebCrypto decrypt + DataChannel key fast-path),
  recording (Safari captured 1.14 MB, completed, downloads), authoring
  (Safari PDF→WebP thumbnails render + save round-trip).
- Full findings in INTEGRATION.md §9. Summary:
  - CB-1: Safari 27 records `audio/webm;codecs=opus` — the `audio/mp4`
    fallback (recorder.js:19) is now dead code on modern Safari. Recording
    works; "downloads not inline" is the endpoint's `attachment` header.
  - CB-2 (FIXED): knock-race — candidate knocked once on its own `ok`; hub
    drops it if the interviewer isn't connected yet, and the candidate never
    re-knocked, so candidate-first → permanent hang at "Knocking…". Fix:
    re-knock on `peer-joined` (session.js). Browser-agnostic. Verified.
  - CB-3 (TO FIX): interviewer's own recording left `completed=f` if the page
    navigates right after End (fire-and-forget `stopAndComplete`, session.js:
    297). Content preserved on disk. Fix later with `{keepalive:true}`.
  - CB-4 (minor): stale/back-button session page → "Session is not joinable"
    instead of the debrief editor (boot keys off page-load state). Fresh load
    is correct.
- Dev-data note: deleted 2 test reveals (exhibit 21, sessions 983/984) to lift
  the DV-13 authoring lock for the Safari save leg — DV-13 itself confirmed
  working (it blocked the save until cleared). Sessions 983 (all webm, both
  completed) + 984 are throwaway T11.2 artifacts in `debrief`.

## Done — Phase 11 rule-05 polish (2026-07-14, commit 872d1e7)
- Guide rule 05 = the staircase is the system's ONLY icon. This finishes the
  conformance deferred through the restyle + Interviewer-Console phases.
- `webapp/static/favicon.svg` — new; staircase glyph on viewBox 0 0 48 48,
  ink→uptick gradient, `@media (prefers-color-scheme: dark)` swaps to
  chalk→dark-uptick (tracks OS theme, not the app toggle — standard for SVG
  favicons). Linked via `<link rel="icon" type="image/svg+xml">` in base.html
  AND session.html (session.html is standalone, not extending base).
- Icon sweep (only 3 `<svg>` remain repo-wide, all the staircase mark):
  - theme toggle: sun/moon SVGs → caps "Dark"/"Light" text label. Label swap
    is pure CSS (`dark:hidden` / `hidden dark:inline`), mirroring the old
    icon-swap, so it's correct before paint; existing click JS untouched.
    Both nav variants. **REVERTED per owner (commit b9097db):** Thomas
    prefers the sun/moon icon in both modes, so the toggle keeps the icon
    as the documented rule-05 exception. The rest of the sweep stands.
  - case_detail vote pills: dropped thumbs-up/down (the "Useful"/"Not useful"
    text already labels them); pruned now-dead `.vote-icon` CSS in base.html.
  - case_detail PDF actions: dropped external-link + download glyphs ("Open
    PDF in new tab" / "Download" are self-labeling).
  - case_detail back link: arrow SVG → typographic `←` (matches the app's
    existing "Open case →" text-arrow use; not an icon).
  - search icon was already gone (dropped in the browse redesign).
- Verified: `pytest tests/ -q` → 234 passed (unchanged). Dev server up;
  `/static/favicon.svg` → 200 image/svg+xml, `<link rel=icon>` in served
  heads. Authed GET /cases/354 served the swept markup (0 vote-icon, `←`
  back link, text PDF buttons). Browser: theme-toggle CLICK flips
  html.dark + localStorage + label "Dark"↔"Light" (light & dark shots:
  output/evidence/rule05-case-{light,dark}.png).

## Done — Phase 11 T11.1 verify script (2026-07-14)
- `scripts/verify_caseroom.sh` — advisory security grep, spec T11.1's five
  PHP checks adapted to this FastAPI/psycopg/vanilla-JS repo. Runs from any
  CWD (resolves REPO_ROOT), `set -uo pipefail` (grep-exit-1 is normal, not
  -e), 4-line header docblock, always exits 0 (advisory, not a CI gate).
- Checks: (a) variables interpolated into SQL text in `execute()` — f-string/
  `.format()`/`+`/`%`, word-bounded SQL keywords so "updated" ≠ UPDATE and
  psycopg `%(name)s`/`%s` placeholders excluded; (b) `webapp/routes/*.py`
  with `@router.` but no `require_auth_api`/`require_auth`; (c) secret-shaped
  literals in git-TRACKED files only (`git ls-files`, sk-/AKIA/PEM/re_/
  generic pw=; `caseroom-dev-1` allowlisted, tests/ + docs/ excluded);
  (d) upload dirs (exhibits/recordings/cases/emails) gitignored (git
  check-ignore) AND not StaticFiles-mounted; (e) `console.*` of sdp/ice/
  candidate/key/secret/offer/answer under webapp/static/js/.
- RAN clean, exit 0: 13 advisory hits — a:11, b:2, c:0, d:0, e:0. ALL
  justified (fix count = 0). Each verified independently on the main model,
  not just taken from the worker:
  - (a) 11 SQL hits: `_SESSION_COLS`/`_COLS` are static module column-list
    constants; `queues.py` `_table(kind)` is a `_TABLES` dict lookup that
    raises ValueError on any key ≠ want/give (table names can't be
    parameterized — this IS the allowlist); `practice_sessions.py` `{column}`
    is a 2-value literal ternary (consent_interviewer|consent_candidate),
    `{stamps}` is assembled only from string literals gated by `==` (target
    itself goes in as `%s`); `recordings.py:71` `+` is SQL arithmetic
    (`bytes + %s`) in a plain string. No request data reaches any SQL text.
  - (b) 2 route hits: `admin.py` guards every route with `Depends(
    require_admin)`, which calls `require_auth(request)` internally then
    admin-allowlists (404-not-403 to hide the surface); `signal_ws.py` does
    manual cookie auth (`get_user_for_session` → CLOSE_UNAUTHORIZED/
    _FORBIDDEN) because SessionMiddleware never runs for WebSockets (the
    documented Phase-3 exception). Both genuinely guarded; grep can't see
    through the wrapper / the WS handshake.
  - (c)(d)(e) clean: no tracked secrets; only `/static` is mounted
    (main.py:115), all four upload dirs gitignored; no signaling data logged.
- Two bash gotchas fixed while building: naive check-(a) grep matched UPDATE
  inside "updated" and flagged safe `%(name)s` placeholders (28 noisy → 11
  real, via `\b` boundaries + tighter `%`-operator pattern); macOS bash 3.2
  misparses a `#` comment inside `<(...)` process substitution ("bad
  substitution") though `bash -n` passes — comment moved above the block.
- NOT committed by the worker; reviewed + committed on main model this session.

## Done — Browse tiles: open rule-bounded tiles (2026-07-12, owner call)
- Owner: keep the calm palette, drop the rounded/bg card shell — tiles
  now use the guide's top+bottom hairlines, transparent, no radius or
  shadow (guide rule 02 fully in force again; the earlier "soft-card
  exception" note in base.html is superseded). Hover = surface wash.
  Grid gutters gap-x-10/gap-y-5 so the rules read as columns.
  NOTE: dark-mode screenshots taken immediately after a JS theme
  toggle can catch Tailwind-CDN pre-recompile colors (HARD badge
  looked ink; computed style confirmed chalk #E9EEF5 — verified).
  Shots: output/evidence/browse-rules-{light,dark}.png. Commit 5100509

## Done — Calmer school + difficulty palette (2026-07-12, owner call)
- Difficulty badges: ink RAMP (Easy quiet outline · Medium firm
  outline · Hard solid ink block — flips to chalk block in dark);
  ordinal data gets intensity, not three hues. badge-* classes in
  base.html so case detail inherits
- School names: one desaturated ink-adjacent band (light) + hand-tuned
  brighter lifts (dark) via --sc/--scd CSS vars; brightness-filter hack
  removed. Map in _search_results.html
- Shots: output/evidence/browse-calm-{light,dark,dark2}.png. Commit e6f47e3

## Done — Browse tiles: classic soft-card shell (2026-07-12, owner call)
- Owner: soft-card dialect, no borders, school color moves into the
  school NAME, 3-up on larger screens. .case-card = borderless
  rounded-[0.75rem] + soft/lift shadows w/ explicit values (THE one
  documented exception to guide rules 01/02 — global radius/shadow
  scales remain zeroed elsewhere); accent-bar CSS removed; school name
  inline-colored + dark:[filter:brightness(1.9)] for midnight
  legibility; Columbia hue → #0369A1 (light-mode contrast); grid
  md:2 → lg:3; internal footer hairline dropped. Interior typography
  (kicker/bold title/serif firm/coded usefulness) unchanged.
  Shots: output/evidence/browse-soft-{light,dark}.png. Commit 7a7e510

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
