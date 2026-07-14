# CaseRoom iOS App — Phase 2 (Session Core, In-Person Mode) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship P2 of the CaseRoom iPhone app — a fully functional **in-person** practice session that runs with **no WebRTC media**: two iPhones in one room pair via QR, run lobby→live→debrief→finalize over the existing signaling WebSocket + `/api/practice/*` HTTP, reveal encrypted exhibits (key delivered over the WebSocket, decrypted on-device with CryptoKit), score the rubric, and record room audio — finalizing into history like any session. Migrate the web client's exhibit key-reveal onto the same WebSocket path (one protocol, two clients).

**Architecture:** The session-level backend already exists under `/api/practice/*` (cookie-auth + `require_same_origin`, both native-compatible — URLSession sends no `Origin`, which the CSRF guard passes). P2 adds three backend enablers — (1) a **server-side reveal broadcast** so the exhibit key travels over the signaling WebSocket instead of the WebRTC DataChannel; (2) an **ad-hoc pairing-token** subsystem so two co-located users can spin up a session without pre-scheduling; (3) the **web client migration** to the WS reveal path. The iOS app gains a `URLSessionWebSocketTask` signaling client, CryptoKit AES-GCM exhibit decryption, and the native session screen (lobby/knock/admit, rubric+timer, exhibit reveal/view, audio recording, finalize) plus the QR create/scan flow (VisionKit `DataScannerViewController`).

**Tech Stack:** FastAPI + psycopg3 + Postgres (existing) · `cryptography` AES-GCM (existing, for exhibits) · SwiftUI + iOS 26 SDK (deployment target iOS 17) · `URLSessionWebSocketTask` (signaling) · CryptoKit (`AES.GCM`, exhibit decrypt) · AVFoundation (`AVAudioRecorder`, room mic) · VisionKit (`DataScannerViewController`, QR scan) · CoreImage (`CIFilter.qrCodeGenerator`, QR display) · XCTest / pytest.

## Global Constraints

- Branch: create `feature/ios-p2` from `feature/ios-app` (P1's work). **Never push main. Never force-push.** Thomas merges.
- Parameterized SQL only — zero string-interpolated SQL (repo rule).
- Every new state-changing endpoint carries BOTH `Depends(require_auth_api)` and `dependencies=_MUTATING` (`require_same_origin`) — consistent with all existing `/api/practice/*` routes. Native passes same-origin (no `Origin` header); browsers stay protected.
- Server-side validation on every new endpoint; client checks are UX only.
- Signaling stays **single-worker** (in-process `SignalingHub` peer map). The reveal broadcast (Task 1) relies on this — do not add workers.
- iOS: deployment target iOS 17.0, build with the iOS 26 SDK, simulator **`iPhone 17`** (iOS 26.5 runtime is installed). System SwiftUI components over custom chrome.
- Commit at the end of every task (imperative message). Update `PROGRESS.md` at phase boundaries.
- **Scope boundary:** P2 is **in-person only** — both devices in one room, no network media. A session runs entirely over the WebSocket (signaling + reveal) + `/api/practice/*` HTTP with **no `RTCPeerConnection`**. Remote/video-off-over-network sessions need WebRTC audio and are **P3** — do not build any WebRTC in P2.

### Verified existing interfaces (recon 2026-07-14 — authoritative; do not re-derive)

**Signaling WebSocket** (`webapp/routes/signal_ws.py`, `webapp/signaling.py`):
- Path `GET /ws/practice/{session_id}`. Auth: session cookie verified before `accept()`. Acceptable states: `scheduled`, `lobby`, `live`. Role from `role_of(session, user.id)` (→ `interviewer`/`candidate`, else close).
- On connect the server sends `{"type":"ok","role":str,"peer_present":bool,"admitted":bool}`.
- Client→server message types: `ping` (→ `pong` to self); `knock` (candidate only → `{"type":"knock","display_name":str}` to interviewer, + APNs push side-effect already wired in P1); `admit`/`deny` (interviewer only → `{"type":mtype}` to candidate; `admit` sets `call.admitted=True`); `sdp`/`ice` (any, **gated on `admitted`** — P3 media only); `bye` (any → `{"type":"peer-left"}` to peer).
- `SignalingHub` tracks `self._calls: dict[int,_Call]`; `_Call.sockets: dict[str,PeerSocket]` (role→socket); `_Call.admitted: bool`. Peer lookup: `call.sockets.get(peer_role(role))`. Send helper: `_safe_send(socket, dict)`.

**Exhibits + crypto** (`webapp/exhibit_crypto.py`, `webapp/repositories/case_exhibits.py`, `webapp/routes/practice_exhibits.py`):
- Ciphertext = `AESGCM(key).encrypt(iv, webp_bytes, None)` — **AES-256-GCM, 32-byte key, 12-byte IV/nonce, 16-byte tag appended to ciphertext**. WebCrypto- and CryptoKit-compatible.
- **The key is per-exhibit and permanent, stored server-side** in `case_exhibits.enc_key BYTEA` (32) + `enc_iv BYTEA` (12). The interviewer only *relays* it today; the server can send it directly.
- Manifest: `GET /api/practice/{sid}/exhibits` → `{"exhibits":[{"exhibit_id":int,"idx":int,"source_pages":str,"width":int,"height":int,"bytes":int,"iv_b64":str}]}` (key NOT in manifest).
- Ciphertext blob: `GET /api/practice/{sid}/exhibit-blob/{exhibit_id}` → raw `application/octet-stream` (ciphertext+tag; IV comes from the manifest).
- Reveal log: `POST /api/practice/{sid}/reveals` `{"exhibit_id":int}` (interviewer only, session must be `live`) → inserts `reveals` row (idempotent, `already_revealed` on repeat). Fallback key fetch: `GET /api/practice/{sid}/exhibit-key/{exhibit_id}` returns the key IF a reveal row exists.

**Rubric / finalize** (`webapp/routes/practice_feedback.py`):
- `GET /api/practice/{sid}/rubric` (interviewer only) → `{"template_items":[{"id":str,"label":str,"dimension":str,"max_points":int}],"items":{},"notes_md":str,"grade_preview":float,"grade":float|null,"finalized_at":str|null}`. 5 dimensions × 5 points.
- `PUT /api/practice/{sid}/rubric` (interviewer) body `{"items":{"<id>":{"points":int,"note":str}},"notes_md":str}` → `{"saved":true,"grade_preview":float}`. Full-draft autosave (debounce client-side); 409 if finalized. points 0..max; note ≤2000; notes_md ≤20000.
- `POST /api/practice/{sid}/finalize` (interviewer, state must be `debrief`) body `{"grade":null|float}` → `{"finalized":true,"grade":float,"finalized_at":str}`. grade = `5 × Σpoints / Σmax`, rounded 0.1 (or the override).

**Recordings** (`webapp/routes/practice_recordings.py`):
- `POST /api/practice/{sid}/recordings/chunk` multipart `seq:int`, `mime:str` (`audio/webm`|`audio/mp4`), `blob:file`. State must be `live`|`debrief`. Chunk 0 creates the row; chunk 0 is container-sniffed (`ftyp` at offset 4 for mp4 — iOS `.m4a` passes). Per-chunk ≤8 MB (413), per-session ≤150 MB (413). Seq must equal current `chunks` count else **409 `{"detail":"expected seq N"}`** (distinguishes already-applied vs gap). → `{"ok":true,"chunks":int,"bytes":int}`.
- `POST /api/practice/{sid}/recordings/complete` → `{"completed":true,...}` (idempotent).
- Recording rows keyed `(session_id, user_id, role)`.

**Consent / state** (`webapp/routes/practice.py`, `webapp/practice_states.py`):
- `POST /api/practice/{sid}/consent` `{"consent":bool}` (state `scheduled`|`lobby`) → full session object.
- `POST /api/practice/{sid}/state` `{"target":str}`. Edges: `scheduled→lobby` (any), `lobby→live` (**interviewer only**, requires `consent_interviewer AND consent_candidate` else 409), `live→debrief` (any), `*→aborted` (any).
- `GET /api/practice/{sid}` → full session object incl. `interviewer_id,candidate_id,case_id,state,consent_interviewer,consent_candidate,started_at,ended_at,interviewer_name,candidate_name,case_title,your_role`.

**Session creation** (`webapp/repositories/practice_sessions.py:72` `create_practice_session(...)`): two callers today — `POST /api/practice` `{interviewer_id,candidate_id,case_id,scheduled_at?}` (checks caller is a participant, case exists, candidate hasn't burned the case) and proposal-accept. Migration numbering is at `013`; next is `014`.

---

## Phase A — Backend enablers

### Task 1: Reveal key over the WebSocket (server broadcast)

**Files:**
- Modify: `webapp/signaling.py` (add `broadcast_reveal`), `webapp/routes/practice_exhibits.py` (broadcast after logging a reveal)
- Test: `tests/test_reveal_ws.py`

**Interfaces:**
- Produces: `SignalingHub.broadcast_reveal(session_id: int, exhibit_id: int, key_b64: str) -> bool` — sends `{"type":"reveal","exhibit_id":exhibit_id,"key_b64":key_b64}` to the candidate socket if connected; returns whether a socket received it. The reveal HTTP endpoint calls it with the key read from `case_exhibits.enc_key` (base64-encoded).

- [ ] **Step 1: Failing test** — `tests/test_reveal_ws.py`: instantiate a `SignalingHub`, register a fake candidate `PeerSocket` (records sent dicts), call `await hub.broadcast_reveal(sid, exhibit_id=5, key_b64="AAAA")`, assert the candidate received `{"type":"reveal","exhibit_id":5,"key_b64":"AAAA"}` and the return is `True`; with no candidate connected → returns `False`, nothing raised. Match how existing signaling tests construct the hub + a fake socket (read `tests/` for the signaling test pattern).
- [ ] **Step 2: Run** `pytest tests/test_reveal_ws.py -v` → FAIL (no `broadcast_reveal`).
- [ ] **Step 3: Implement** `broadcast_reveal` in `webapp/signaling.py`:

```python
async def broadcast_reveal(self, session_id: int, exhibit_id: int, key_b64: str) -> bool:
    """Push an exhibit decryption key to the candidate over the signaling WS.
    Key travels here instead of the WebRTC DataChannel so exhibits work with
    no peer connection (in-person / video-off sessions)."""
    call = self._calls.get(session_id)
    if call is None:
        return False
    sock = call.sockets.get("candidate")
    if sock is None:
        return False
    await _safe_send(sock, {"type": "reveal", "exhibit_id": exhibit_id, "key_b64": key_b64})
    return True
```

- [ ] **Step 4:** In `webapp/routes/practice_exhibits.py`, in the reveal handler (`POST /api/practice/{sid}/reveals`), AFTER `create_reveal(...)` succeeds, read the exhibit key and broadcast it. Read the existing handler first for the exact variable names / hub accessor; the addition is roughly:

```python
# after create_reveal(...) logs the reveal:
key = case_exhibits_repo.key_for_exhibit(exhibit_id)   # bytes; add this repo helper if absent
await get_hub().broadcast_reveal(session_id, exhibit_id, base64.b64encode(key).decode())
```

If there is no `key_for_exhibit`, add a tiny parameterized repo function `key_for_exhibit(exhibit_id: int) -> bytes` in `webapp/repositories/case_exhibits.py` (`SELECT enc_key FROM case_exhibits WHERE id = %s`). The interviewer client no longer needs to relay the key — but the broadcast is additive and must not change the endpoint's existing JSON response or its `already_revealed` idempotency.
- [ ] **Step 5: Run** `pytest tests/test_reveal_ws.py tests/test_practice_exhibits.py -v` → PASS (reveal endpoint still behaves; broadcast covered).
- [ ] **Step 6: Commit** `"Broadcast exhibit key over signaling WS on reveal"`.

---

### Task 2: Migration 014 — pairing tokens

**Files:**
- Create: `db/migrations/014_pairing_tokens.sql`

**Interfaces:**
- Produces: table `pairing_tokens(id, token, interviewer_id, case_id, created_at, expires_at, claimed_session_id)`.

- [ ] **Step 1: Write the migration**

```sql
-- db/migrations/014_pairing_tokens.sql
-- Ad-hoc in-person pairing: an interviewer mints a one-time token bound to a
-- chosen case; the scanner (candidate) claims it, which CREATES the session.
CREATE TABLE IF NOT EXISTS pairing_tokens (
    id                  bigserial   PRIMARY KEY,
    token               text        NOT NULL UNIQUE,      -- URL-safe random, in the QR
    interviewer_id      integer     NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    case_id             integer     NOT NULL REFERENCES cases(id) ON DELETE CASCADE,
    created_at          timestamptz NOT NULL DEFAULT now(),
    expires_at          timestamptz NOT NULL,             -- short TTL (e.g. now()+10 min)
    claimed_session_id  integer     REFERENCES practice_sessions(id)  -- NULL until claimed (single-use)
);
CREATE INDEX IF NOT EXISTS idx_pairing_tokens_token ON pairing_tokens(token);
```

- [ ] **Step 2: Apply + verify** — `export $(grep -E '^DATABASE_URL=' .env | xargs)` then `psql "$DATABASE_URL" -f db/migrations/014_pairing_tokens.sql` and `psql "$DATABASE_URL" -c "\d pairing_tokens"` → 7 columns present.
- [ ] **Step 3: Commit** `"Add pairing_tokens table for ad-hoc in-person pairing"`.

---

### Task 3: Pairing-token repository + mint endpoint

**Files:**
- Create: `webapp/repositories/pairing_tokens.py`
- Modify: `webapp/routes/practice.py` (add `POST /api/practice/pair/create`)
- Test: `tests/test_pairing.py`

**Interfaces:**
- Consumes: DB pool idiom (`with get_pool().connection() as conn: with conn.cursor(row_factory=dict_row) as cur:`), `require_auth_api`, `require_same_origin`, existing case-existence check.
- Produces: repo `mint_token(interviewer_id: int, case_id: int, ttl_minutes: int = 10) -> dict` (returns `{token, expires_at}`; token = `secrets.token_urlsafe(24)`); route `POST /api/practice/pair/create` body `{"case_id": int}` → 200 `{"token": str, "expires_at": iso8601}`. Server validates the case exists; the authenticated user is the interviewer.

- [ ] **Step 1: Failing test** — `tests/test_pairing.py` (reuse `_READY`/`_HTTPX` harness + a seeded authenticated user): `POST /api/practice/pair/create {"case_id": <seeded case>}` → 200, body has a non-empty `token` and a future `expires_at`; a row exists in `pairing_tokens` with `interviewer_id`=the caller; a non-existent `case_id` → 404; unauthenticated → 401.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** repo `mint_token` (parameterized INSERT `RETURNING token, expires_at`, `expires_at = now() + make_interval(mins => %s)`) + the route (`Depends(require_auth_api)`, `_MUTATING`). **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `"Add pairing-token mint endpoint (POST /api/practice/pair/create)"`.

---

### Task 4: Claim endpoint (creates the session)

**Files:**
- Modify: `webapp/repositories/pairing_tokens.py` (add `claim`), `webapp/routes/practice.py` (add `POST /api/practice/pair/claim`)
- Test: `tests/test_pairing.py` (extend)

**Interfaces:**
- Consumes: `create_practice_session(interviewer_id, candidate_id, case_id, ...)` (`webapp/repositories/practice_sessions.py:72`).
- Produces: repo `claim(token: str, candidate_id: int) -> dict` — in ONE transaction: `SELECT ... FOR UPDATE` the token row, reject if missing / `expires_at < now()` / already `claimed_session_id IS NOT NULL` / `interviewer_id == candidate_id`; else create the session (interviewer_id from the token, candidate_id = the scanner), set `claimed_session_id`, return `{"session_id": int}`. Route `POST /api/practice/pair/claim` body `{"token": str}` → 200 `{"session_id": int}` (or 409 for expired/claimed/self-claim, 404 for unknown token). The session starts in `scheduled`; both clients then open it and knock/admit into the lobby like any session.

- [ ] **Step 1: Failing tests** — mint a token as user A; claim as user B → 200 with a `session_id`; `GET /api/practice/{session_id}` as A and as B both resolve with `your_role` interviewer/candidate respectively; a second claim of the same token → 409 (single-use); an expired token → 409; A claiming their own token → 409; unknown token → 404. (Note: if the seeded candidate has "burned" the case, `create_practice_session` will reject — pick a case the candidate hasn't burned, or seed accordingly; surface that error as a clear 409.)
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** the transactional `claim` + route. **Step 4: Run** → PASS. **Step 5:** full suite `pytest tests/ -q` → no regressions.
- [ ] **Step 6: Commit** `"Add pairing-token claim endpoint that creates the session"`.

---

## Phase B — Web client migration (decision 5: one protocol, two clients)

### Task 5: Web candidate receives reveal over the WebSocket

**Files:**
- Modify: `webapp/static/js/caseroom/session.js` (route a `reveal` WS message to exhibits), `webapp/static/js/caseroom/exhibits.js` (interviewer reveal no longer relays the key over the DataChannel — just POSTs `/reveals`; server broadcasts)
- (Reference only, do not delete media plumbing) `webapp/static/js/caseroom/rtc.js`

**Interfaces:**
- Consumes: the server `{"type":"reveal","exhibit_id","key_b64"}` WS message from Task 1.
- Produces: web candidate unlocks/decrypts an exhibit when the reveal arrives over the **WebSocket**, using the same `crypto.subtle.decrypt({name:'AES-GCM', iv: b64buf(iv_b64)}, key, cipher)` path (`exhibits.js` `_unlock`/`_decrypt`). Interviewer's "Release" action becomes: `POST /api/practice/{sid}/reveals {exhibit_id}` only (the existing DataChannel `sendCtrl({type:'reveal',...})` relay is removed).

- [ ] **Step 1:** Read `session.js` for where inbound WebSocket messages are dispatched (the signaling `onmessage`/handler that today processes `knock`/`admit`/`sdp`/`ice`/`peer-left`). Add a branch: `else if (msg.type === 'reveal') { exhibits?.handleCtrl(msg); }` — reusing the SAME `exhibits.handleCtrl` that the DataChannel path used (`{type:'reveal', exhibit_id, key_b64}`), so `_unlock`→`_decrypt` runs unchanged.
- [ ] **Step 2:** In `exhibits.js`, change the interviewer "Release" handler so it stops calling `this.opts.sendCtrl({type:'reveal',...})` (the DataChannel relay) and instead only ensures `POST /api/practice/{sid}/reveals {exhibit_id}` fires (it likely already does for logging — verify; if the POST was previously done elsewhere, keep exactly one POST). The server broadcast (Task 1) now delivers the key. Keep the interviewer's own local unlock (interviewer already holds keys for its own view).
- [ ] **Step 3: Verify (manual, no unit harness for this JS):** boot the backend, run a real 2-browser session (interviewer + candidate) per the repo's existing session flow, reveal an exhibit → the candidate's image decrypts and appears, driven by the WS message (confirm in devtools: the `reveal` arrives on the WebSocket, not a DataChannel). Confirm reveal is still logged (a `reveals` row). Capture the evidence (network frames / screenshot) in the report. Re-run the repo's cross-browser session smoke if one exists (INTEGRATION.md §9 CB checks).
- [ ] **Step 4: Commit** `"Migrate web exhibit reveal from DataChannel to signaling WebSocket"`.

---

## Phase C — iOS foundation

### Task 6: iOS signaling WebSocket client

**Files:**
- Create: `ios/CaseRoom/Networking/SignalingClient.swift`, `ios/CaseRoom/Networking/SignalMessage.swift`
- Test: `ios/CaseRoomTests/SignalMessageTests.swift`

**Interfaces:**
- Consumes: `URLSessionWebSocketTask` against `ws(s)://<API_BASE_URL host>/ws/practice/{sessionId}`; cookies flow via the shared `HTTPCookieStorage` (same as `APIClient`), so no token code.
- Produces:
  - `enum SignalMessage` (Codable-ish) modelling inbound `ok`/`knock`/`admit`/`deny`/`peer-left`/`reveal`/`pong` and a PURE `static func parse(_ data: Data) -> SignalMessage?` decoder (handles `session_id`/ids as Int or String defensively). Outbound helpers produce the JSON for `knock`, `admit`, `deny`, `bye`, `ping`.
  - `actor`/`@Observable` `SignalingClient` with `connect(sessionId:)`, an `AsyncStream`/callback of inbound `SignalMessage`, `send(_ outbound:)`, `disconnect()`, a `ping` heartbeat, and one automatic reconnect on drop. It must NEVER send `sdp`/`ice` (P3 media only).

- [ ] Steps (TDD): unit-test `SignalMessage.parse` against canned JSON for each inbound type (esp. `{"type":"reveal","exhibit_id":5,"key_b64":"..."}` → `.reveal(exhibitId:5,keyB64:"...")`, and `{"type":"ok","role":"candidate","peer_present":true,"admitted":false}`) plus malformed → nil → RUN FAIL → implement parser + client (derive the ws URL by swapping `http`→`ws` on `API_BASE_URL`) → RUN PASS (parser tests; the live socket is exercised in Task 15's E2E) → build on iPhone 17 → commit `"Add iOS signaling WebSocket client and message model"`.

---

### Task 7: iOS session service + SessionDetail model

**Files:**
- Create: `ios/CaseRoom/Networking/SessionModels.swift`, extend `ios/CaseRoom/Networking/APIClient.swift`
- Test: `ios/CaseRoomTests/SessionServiceTests.swift`

**Interfaces:**
- Produces Codable models matching the verified shapes: `SessionDetail` (`id,interviewerId,candidateId,caseId,state,consentInterviewer,consentCandidate,startedAt:Date?,endedAt:Date?,interviewerName,candidateName,caseTitle,yourRole`), `ExhibitMeta` (`exhibitId,idx,sourcePages,width,height,bytes,ivB64`), `RubricTemplateItem` (`id,label,dimension,maxPoints`), `RubricState` (`templateItems,items:[String:RubricItemScore],notesMd,gradePreview,grade:Double?,finalizedAt:Date?`), `RubricItemScore` (`points:Int,note:String`).
- Produces a `SessionService` protocol (APIClient conforms) covering the existing `/api/practice/*` endpoints the app needs: `sessionDetail(id)`, `setConsent(id, consent:Bool)`, `transition(id, target:String)`, `rubric(id)`, `saveRubric(id, items, notesMd)`, `reveal(id, exhibitId)`, `exhibits(id) -> [ExhibitMeta]`, `exhibitBlob(id, exhibitId) -> Data`, `uploadRecordingChunk(id, seq, mime, blob)`, `completeRecording(id)`, `finalize(id, grade:Double?)`. All are cookie-authed; POST/PUT are `/api/practice/*` (native passes same-origin). Use the existing ISO date decoder/encoder from P1.

- [ ] Steps (TDD): `SessionServiceTests` with URLProtocol stubs — assert request paths/methods/bodies for `sessionDetail`, `saveRubric` (PUT body shape `{"items":{...},"notes_md":...}`), `reveal` (`POST /reveals {exhibit_id}`), `transition` (`POST /state {target}`), and that a canned rubric/session JSON decodes into the models → RUN FAIL → implement models + `SessionService` conformance → RUN PASS → build → commit `"Add iOS session service and models for /api/practice"`.

---

### Task 8: iOS exhibit decryption (CryptoKit)

**Files:**
- Create: `ios/CaseRoom/Support/ExhibitCrypto.swift`
- Test: `ios/CaseRoomTests/ExhibitCryptoTests.swift`

**Interfaces:**
- Produces a PURE `enum ExhibitCrypto { static func decrypt(ciphertext: Data, keyB64: String, ivB64: String) throws -> Data }` using `AES.GCM` — the server appends the 16-byte tag to the ciphertext and uses a 12-byte nonce, so split accordingly: `nonce = AES.GCM.Nonce(data: iv)`, `sealed = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ct[..<(ct.count-16)], tag: ct[(ct.count-16)...])`, `return try AES.GCM.open(sealed, using: SymmetricKey(data: key))`. Decoded bytes are the WebP image.

- [ ] **Step 1: Failing test** — `ExhibitCryptoTests`: bundle a small fixture produced by the SERVER's `AESGCM` (generate one: a tiny script or a committed fixture of `key_b64`, `iv_b64`, `ciphertext` + the expected plaintext bytes). Assert `ExhibitCrypto.decrypt` returns the exact plaintext; a wrong key throws. (To produce the fixture deterministically, encrypt a known plaintext with `python -c` using `cryptography`'s `AESGCM` and commit the base64 values — do NOT hardcode a real exhibit.)
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** `ExhibitCrypto.decrypt`. **Step 4: Run** → PASS. **Step 5: Commit** `"Add CryptoKit AES-GCM exhibit decryption"`.

---

## Phase D — iOS session screen

### Task 9: Session entry + lobby (knock/admit/consent)

**Files:**
- Create: `ios/CaseRoom/Views/SessionView.swift`, `ios/CaseRoom/State/SessionViewModel.swift`, `ios/CaseRoom/Views/LobbyView.swift`
- Test: `ios/CaseRoomTests/SessionViewModelTests.swift`

**Interfaces:**
- Consumes: `SessionService` (Task 7), `SignalingClient` (Task 6) — both injectable protocols so the VM test uses stubs.
- Produces: `@Observable SessionViewModel(sessionId:, service:, signaling:)` — loads `SessionDetail`, connects the WS, exposes `state`, `role`, `peerPresent`, `admitted`, `myConsent`/`peerReady`; actions `knock()` (candidate), `admit()`/`deny()` (interviewer), `toggleConsent()` (POST consent), `goLive()` (interviewer: POST state `live`, gated on both-consent). It reacts to inbound `SignalMessage` (`ok`/`knock`/`admit`/`deny`/`peer-left`) to update state. `LobbyView` renders per-role: candidate shows a Knock button then "waiting to be admitted"; interviewer sees the knock + Admit/Deny; both see consent toggles and (interviewer) a Go-Live button enabled only when both consented.

- [ ] Steps (TDD): VM test with stub service + stub signaling (inject a scripted inbound message stream) — candidate `knock()` sends a `knock` outbound; interviewer receiving a `knock` sets `peerKnocked`; `admit()` sends `admit`; `toggleConsent()` calls `setConsent`; `goLive()` calls `transition(target:"live")` only when both consent flags true (assert it does NOT fire otherwise) → RUN FAIL → implement VM + views → RUN PASS → build iPhone 17 → commit `"Add session entry and lobby (knock/admit/consent) over WS"`.

---

### Task 10: Live — interviewer rubric + timer + reveal controls

**Files:**
- Create: `ios/CaseRoom/Views/RubricView.swift`, `ios/CaseRoom/State/RubricViewModel.swift`, `ios/CaseRoom/Views/InterviewerLiveView.swift`
- Test: `ios/CaseRoomTests/RubricViewModelTests.swift`

**Interfaces:**
- Consumes: `SessionService.rubric/saveRubric/reveal/exhibits` (Task 7).
- Produces: `@Observable RubricViewModel` — loads the template, holds `items: [String: RubricItemScore]` + `notesMd`, `gradePreview`; click-to-score updates an item and schedules a **debounced (~800 ms) `saveRubric` autosave**; exposes `save()` returning the new `gradePreview`. `InterviewerLiveView` shows the 5 dimensions with 0–5 pickers + notes, a client-side stopwatch **timer** (start/pause/reset, purely local — no server timer exists), an exhibit strip with a **Release** button per exhibit that calls `reveal(exhibitId:)` (the server broadcasts the key to the candidate), and a "Move to debrief" action (POST state `debrief`).

- [ ] Steps (TDD): VM test with stub service — scoring an item updates `items` and (after the debounce, tested by invoking the save path directly) calls `saveRubric` with the right body and updates `gradePreview` from the response; loading populates `templateItems` → RUN FAIL → implement VM + view (system components; brand tint; the timer is a local `TimelineView`/`Timer`) → RUN PASS → build → commit `"Add interviewer live view: rubric autosave, timer, reveal controls"`.

---

### Task 11: Live — candidate exhibit view (WS reveal → decrypt → display)

**Files:**
- Create: `ios/CaseRoom/Views/CandidateLiveView.swift`, `ios/CaseRoom/State/ExhibitsViewModel.swift`
- Test: `ios/CaseRoomTests/ExhibitsViewModelTests.swift`

**Interfaces:**
- Consumes: `SessionService.exhibits/exhibitBlob` (Task 7), `ExhibitCrypto.decrypt` (Task 8), inbound `.reveal(exhibitId:,keyB64:)` `SignalMessage` (Task 6).
- Produces: `@Observable ExhibitsViewModel` — loads the manifest (`[ExhibitMeta]`), pre-fetches each ciphertext blob (`exhibitBlob`) into memory locked, and on a `.reveal(exhibitId:,keyB64:)` message decrypts that exhibit (`ExhibitCrypto.decrypt(ciphertext:, keyB64:, ivB64: meta.ivB64)`) → a `UIImage`/`Image` shown in `CandidateLiveView`. Before reveal, exhibits show a locked placeholder. Feed the VM the reveal messages from the session's `SignalingClient` stream (injected in tests).

- [ ] Steps (TDD): VM test with a stub service (returns a manifest + a fixture ciphertext for one exhibit) and a scripted `.reveal` message → assert the exhibit transitions locked→revealed and the decrypted bytes are non-empty/decode as an image; a `.reveal` for an unknown exhibit id is ignored → RUN FAIL → implement VM + view → RUN PASS → build → commit `"Add candidate exhibit view with WS-keyed decryption"`.

---

### Task 12: Room audio recording (AVAudioRecorder → chunked upload)

**Files:**
- Create: `ios/CaseRoom/Support/RoomRecorder.swift`, `ios/CaseRoom/State/RecordingUploader.swift`
- Test: `ios/CaseRoomTests/RecordingUploaderTests.swift`

**Interfaces:**
- Consumes: `SessionService.uploadRecordingChunk/completeRecording` (Task 7).
- Produces: `RoomRecorder` — `AVAudioSession` record permission (`NSMicrophoneUsageDescription` added to `project.yml` info.properties), `AVAudioRecorder` writing AAC `.m4a` (`audio/mp4`) to a temp file; start on go-live, stop on debrief. `RecordingUploader.upload(fileURL:, sessionId:)` — reads the finished `.m4a`, splits it into sequential ≤8 MB byte chunks, POSTs each `uploadRecordingChunk(seq:, mime:"audio/mp4", blob:)` starting at seq 0, then `completeRecording`. On a **409 `expected seq N`** it resyncs to N and continues (idempotent resume); it never re-sends an already-applied chunk. (Chunk 0 begins with the `.m4a` `ftyp` box → passes the server's container sniff.)

- [ ] Steps (TDD): `RecordingUploaderTests` with a stub service — feed a synthetic multi-chunk blob; assert chunks upload in order with correct `seq`; simulate a 409 `expected seq 1` after seq 0 and assert the uploader resumes at seq 1 (not 0) and completes; assert `completeRecording` fires once at the end → RUN FAIL → implement uploader (+ recorder; the recorder's live mic capture is exercised manually in Task 15, the uploader/chunking is unit-tested) → RUN PASS → build → commit `"Add room audio recording and chunked resumable upload"`.

**Info.plist:** add `NSMicrophoneUsageDescription` ("Records the room audio of your in-person practice session for later review.") to the app target's `info.properties` in `ios/project.yml`, and verify it lands in the compiled plist (`plutil -p`) — same mechanism P1 used for the calendar/ATS keys.

---

### Task 13: Debrief + finalize

**Files:**
- Create: `ios/CaseRoom/Views/DebriefView.swift`
- Modify: `ios/CaseRoom/State/SessionViewModel.swift` (finalize action)
- Test: `ios/CaseRoomTests/SessionViewModelTests.swift` (extend)

**Interfaces:**
- Consumes: `SessionService.finalize(id, grade:)` (Task 7).
- Produces: interviewer `DebriefView` — review the rubric/grade preview, an optional grade override, a **Finalize** button calling `finalize(grade:)` (state must be `debrief`) → on success the session is finalized and the recorder is stopped/uploaded (Task 12). The candidate sees a "waiting for feedback" state until finalized, then the released grade. After finalize, dismiss the session screen; the session now appears in history (Today/Sessions tabs from P1, `scope=recent`).

- [ ] Steps (TDD): extend `SessionViewModelTests` — `finalize()` calls `service.finalize` only in `debrief` state and marks the VM finalized on success; a non-debrief finalize is blocked → RUN FAIL → implement → RUN PASS → build → commit `"Add debrief and finalize flow"`.

---

### Task 14: QR pairing — create (interviewer) + scan (candidate)

**Files:**
- Create: `ios/CaseRoom/Views/PairCreateView.swift`, `ios/CaseRoom/Views/PairScanView.swift`, `ios/CaseRoom/State/PairViewModel.swift`, `ios/CaseRoom/Support/QRCode.swift`
- Modify: `ios/CaseRoom/Networking/APIClient.swift` (add `pairCreate(caseId:) -> PairToken`, `pairClaim(token:) -> Int`), a session entry point on an existing tab
- Test: `ios/CaseRoomTests/PairViewModelTests.swift`

**Interfaces:**
- Consumes: `POST /api/practice/pair/create {case_id}` → `{token, expires_at}`; `POST /api/practice/pair/claim {token}` → `{session_id}` (Tasks 3–4).
- Produces: `PairViewModel` — interviewer flow: pick a case (reuse P1's Cases browse) → `pairCreate(caseId:)` → render the `token` as a QR (CoreImage `CIFilter.qrCodeGenerator`, via `QRCode.image(from:)`) in `PairCreateView`, then navigate into the created… (note: create only mints a token; the SESSION is created on claim — so the interviewer waits, then opens the session once it exists — poll `sessions(scope:upcoming)` or open when the candidate has claimed). Candidate flow: `PairScanView` uses VisionKit `DataScannerViewController` (QR only) → on scan → `pairClaim(token:)` → open the returned `session_id` in `SessionView` (lobby). Both land in the lobby of a `scheduled`/video-off session.
  - **Interviewer post-mint:** after minting, the interviewer needs the `session_id` once the candidate claims. Simplest: the interviewer polls `GET /api/practice` for a session on this pairing token — add to Task 4's claim a way for the interviewer to discover it, OR (preferred) have `pairCreate` also return nothing extra and the interviewer opens the session by polling `sessions(scope:upcoming)` for the newest session with this case + themselves as interviewer. Pick the simplest reliable path at implementation time and note it in the report.

- [ ] Steps (TDD): `PairViewModelTests` with a stub APIClient — `createPairing(caseId:)` stores the returned token and produces a non-nil QR image; `claim(token:)` returns a session id and drives navigation state → RUN FAIL → implement VM + views (`DataScannerViewController` wrapped in `UIViewControllerRepresentable`; requires `NSCameraUsageDescription` in `project.yml` info.properties — add it + verify via `plutil -p`) → RUN PASS → build → **manual sim note:** the simulator has no camera, so `DataScannerViewController` scan is device-only; document the scan step as a real-device manual check, and unit-test the claim path with the token passed directly → commit `"Add QR pairing: create (interviewer) and scan-to-claim (candidate)"`.

**Info.plist:** add `NSCameraUsageDescription` ("Scans your practice partner's pairing QR code to join the session.") to `ios/project.yml` info.properties; verify in the compiled plist.

---

## Phase E — Verification + handoff

### Task 15: End-to-end verification + handoff

**Files:**
- Modify: `PROGRESS.md`

- [ ] **Step 1: Full backend suite** `.venv/bin/python -m pytest tests/ -q` → all pass (list any pre-existing failures).
- [ ] **Step 2: Full iOS suite** `cd ios && xcodegen && xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test` → all pass.
- [ ] **Step 3: Live backend E2E (HTTP + WS, no UI):** boot `.venv/bin/python main.py serve --port 8077` (seeded a/b@yale.edu). As A: `POST /api/practice/pair/create {case_id}` → token. As B: `POST /api/practice/pair/claim {token}` → `session_id`. Both `GET /api/practice/{session_id}` resolve with the right `your_role`. Drive the state machine over HTTP: consent (both) → `state live` → `POST /reveals {exhibit_id}` → assert a `reveals` row. (A WebSocket client script can additionally assert the `{"type":"reveal",...}` frame arrives on B's socket — optional but strong.) Record status codes + snippets. Stop the server.
- [ ] **Step 4: In-person session smoke (2 sims or sim+web):** if feasible with ≤2 attempts, run two iPhone-17 sims (A interviewer, B candidate) through claim→lobby→consent→live→reveal→rubric→debrief→finalize; else document the interactive/real-device walkthrough (QR scan is device-only — no sim camera) as a MANUAL step. Do NOT sink time into flaky UI automation (watchdog: ≤2 attempts, then document + move on).
- [ ] **Step 5: Update `PROGRESS.md`** — "P2 (in-person session core) — DONE" with evidence lines (command → result), branch/commit, and a **Remaining/manual** list: real-device QR-scan walkthrough, real-device room-audio capture check, and (from P1, still open) Apple portal `.p8` → `.env` for live push. Note next: **P3 — remote WebRTC media + Live Activities + TURN provider decision**.
- [ ] **Step 6: Commit** `"Complete iOS P2: in-person session core, WS reveal, QR pairing"`.

---

## Out of scope for this plan (per spec — planned at their phase boundaries)

- **P3**: WebRTC audio/video (remote sessions), the video-off remote toggle (phone-screen practice), Live Activities / Dynamic Island, and the **TURN provider** owner decision. The `sdp`/`ice` WS relay already exists but stays unused in P2.
- **P4**: on-device Foundation-Models drills, widgets, App Intents/Entities, "free now" instant-match.
- **Fall wave** (iOS 27 GA): Spotlight entity indexing, Siri AI Q&A, on-device transcription + FM feedback summaries of recordings.

## Manual steps only Thomas can do (not blocking simulator/backend work)

1. **Real-device pass** for what the simulator can't do: QR scan (`DataScannerViewController` needs a camera) and live room-mic capture. Free provisioning + a cable is enough for dev; the same App ID `studio.ogee.caseroom` from P1 applies (add the **Camera** + **Microphone** usage strings ship in the app via `project.yml` — no portal change needed for those).
2. Still open from P1: Apple Developer portal App ID Push (+ Time-Sensitive) capability + APNs `.p8` → `.env` for real push; merge `feature/ios-app` (P1) and later `feature/ios-p2`.

## Self-review (author checklist — done)

- **Spec coverage:** lobby/knock/admit (T9) · exhibit fetch→decrypt→reveal, WS-keyed (T1,T8,T11) · web client migrates (T5) · interviewer rubric+timer (T10) · candidate exhibit view (T11) · audio recording + chunked upload (T12) · finalize (T13) · QR one-time-token pairing, VisionKit scan (T2,T3,T4,T14) · "two iPhones in one room run a full case → finalizes into history" (T15). All spec P2 bullets map to a task.
- **No WebRTC in P2** (scope boundary honored — `sdp`/`ice` untouched).
- **Contracts** use the recon-verified endpoint shapes verbatim (rubric PUT body, recordings 409 protocol, AES-GCM tag/nonce split, WS message types).
