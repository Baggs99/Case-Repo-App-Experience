# CaseRoom iOS App — Phase 3 (Remote WebRTC Media) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship P3 of the CaseRoom iPhone app — **remote** practice sessions with live WebRTC audio/video (and a video-off "phone-screen practice" mode), so an iPhone and a desktop can run a full case over cellular. Reuse the existing signaling WebSocket's `sdp`/`ice` relay + perfect-negotiation protocol; add TURN for NAT traversal, a session **mode** to separate remote (media) from P2's in-person (no media), and **Live Activities** for the lobby countdown + live timer.

**Architecture:** The signaling already carries `sdp`/`ice` between the two participants over the WebSocket (gated on `admitted`); the web client (`rtc.js`) already implements RFC-8829 perfect negotiation (candidate = polite, interviewer = impolite). P3 gives iOS the same: an `RTCPeerConnection` (WebRTC framework), the identical polite/impolite negotiation over the existing `SignalingClient`, camera/mic capture, and local/remote video views — wired into the P2 session screen **only for `remote`-mode sessions**. A new `mode` column distinguishes remote from in-person (QR-claimed in-person sessions from P2 stay media-free). TURN credentials are minted per-session server-side and delivered via the existing `join-config` endpoint. Live Activities reuse P1's APNs.

**Tech Stack:** FastAPI + Postgres (existing) · `httpx` (existing, for the TURN provider API) · SwiftUI + iOS 26 SDK (target iOS 17) · **WebRTC framework** (SPM — the one unavoidable heavy dependency; see Owner Decision 1) · `AVFoundation` capture · `ActivityKit` (Live Activities / Dynamic Island) · XCTest / pytest.

---

## ⚠️ Owner decisions required before execution (recommended defaults chosen — veto before the gated task)

**OD-1 · iOS WebRTC framework (unavoidable dependency).** There is no dependency-free way to do real-time media on iOS — this is the one justified exception to the repo's dependency-free rule. **Default: the `WebRTC` framework via Swift Package Manager** (the maintained binary distribution, e.g. `stasel/WebRTC` or `webrtc-sdk`). It's a ~30–70 MB prebuilt binary. *Alternative considered and rejected:* rolling raw sockets / no media (defeats the phase). Commit message for the adding task must carry the one-line justification. **Gates Task 5.**

**OD-2 · TURN provider (cost/ops decision).** Cellular sessions need TURN (STUN alone fails behind symmetric NAT). Hostinger shared hosting **cannot** run a TURN server, so self-hosting `coturn` means a separate VPS (~$5/mo + ops). **Default: Cloudflare Calls TURN** — a generous free tier, no server to run, short-lived credentials minted via their API from the FastAPI backend. *Alternatives:* self-hosted `coturn` on a VPS (free software, ops burden, HMAC time-limited creds), or Twilio TURN (paid). **Gates Tasks 2–3.** Thomas must create the provider account/key and put the secret in `.env` before real-device cellular testing (a simulator/same-LAN session works STUN-only).

**Scope note:** Much of P3 is **only verifiable on real devices over a real network** (camera, live WebRTC media, cellular NAT/TURN). Unit tests cover the negotiation state machine, signaling, the `mode` gate, and TURN-cred minting; the actual media/video/cellular path is a real-device manual check (Task 12). The plan is written so the maximum is simulator/CI-verifiable and the irreducibly-manual parts are explicit.

---

## Global Constraints

- Branch: create `feature/ios-p3` from `feature/ios-p2`. **Never push main. Never force-push.** Thomas merges.
- Parameterized SQL only. New state-changing endpoints carry `Depends(require_auth_api)` + `dependencies=_MUTATING`; GET endpoints auth-only.
- Secrets: the TURN provider token lives ONLY in gitignored `.env` (`TURN_*`); never committed/echoed. TURN credentials minted server-side are short-lived and per-session.
- Signaling stays **single-worker** (in-process `SignalingHub`). `sdp`/`ice` relay + the media path do not change that.
- iOS: deployment target iOS 17.0, iOS 26 SDK, simulator `iPhone 17`. The WebRTC framework's camera capture does NOT run on the simulator — media capture code is real-device-only; keep it behind the injectable protocols so the simulator build + unit tests pass without a camera.
- Commit at the end of every task. Update `PROGRESS.md` at phase boundaries.
- **Scope boundary:** P3 is REMOTE media only. In-person (P2, `mode='in_person'`) sessions stay media-free and unchanged. P4 (Foundation-Models drills, widgets, App Intents, "free now") is out of scope.

### Verified existing interfaces (recon 2026-07-14 — authoritative)

**Perfect negotiation** (`webapp/static/js/caseroom/rtc.js` — mirror this on iOS):
- `new RTCPeerConnection({ iceServers, iceTransportPolicy: forceRelay ? 'relay' : 'all' })`.
- **Polite = candidate, impolite = interviewer** (`polite: IS_CANDIDATE`).
- `onnegotiationneeded` → `setLocalDescription()` (implicit offer) → send `{"type":"sdp","description":<localDescription>}`.
- Inbound `sdp`: `offerCollision = description.type==='offer' && (makingOffer || signalingState!=='stable')`; `ignoreOffer = !polite && offerCollision`; if `ignoreOffer` drop it; else `setRemoteDescription(description)`, and if it was an offer, `setLocalDescription()` → send the answer.
- `onicecandidate` → send `{"type":"ice","candidate":<candidate>}` (and a final `{candidate:null}`); inbound `ice` → `addIceCandidate(candidate ?? undefined)`, dropped while `ignoreOffer`.
- Negotiated DataChannel `'ctrl'` `{id:0, negotiated:true, ordered:true}` (both create independently — used for echo/latency + the DV-4 fallback signal, NOT reveal after P2).
- Video sender bitrate capped at 1.2 Mbps; ICE restart on `disconnected` (3 s grace) / `failed`.

**Signaling relay** (`webapp/signaling.py`): `sdp`/`ice` are relayed to the peer ONLY when `call.admitted` (set by the interviewer's `admit`). Shapes: client sends `{"type":"sdp","description":{...}}` and `{"type":"ice","candidate":{...}|null}`; server relays `{"type":"sdp","description":...}` / `{"type":"ice","candidate":...}` to the peer. (The iOS `SignalingClient` from P2 deliberately never sent these — P3 adds them.)

**ICE config delivery** (`webapp/routes/practice.py`): `GET /api/practice/{session_id}/join-config` → `{"session_id","your_role","ws_path":"/ws/practice/{id}","ice_servers":[...]}`. `ice_servers` comes from `ICE_SERVERS_JSON` env (default STUN-only `stun:stun.l.google.com:19302`). **No TURN credential minting exists yet.**

**Media (web)**: `getUserMedia({video:{1280×720@30}, audio:{ec/ns/agc}})` (audio+video together); video-off = `track.enabled = !track.enabled` (track stays in the stream); recording is mic-only (`MediaRecorder` on the audio track).

**Session mode**: **does not exist.** `practice_sessions` has no mode/type column; every web session currently attempts media (a debug `?nomedia=1` flag aside). P3 adds `mode`.

**iOS building blocks (P2, reuse)**: `SignalingClient`/`SignalingChannel` (add `sdp`/`ice` send + inbound cases), `SignalMessage` (add `.sdp`/`.ice`), `SessionViewModel`/`SessionView` (host the media view for `remote` sessions), the P1 APNs push infra (reuse for ActivityKit push tokens).

---

## Phase A — Backend: session mode + TURN

### Task 1: Migration 015 — session mode + expose it

**Files:** Create `db/migrations/015_session_mode.sql`; Modify `webapp/repositories/practice_sessions.py` (`_SESSION_COLS`/create), `webapp/repositories/pairing_tokens.py` (claim sets in_person), `webapp/routes/practice.py` (join-config + session detail return `mode`).

**Interfaces:** `practice_sessions.mode text NOT NULL DEFAULT 'remote' CHECK (mode IN ('remote','in_person'))`. `create_practice_session(..., mode: str = 'remote')`. The pairing-token `claim` (P2) passes `mode='in_person'`. `GET /api/practice/{id}` and `/join-config` include `"mode"`.

- [ ] **Step 1: Migration**
```sql
-- db/migrations/015_session_mode.sql
-- Distinguish remote (WebRTC media) from in-person (no media, P2 QR flow).
ALTER TABLE practice_sessions
  ADD COLUMN IF NOT EXISTS mode text NOT NULL DEFAULT 'remote'
  CHECK (mode IN ('remote','in_person'));
```
- [ ] **Step 2: Apply + verify** — `psql "$DATABASE_URL" -f db/migrations/015_session_mode.sql`; `\d practice_sessions` shows `mode`.
- [ ] **Step 3: Thread mode through** — add `mode` param to `create_practice_session` (default `'remote'`); the pairing-token `claim` path (P2, `webapp/repositories/pairing_tokens.py`) creates its session with `mode='in_person'`; add `mode` to `_SESSION_COLS`/the returned session dict; add `"mode"` to the `join-config` response. Failing test in `tests/test_session_mode.py`: a proposal-accepted session → `mode=='remote'`; a pairing-claimed session → `mode=='in_person'`; `GET /api/practice/{id}` and `/join-config` return the mode. RUN FAIL → implement → RUN PASS.
- [ ] **Step 4: Commit** `"Add session mode (remote vs in-person); expose in join-config"`.

---

### Task 2: TURN credential minting (provider-backed)

**Files:** Create `webapp/turn.py`; Modify `webapp/settings.py` (`TURN_*` settings), `requirements.txt` note if needed. Test `tests/test_turn.py`.

**Interfaces:** `async mint_turn_credentials(settings, *, ttl_seconds=3600, client=None) -> list[dict]` — returns ICE-server dicts with short-lived TURN username/credential; returns `[]` (falls back to STUN) when `TURN_*` settings are absent. `TURN_ENABLED` = all TURN settings present.

- [ ] **Step 1: Settings** — add `TURN_PROVIDER` (`'cloudflare'` default), `TURN_KEY_ID`, `TURN_TOKEN` (all `str | None`) to `webapp/settings.py` following the existing pattern.
- [ ] **Step 2: Failing test** — with a mocked `httpx` transport returning a canned Cloudflare `{"iceServers":{"urls":[...],"username":...,"credential":...}}`, `mint_turn_credentials(fake_settings)` returns a normalized `[{"urls":[...],"username":...,"credential":...}]`; with no TURN settings → `[]`, no network call. (Mirror P1's `tests/test_apns.py` MockTransport pattern.)
- [ ] **Step 3: Implement** `webapp/turn.py` — for `cloudflare`: `POST https://rtc.live.cloudflare.com/v1/turn/keys/{TURN_KEY_ID}/credentials/generate` with `Authorization: Bearer {TURN_TOKEN}` and `{"ttl": ttl_seconds}`; normalize the response to the ICE-server list shape the client expects. Never raise into a request (log + return `[]` on provider error — STUN-only degrade). (A `coturn` branch — HMAC `username=exp:sessionid`, `credential=base64(hmac_sha1(secret, username))` — is a documented alternative if OD-2 picks self-hosting; implement only the chosen provider.)
- [ ] **Step 4: RUN PASS. Commit** `"Add short-lived TURN credential minting"`.

---

### Task 3: Deliver TURN creds via join-config

**Files:** Modify `webapp/routes/practice.py` (`/join-config`). Test extend `tests/test_turn.py`.

**Interfaces:** `/join-config` merges the static `ice_servers` (STUN) with freshly-minted TURN creds (Task 2) — only for `mode='remote'` sessions (in-person needs no ICE). Response `ice_servers` = STUN + TURN.

- [ ] Steps: failing test (a remote session's `/join-config` includes the minted TURN entry when `TURN_*` set; STUN-only when absent; an in-person session gets no TURN) → implement (await `mint_turn_credentials` in the handler, append to `ice_servers`; TURN mint failure degrades to STUN, never 500) → RUN PASS → commit `"Serve TURN credentials in join-config for remote sessions"`.

---

## Phase B — iOS: WebRTC media

### Task 4: Session mode + join-config models (iOS)

**Files:** Modify `ios/CaseRoom/Networking/SessionModels.swift`, `APIClient.swift`; Test `SessionServiceTests`.
**Interfaces:** `SessionDetail.mode: String`; `JoinConfig` Codable (`sessionId, yourRole, wsPath, iceServers:[ICEServer]`); `ICEServer{urls:[String], username:String?, credential:String?}`; `SessionService.joinConfig(id:) -> JoinConfig`.
- [ ] Steps (TDD): stub-decode a `join-config` JSON (with TURN entry) into `JoinConfig`; `SessionDetail` decodes `mode`; the session screen reads `mode` to decide media vs no-media → RUN FAIL → implement → RUN PASS → commit `"Add iOS join-config + session mode models"`.

---

### Task 5: WebRTC framework + RTCPeerConnection wrapper  ·  **gated on OD-1**

**Files:** Modify `ios/project.yml` (add the WebRTC SPM package per OD-1); Create `ios/CaseRoom/Media/PeerConnection.swift`. Test `ios/CaseRoomTests/PeerConnectionTests.swift`.
**Interfaces:** a thin `protocol MediaTransport` the negotiation layer depends on (create offer/answer, set local/remote description, add ICE candidate, add local tracks, expose remote track, close) so the negotiation state machine (Task 6) is testable with a stub without the real framework/camera. `RTCPeerConnectionWrapper: MediaTransport` builds `RTCPeerConnection` with the delivered `iceServers` + `iceTransportPolicy` (`.relay` when a forceRelay debug flag is set).
- [ ] Steps: add the SPM dependency in `project.yml` (commit-message justification per OD-1); implement the wrapper + protocol; a unit test that constructs the wrapper with fake ICE servers and asserts it initializes (no camera needed — configuration only; live media is Task 12 real-device). Build on iPhone 17 → commit `"Add WebRTC framework and RTCPeerConnection wrapper (dep: real-time media requires it)"`.

---

### Task 6: Perfect-negotiation client (mirror rtc.js)

**Files:** Create `ios/CaseRoom/Media/Negotiator.swift`; Modify `SignalMessage.swift` (add `.sdp`/`.ice` inbound + outbound helpers), `SignalingClient.swift`/`SignalingChannel` (send sdp/ice). Test `NegotiatorTests.swift`, `SignalMessageTests.swift`.
**Interfaces:** `SignalMessage` gains `.sdp(description: SDPPayload)` and `.ice(candidate: ICEPayload?)` (parse `{"type":"sdp","description":{type,sdp}}`, `{"type":"ice","candidate":{...}|null}`). `Negotiator(transport: MediaTransport, signaling: SignalingChannel, polite: Bool)` implements RFC-8829 exactly like rtc.js: `polite = (role == "candidate")`; on negotiation-needed → set local → send sdp; on inbound sdp → collision check (`offer && (makingOffer || state != stable)`), `ignoreOffer = !polite && collision`, else set remote (+answer if offer); on inbound ice → add candidate (drop while ignoreOffer). Send sdp/ice over the signaling channel (which the P2 client never did).
- [ ] Steps (TDD, the state machine is the high-value test): with a STUB `MediaTransport` + stub signaling, drive: impolite side offers on negotiation-needed → sends sdp; a colliding offer arrives at the impolite side → `ignoreOffer` (not applied); the polite side accepts a colliding offer (rollback path); inbound ice is added; ice while ignoreOffer is dropped. Assert the exact sent messages + transport calls. Also parser tests for `.sdp`/`.ice` (Int/String-safe). RUN FAIL → implement → RUN PASS → build → commit `"Add perfect-negotiation client mirroring rtc.js"`.

---

### Task 7: Camera/mic capture + video views  ·  real-device media, simulator-safe build

**Files:** Create `ios/CaseRoom/Media/MediaCapture.swift`, `ios/CaseRoom/Views/VideoCallView.swift`. Test `MediaCaptureTests.swift` (logic only).
**Interfaces:** `protocol MediaCapturing { func start(video: Bool, audio: Bool) throws; func setVideoEnabled(_:); func setAudioEnabled(_:); var localTrack; var remoteTrack; func stop() }`; `WebRTCMediaCapture: MediaCapturing` uses `RTCCameraVideoCapturer` + audio; `VideoCallView` shows local (PIP) + remote `RTCMTLVideoView`, with mute/camera toggles (`setVideoEnabled`/`setAudioEnabled` = `track.isEnabled`), matching the web's `btn-mute`/`btn-cam`. Camera usage string already ships (P2 added `NSCameraUsageDescription`); add nothing new to Info.plist except confirming mic (P2 added `NSMicrophoneUsageDescription`).
- [ ] Steps: implement behind `MediaCapturing` so the simulator build + unit tests don't need a camera; unit-test the toggle logic (setVideoEnabled flips the injected track's enabled state via a stub); build. The live camera/preview is Task 12 real-device. Commit `"Add camera/mic capture and video call view (real-device media)"`.

---

### Task 8: Wire media into the session screen (remote only) + video-off mode

**Files:** Modify `ios/CaseRoom/State/SessionViewModel.swift`, `ios/CaseRoom/Views/SessionView.swift`. Test `SessionViewModelTests.swift`.
**Interfaces:** for a `mode=='remote'` session, on entering `live` (post-admit) the interviewer/candidate set up `MediaTransport` + `Negotiator` + `MediaCapturing` (fetch `joinConfig` for iceServers), attach local tracks, and render `VideoCallView`; the video-off toggle = audio-only "phone-screen practice". A `mode=='in_person'` session keeps the P2 no-media path unchanged. The sdp/ice gate (post-admit) is respected — no offer before admit. Inject the media collaborators (protocols) so the VM test runs without WebRTC.
- [ ] Steps (TDD): VM test with stub transport/negotiator/capture — a remote-mode live transition creates the negotiator + starts capture; an in-person-mode live transition does NOT (stays P2 flow); video-off toggles `setVideoEnabled(false)`. RUN FAIL → implement → RUN PASS → build → commit `"Wire WebRTC media into remote session screen; video-off mode"`.

---

## Phase C — Live Activities

### Task 9: Backend — ActivityKit push token registration + update pushes

**Files:** Create `webapp/push/live_activity.py`; Modify device-token/registration routes + the session lifecycle. Migration `016_live_activity_tokens.sql`. Test `tests/test_live_activity.py`.
**Interfaces:** table `live_activity_tokens(session_id, user_id, push_token)`; `POST /api/v1/live-activity` registers a per-session Live Activity push token; on lobby→live and a periodic timer the server sends ActivityKit update pushes over APNs (reuse P1's `webapp/push/apns.py` — Live Activity pushes use `apns-push-type: liveactivity`, topic `{bundle}.push-type.liveactivity`, an `event`/`content-state` payload). No-op when APNs disabled (P1 `push_enabled`).
- [ ] Steps: migration + apply; failing tests (token upsert; the update-push payload shape for `liveactivity` type; no-op when disabled) → implement → RUN PASS → commit `"Add ActivityKit Live Activity push token + update pushes"`.

---

### Task 10: iOS — Live Activity (lobby countdown + live timer + Dynamic Island)

**Files:** Create `ios/CaseRoom/LiveActivity/SessionActivityAttributes.swift`, `ios/CaseRoomWidgets/SessionLiveActivity.swift` (a Widget Extension target in `project.yml`). 
**Interfaces:** `ActivityAttributes` with a `ContentState` (state, other user, scheduled/started time); start the Live Activity when a session enters lobby/live; register its `pushTokenUpdates` with the backend (Task 9); the widget renders the lock-screen banner + Dynamic Island (compact/expanded) with a lobby countdown or the live-session elapsed timer.
- [ ] Steps: add the widget-extension target to `project.yml`; implement the attributes + widget; wire start/end into the session lifecycle + push-token registration; build. Live Activity rendering is real-device/simulator-visual — assert the attributes/content-state model with a unit test and verify the widget builds; the on-device banner is Task 12 manual. Commit `"Add session Live Activity (lobby countdown, live timer, Dynamic Island)"`.

---

## Phase D — Verification + handoff

### Task 11: Automated verification (everything simulator/CI-checkable)

- [ ] Full backend suite `pytest tests/ -q` → green (mode, TURN mint, live-activity push). Full iOS suite `xcodebuild ... -destination 'platform=iOS Simulator,name=iPhone 17' test` → green (negotiation state machine, sdp/ice parser, mode gate, media toggle logic). A live HTTP+WS test: two WS clients complete a full **sdp/ice exchange through the relay** post-admit (using stub SDP/ICE payloads — proves the relay + the admit gate for media), and `/join-config` returns TURN creds for a remote session. Commit `"P3 automated verification"` (if any test files added).

### Task 12: Real-device manual verification + handoff

- [ ] **Real-device (the phase's "done when"):** with OD-1 dependency added and OD-2 TURN configured (`TURN_*` in `.env`), run an **iPhone ↔ desktop-web video session over cellular** (iPhone on cellular, not wifi) → both see/hear each other, video-off toggles audio-only, the Live Activity shows in the Dynamic Island, and it finalizes into history. Document the steps + result.
- [ ] **Update `PROGRESS.md`**: "P3 (remote WebRTC media) — DONE" with evidence; Remaining/manual: the real-device cellular run (needs OD-2 TURN key), App Store WebRTC-binary size note; still-open: Apple portal `.p8`, merge the branch chain. Note next: **P4 — Foundation-Models drills, widgets, App Intents/Entities, "free now" instant-match**.
- [ ] Commit `"Complete iOS P3: remote WebRTC media, TURN, Live Activities"`.

---

## Risks & open items
- **OD-1 / OD-2** (above) block Tasks 5 and 2–3 / 12 respectively — resolve before those tasks.
- **WebRTC on iOS is not simulator-testable for real media** — the plan maximizes unit-tested logic (negotiation, signaling, mode, TURN mint) and isolates the irreducible real-device parts (Task 12).
- **App size / review**: the WebRTC binary adds tens of MB; note it for App Store submission.
- **Single-worker signaling** still stands; a media session is 1:1 so it's fine, but revisit before any multi-session scale.
- **Recording** stays mic-only (P2 infra reused) — video recording is explicitly out of scope for P3.

## Manual steps only Thomas can do
1. **OD-1**: approve the WebRTC framework dependency (or name an alternative).
2. **OD-2**: pick the TURN provider; create the account/key (default Cloudflare Calls); put `TURN_KEY_ID`/`TURN_TOKEN` in `.env`.
3. Real-device cellular test (Task 12); merge `feature/ios-app` → `feature/ios-p2` → `feature/ios-p3`.

## Self-review (author checklist — done)
- Spec P3 coverage: WebRTC audio/video (T5–8) · same perfect-negotiation as rtc.js (T6) · video-off remote = phone-screen practice (T8) · Live Activities + Dynamic Island (T9–10) · TURN for cellular NAT + the provider decision (OD-2, T2–3) · "iPhone↔desktop video over cellular" (T12). All map to a task.
- In-person (P2) untouched: the `mode` gate keeps media off for `in_person` (T1, T8).
- Contracts use the recon-verified perfect-negotiation flow, sdp/ice shapes, and join-config verbatim.
- Two consequential dependencies/costs surfaced as explicit owner decisions with defaults, gating the relevant tasks.
