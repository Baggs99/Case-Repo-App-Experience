# SPEC — CaseRoom: 1:1 Case-Interview Video Platform

Status: ready to execute · Format: phased plan with task IDs and "Done when" gates
(compatible with spec-executor / PROGRESS.md workflow)

---

## 0. What this is

A case-interview practice platform for MBA students, distributed across schools.
Two logged-in users hold a **one-to-one video call** in which one acts as
**interviewer** and the other as **candidate**. The interviewer works from a case
packet (PDF); the candidate must NOT see the packet or its exhibits until the
interviewer explicitly reveals each exhibit mid-call. Sessions produce a logged
record: reveal timeline, rubric-based feedback and grade, and per-participant
local audio recordings. Users maintain queues of cases they want to receive and
cases they are prepped to give, propose sessions to each other, and see their
history and simple recommendations on a room dashboard.

This spec integrates into the existing repo
`https://github.com/Baggs99/Case-Repo-App-Experience`. The repo could not be
inspected when this spec was written (private / not fetchable), so **Phase 1
is a mandatory discovery phase**: the executing agent inventories what already
exists (auth, users, cases, conventions) and records adaptation decisions in
`INTEGRATION.md` before building. Where this spec names tables, columns, or
paths, treat them as defaults — **reuse existing equivalents where they exist**
and log the mapping as a deviation rather than duplicating.

### Explicitly in scope (v1)
- 1:1 WebRTC calls, P2P-first with TURN relay fallback, 720p max, ~1.2 Mbps cap.
- Rooms with permanent URLs, knock/admit gating, per-session roles.
- Case entities: full PDF (interviewer-only) + exhibits as pre-rendered images,
  preloaded encrypted on the candidate side, revealed instantly via DataChannel
  with a server-side log as the source of truth.
- Case authoring flow (upload PDF, pick exhibit pages, done).
- Rubric templates, live checklist during call, finalize → grade + released feedback.
- Queues (want / can-give), proposals with visible case metadata, accept →
  scheduled session + .ics email invite.
- Room dashboard: history, grades (private by default), queues, SQL-rule
  recommendations.
- Local per-participant audio recording (MediaRecorder, mic only), uploaded at
  call end and stored keyed by session. **Storage only — no transcription.**
- Recording-consent gate at the knock/admit step, logged per participant.

### Explicitly out of scope (v1) — do not build
- Transcription, summarization, or any AI processing of recordings. (Recordings
  are stored so a later pipeline can consume them; that is the only hook.)
- School-admin features (locking cases to a school, admin dashboards). The only
  concession: nullable `school_id` columns exist in the schema so this can be
  added without migration. No UI, no enforcement logic.
- Group calls / SFU, screen sharing (exhibit reveal replaces it), native or
  mobile apps, global presence/online indicators, ML recommendations, payments,
  video recording (audio only).

### Case-visibility rule (get this right — it was corrected during design)
Candidates and proposal recipients **DO see case metadata**: title, source
(school/casebook), sector, case type, difficulty. That is what lets them decide
to queue a case. What stays hidden from the candidate until the appropriate
moment is **content**: the full PDF (hidden until the session is finalized,
then released for review) and each exhibit image (hidden until the interviewer
reveals it during the call). Never leak content through thumbnails, previews,
open directories, or predictable URLs.

---

## 1. Architecture

Two planes on two hosts. Keep them separable.

**App plane — Hostinger shared hosting (existing site), PHP + MySQL.**
Serves all pages and static assets, owns auth and every database table, handles
uploads (case PDFs, exhibit images, recordings), mints signed tokens for the
media plane, generates .ics invites, and is the sole authority on roles,
reveals, grades, and access control. No long-lived processes here.

**Media plane — one small VPS (Hetzner CX22-class, Debian/Ubuntu).**
Two services only:
1. `signal` — a Node.js WebSocket signaling server (single dependency: `ws`).
   Relays SDP offers/answers and ICE candidates between exactly two authorized
   peers per session, runs the knock/admit exchange, and enforces the 2-peer
   + role limits using claims from the app plane's HMAC token. Stateless
   beyond in-memory session maps; holds no database connection.
2. `coturn` — TURN relay for the ~10–20% of pairs that cannot connect P2P.
   Ephemeral credentials only (`use-auth-secret`), never static creds in JS.

TLS on the VPS via Caddy (or nginx + certbot): `wss://signal.<domain>` on 443
proxying to the Node process. coturn listens on 3478 (udp+tcp) and 5349 (tls).

**Trust bridge.** PHP mints a compact HMAC-signed token binding
`{session_id, user_id, role, exp}`; the signaling server verifies it with a
shared secret from its environment. No cross-host DB access, no cookies on the
VPS. TURN credentials are minted the same way (coturn REST-auth convention) and
handed to the client in the same API response.

**Media path.** Browser-native WebRTC. Video capped at 720p/30 and ~1.2 Mbps
via `RTCRtpSender.setParameters`; Opus audio with echoCancellation /
noiseSuppression / autoGainControl. One `RTCDataChannel` per call carries
exhibit-reveal key messages and lightweight in-call events. Media and
DataChannel are P2P (or blind-relayed through coturn) — the servers never see
call content.

**Client.** Vanilla JS ES modules, no framework, no build step. Static assets
served from Hostinger with far-future cache headers. pdf.js is vendored and
loaded **only** on the authoring page. "Maximally efficient" here means: one
WebSocket, P2P media, preloaded exhibits, zero framework payload, lazy
everything that isn't the call.

---

## 2. Global invariants (re-check after every phase)

These are non-negotiable. The final phase includes a verify script that greps
for violations of the mechanical ones; the rest are review items.

- **INV-1 SQL:** every query uses prepared statements / parameterized inputs.
  No request data ever concatenated into SQL.
- **INV-2 Auth:** every `/api/*` endpoint and every non-public page begins by
  resolving the authenticated user via the repo's existing auth helper (or the
  one built in Phase 2). No endpoint trusts client-supplied user IDs.
- **INV-3 Role enforcement is server-side:** full-PDF bytes, exhibit decryption
  keys, and rubric-draft writes are served only to the session's interviewer;
  exhibit keys to the candidate only after a reveal row exists; full PDF to the
  candidate only after `sessions.state = 'finalized'`. UI hiding is never the
  control.
- **INV-4 Secrets:** shared secrets, DB creds, SMTP creds live in a gitignored
  config/env file. Verify `.gitignore` covers it before the first commit that
  references it. Nothing secret in client JS — TURN creds are short-lived and
  minted per call.
- **INV-5 Uploads:** server-side validation of type, size, and ownership on
  every upload (PDF ≤ 40 MB, exhibit image ≤ 2 MB, recording chunk ≤ 8 MB,
  per-session recording total ≤ 150 MB). Stored under non-guessable names in
  directories that deny direct HTTP listing/access; all downloads flow through
  an auth-checked PHP passthrough.
- **INV-6 Content secrecy:** no route, filename pattern, directory index, or
  cache header may expose case PDFs or exhibit images to anyone the role rules
  don't allow. Encrypted exhibit blobs may be served to the session's candidate
  pre-reveal (that is the preload); plaintext bytes and keys may not.
- **INV-7 Git:** all work on a feature branch (`feature/caseroom`). Never
  commit to or push `main` — it auto-deploys. Never force-push. Small
  imperative commits. Maintain PROGRESS.md so any session can resume.
- **INV-8 Style:** match the existing repo's naming, layout, and helper
  patterns (as recorded in INTEGRATION.md). Never reformat unrelated code.
- **INV-9 TURN safety:** coturn runs with `use-auth-secret`, quotas, and
  `denied-peer-ip` rules covering loopback, RFC1918, and link-local ranges so
  the relay cannot reach internal networks.
- **INV-10 Consent:** a session cannot enter `live` state until both
  participants' recording-consent booleans are recorded on the session row.

---

## 3. Data model

Default DDL below (MySQL 8 / MariaDB, InnoDB, utf8mb4). In Phase 1, map to
existing tables where the repo already has equivalents (especially `users` and
anything case-like); prefix new tables to match repo convention if one exists.
Use these definitions verbatim otherwise.

```sql
CREATE TABLE schools (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(120) NOT NULL UNIQUE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- users: reuse the repo's table. Required additions if absent:
--   school_id INT UNSIGNED NULL (FK schools.id)  -- future-lock hook, no logic v1
--   display_name, email must exist in some form (record mapping in INTEGRATION.md)

CREATE TABLE rooms (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  owner_user_id INT UNSIGNED NOT NULL,
  slug VARCHAR(60) NOT NULL UNIQUE,          -- /room/{slug}, permanent, non-secret
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_room_owner (owner_user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE cases (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  title VARCHAR(200) NOT NULL,
  source VARCHAR(120) NOT NULL,              -- e.g. "Kellogg 2019 casebook"
  sector VARCHAR(80) NOT NULL,
  case_type VARCHAR(80) NOT NULL,            -- profitability, market entry, M&A...
  difficulty TINYINT UNSIGNED NOT NULL,      -- 1..5
  school_id INT UNSIGNED NULL,               -- future-lock hook, unused v1
  created_by INT UNSIGNED NOT NULL,
  pdf_path VARCHAR(255) NOT NULL,            -- outside webroot / access-denied dir
  status ENUM('draft','published') NOT NULL DEFAULT 'draft',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY idx_cases_browse (status, sector, case_type, difficulty)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE exhibits (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  case_id INT UNSIGNED NOT NULL,
  idx TINYINT UNSIGNED NOT NULL,             -- display order: Exhibit 1..N
  source_pages VARCHAR(60) NOT NULL,         -- e.g. "4" or "4-5", informational
  enc_blob_path VARCHAR(255) NOT NULL,       -- AES-256-GCM ciphertext of WebP
  enc_key VARBINARY(32) NOT NULL,            -- per-exhibit key, server-side only
  enc_iv VARBINARY(12) NOT NULL,
  width SMALLINT UNSIGNED NOT NULL,
  height SMALLINT UNSIGNED NOT NULL,
  bytes INT UNSIGNED NOT NULL,
  UNIQUE KEY uq_exhibit (case_id, idx),
  CONSTRAINT fk_exhibit_case FOREIGN KEY (case_id) REFERENCES cases(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE rubric_templates (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  case_id INT UNSIGNED NULL,                 -- NULL = generic template
  name VARCHAR(120) NOT NULL,
  items_json JSON NOT NULL,                  -- [{id,label,dimension,max_points}, ...]
  created_by INT UNSIGNED NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE sessions (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  room_id INT UNSIGNED NOT NULL,
  interviewer_id INT UNSIGNED NOT NULL,
  candidate_id INT UNSIGNED NOT NULL,
  case_id INT UNSIGNED NOT NULL,
  rubric_template_id INT UNSIGNED NOT NULL,
  state ENUM('scheduled','lobby','live','debrief','finalized','aborted')
        NOT NULL DEFAULT 'scheduled',
  consent_interviewer TINYINT(1) NOT NULL DEFAULT 0,
  consent_candidate  TINYINT(1) NOT NULL DEFAULT 0,
  scheduled_at DATETIME NULL,
  started_at DATETIME NULL,
  ended_at DATETIME NULL,
  KEY idx_sessions_user_hist (candidate_id, state, ended_at),
  KEY idx_sessions_ivr_hist  (interviewer_id, state, ended_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE reveals (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  session_id INT UNSIGNED NOT NULL,
  exhibit_id INT UNSIGNED NOT NULL,
  revealed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  t_offset_ms INT UNSIGNED NOT NULL,         -- ms since sessions.started_at
  UNIQUE KEY uq_reveal (session_id, exhibit_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE feedback (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  session_id INT UNSIGNED NOT NULL UNIQUE,
  rubric_json JSON NOT NULL,                 -- ticked items + per-item points/notes
  grade DECIMAL(4,1) NULL,                   -- set at finalize
  notes_md TEXT NULL,
  finalized_at DATETIME NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE queue_want (
  user_id INT UNSIGNED NOT NULL,
  case_id INT UNSIGNED NOT NULL,
  added_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, case_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE queue_give (
  user_id INT UNSIGNED NOT NULL,
  case_id INT UNSIGNED NOT NULL,
  added_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, case_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE burned (
  user_id INT UNSIGNED NOT NULL,             -- candidate who has now seen the case
  case_id INT UNSIGNED NOT NULL,
  session_id INT UNSIGNED NOT NULL,
  burned_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, case_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE proposals (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  from_user_id INT UNSIGNED NOT NULL,
  to_user_id INT UNSIGNED NOT NULL,
  case_id INT UNSIGNED NOT NULL,
  from_role ENUM('interviewer','candidate') NOT NULL,  -- role the proposer will take
  message VARCHAR(500) NULL,
  proposed_times_json JSON NULL,             -- ISO strings, optional
  state ENUM('pending','accepted','declined','expired') NOT NULL DEFAULT 'pending',
  session_id INT UNSIGNED NULL,              -- set on accept
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  responded_at DATETIME NULL,
  KEY idx_prop_inbox (to_user_id, state, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE recordings (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  session_id INT UNSIGNED NOT NULL,
  user_id INT UNSIGNED NOT NULL,
  role ENUM('interviewer','candidate') NOT NULL,
  path VARCHAR(255) NOT NULL,
  mime VARCHAR(60) NOT NULL,                 -- audio/webm or audio/mp4 (Safari)
  bytes INT UNSIGNED NOT NULL DEFAULT 0,
  chunks INT UNSIGNED NOT NULL DEFAULT 0,
  completed TINYINT(1) NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_rec (session_id, user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

Foreign keys omitted above where the referenced table is repo-owned (`users`);
add them where the discovered schema allows.

---

## 4. Key mechanisms (contracts the implementation must satisfy)

### 4.1 Auth bridge: HMAC session token (PHP → Node)
- PHP endpoint `POST /api/sessions/{id}/join-token` (auth required; caller must
  be that session's interviewer or candidate; session state `scheduled|lobby|live`).
- Token = `base64url(payload) . "." . base64url(HMAC_SHA256(base64url(payload), SIGNALING_SHARED_SECRET))`
  with payload JSON `{"sid":<session_id>,"uid":<user_id>,"role":"interviewer"|"candidate","exp":<unix+7200>}`.
- Response also carries the ICE config: `{token, ws_url, ice_servers:[{urls:["stun:..."]},{urls:["turn:HOST:3478?transport=udp","turn:HOST:3478?transport=tcp","turns:HOST:5349"],username,credential}]}`.
- TURN creds per coturn REST convention: `username = "<unix_expiry>:<uid>"`,
  `credential = base64(HMAC_SHA1(username, TURN_STATIC_SECRET))`, TTL 2 h.
- Node verifies signature + expiry on WS `hello`, then trusts `{sid, uid, role}`.
  Constant-time compare on both hosts.

### 4.2 Signaling protocol (WebSocket, JSON messages)
`hello{token}` → `ok{role, peer_present}` | close(4401) ·
`knock` (candidate, auto after hello) → owner gets `knock{uid, display_name}` ·
`admit` / `deny` (interviewer only) ·
`sdp{description}` and `ice{candidate}` — relayed only after admit, only
between the session's two authorized sockets ·
`bye`, `ping`/`pong` (30 s heartbeat; kill dead sockets).
Server rules: max one socket per (sid, uid) — a newer socket replaces the old
(reconnect support); never more than the two token-named users per sid; drop
any message type not listed; never log SDP/ICE contents (metadata-only logs).

### 4.3 WebRTC configuration
- `getUserMedia`: video `{width:{ideal:1280,max:1280}, height:{ideal:720,max:720}, frameRate:{ideal:30,max:30}}`;
  audio `{echoCancellation:true, noiseSuppression:true, autoGainControl:true}`.
- After `addTrack`, cap the video sender:
  `const p = sender.getParameters(); p.encodings[0].maxBitrate = 1_200_000; await sender.setParameters(p);`
- Implement the **perfect negotiation** pattern (interviewer = impolite,
  candidate = polite) so simultaneous (re)negotiation never glares.
- `oniceconnectionstatechange`: on `disconnected` wait 3 s then `restartIce()`;
  on `failed`, `restartIce()` immediately; surface a reconnect banner in UI.
- Create one negotiated DataChannel `{id:0, negotiated:true, ordered:true}`
  labelled `ctrl` on both sides — used for reveals and in-call pings; keeps
  channel setup out of the SDP race.
- Full ICE (no `iceTransportPolicy` override) except behind the debug flag
  `?forceRelay=1` → `iceTransportPolicy:'relay'` for TURN testing.

### 4.4 Exhibit preload + reveal (the core feature)
Authoring time (Phase 5): each selected exhibit is rendered to WebP **in the
author's browser** (pdf.js canvas at 2× scale, quality ~0.82, longest edge
≤ 1800 px) and uploaded. Server encrypts each image once with AES-256-GCM
(`openssl_encrypt`, random 32-byte key + 12-byte IV per exhibit, tag appended
to ciphertext) and stores `{enc_blob_path, enc_key, enc_iv}`. Client-side
rendering deliberately avoids any server binary dependency (poppler etc.) on
shared hosting.

Session time:
1. On entering `live`, the candidate client fetches the exhibit **manifest**
   (`GET /api/sessions/{id}/exhibits` → `[{exhibit_id, idx, bytes, iv_b64}]` —
   no keys) and preloads every encrypted blob
   (`GET /api/sessions/{id}/exhibit-blob/{exhibit_id}`, role-checked) into
   memory as ArrayBuffers. UI shows N locked slots.
2. The interviewer client fetches the same manifest **plus keys**
   (`GET /api/sessions/{id}/exhibit-keys`, interviewer-only) and sees live
   thumbnails of all exhibits alongside the full PDF.
3. Interviewer clicks **Send Exhibit k** → client simultaneously
   (a) sends `{type:'reveal', exhibit_id, key_b64}` over the `ctrl`
   DataChannel and (b) `POST /api/sessions/{id}/reveals {exhibit_id}` (server
   writes the reveal row with `t_offset_ms`). The POST is the system of
   record; the DataChannel is the fast path.
4. Candidate client decrypts with WebCrypto
   (`crypto.subtle.importKey('raw',…,'AES-GCM')` → `decrypt({iv})`), renders
   the WebP into the exhibit tray, flips slot k to unlocked. Perceived reveal
   latency: single-digit milliseconds.
5. **Fallback:** if the DataChannel is down or the key message is missed, the
   candidate may call `GET /api/sessions/{id}/exhibit-key/{exhibit_id}`, which
   returns the key **iff a reveal row exists**. Candidate polls this only after
   seeing a reveal notification via signaling or on reconnect (client also
   reconciles: on reconnect, fetch reveal list and pull any missing keys).
Accepted tradeoff (do not "fix"): keys are per-exhibit, not per-session, so a
candidate retains the ability to decrypt blobs they were already shown. That is
equivalent to having seen the image; the case is burned for them regardless.

### 4.5 Session lifecycle & state machine
`scheduled → lobby` (either party opens the session page) →
`live` (owner admitted + both consent booleans true; server stamps
`started_at`) → `debrief` (call ended; video torn down; rubric still editable;
candidate STILL cannot see full PDF) → `finalized` (interviewer clicks
Finalize: grade computed/confirmed, feedback released, `burned` row written,
candidate gains full-PDF access, case auto-removed from candidate's
`queue_want` and from the interviewer's `queue_give` only if they choose) →
terminal. `aborted` from any pre-debrief state; nothing released. All
transitions server-validated (no skipping, correct actor).

### 4.6 Local recording (storage only)
- Each client records **its own mic track only**:
  `new MediaRecorder(new MediaStream([localAudioTrack]), {mimeType, audioBitsPerSecond: 32000})`
  with `mimeType` feature-detected: `audio/webm;codecs=opus` (Chrome/Firefox)
  else `audio/mp4` (Safari).
- `start(60000)`: every 60 s chunk is uploaded immediately —
  `POST /api/sessions/{id}/recordings/chunk` (fields: seq, blob) — and the
  server appends to the user's session file in arrival-guaranteed order
  (client retries with backoff; server rejects out-of-order seq with 409 and
  client re-sends). Immediate chunk upload means a crashed tab loses ≤ 60 s.
- On `debrief`, client calls `stop()`, flushes the final chunk, then
  `POST /api/sessions/{id}/recordings/complete` → server sets
  `completed=1, bytes, chunks`.
- Files live under a deny-all directory, named
  `rec_{session}_{uid}_{rand16}.{ext}`; download only via authed passthrough
  restricted to the two participants. Enforce INV-5 limits.
- ~32 kbps ≈ 14 MB/hour/side. No processing of any kind afterward (v1).

### 4.7 Proposals, queues, scheduling
- Browse/case pages show metadata to everyone (per §0 visibility rule) with
  Add-to-Want / Add-to-Give buttons; Give additionally requires confirming
  "I've read this case" (client-side honesty check only).
- Visiting `/room/{slug}` of another user shows: their public stats (session
  count, streak — never grades), and the **intersection lists**:
  "cases in your Give ∩ their Want" and "cases in your Want ∩ their Give",
  excluding cases burned for the would-be candidate. One SQL join each.
- Propose = pick case + role + optional message + up to 3 proposed times →
  `proposals` row → recipient's inbox (badge in nav; no realtime needed).
- Accept (optionally picking one time) → create `sessions` row
  (`scheduled_at` set or NULL for "now"), link proposal, email both parties an
  **.ics invite** (RFC 5545: METHOD:REQUEST, stable UID
  `caseroom-{session_id}@{domain}`, UTC DTSTART/DTEND with 45-min default
  duration, ORGANIZER/ATTENDEE mailto, escaped SUMMARY "Case practice:
  {title}", DESCRIPTION with the session URL) via the repo's existing mail
  path or PHP mail()/Hostinger SMTP. Also offer the .ics as a download link.
- Decline / 7-day expiry close the proposal.

### 4.8 Dashboard & recommendations (SQL only, no ML)
Own room shows: upcoming sessions, proposal inbox, both queues, session
history with grades and per-dimension rubric averages over the last 10
sessions (one GROUP BY over `feedback.rubric_json` extractions), and a
"Recommended next" panel built from three rules, in order:
1. **Coverage gap:** case types with the fewest finalized candidate-sessions
   for this user → suggest highest-rated unburned published case of that type.
2. **Difficulty ladder:** if the mean grade over the last 3 finalized sessions
   ≥ 4.0/5, suggest difficulty +1 of their most-practiced type.
3. **Weak dimension:** lowest-averaging rubric dimension → suggest cases whose
   rubric template weights that dimension heaviest.
Each rule is a bounded query; union, dedupe, cap at 5, exclude burned/queued.

---

## 5. HTTP API surface (app plane, PHP)

All endpoints: auth required (INV-2), JSON in/out unless noted, parameterized
SQL (INV-1). Adapt path style to the repo's existing API convention.

| Endpoint | Actor | Purpose |
|---|---|---|
| `GET  /api/me` | any | id, name, room slug (reuse if repo has one) |
| `GET  /api/cases` `?sector&type&difficulty&q` | any | browse metadata only |
| `POST /api/cases` | any | create draft (metadata) |
| `POST /api/cases/{id}/pdf` | author | upload full PDF (multipart) |
| `POST /api/cases/{id}/exhibits` | author | upload rendered WebP + idx + source_pages; server encrypts |
| `POST /api/cases/{id}/publish` | author | validate ≥1 exhibit + rubric, flip status |
| `GET  /api/cases/{id}/pdf` | author, session interviewer, or finalized candidate | passthrough download (INV-3/6) |
| `GET/POST/DELETE /api/queues/(want\|give)/{case_id}` | any | queue management |
| `GET  /api/rooms/{slug}` | any | public room view + intersections vs. viewer |
| `POST /api/proposals` · `POST /api/proposals/{id}/(accept\|decline)` | pair | §4.7 |
| `POST /api/sessions/{id}/join-token` | participant | §4.1 token + ICE config |
| `POST /api/sessions/{id}/consent` | participant | set own consent boolean |
| `GET  /api/sessions/{id}/exhibits` | participant | manifest, no keys |
| `GET  /api/sessions/{id}/exhibit-blob/{eid}` | participant | encrypted blob (preload) |
| `GET  /api/sessions/{id}/exhibit-keys` | interviewer | all keys (call start) |
| `POST /api/sessions/{id}/reveals` | interviewer | log reveal (system of record) |
| `GET  /api/sessions/{id}/reveals` | participant | reveal list (reconcile) |
| `GET  /api/sessions/{id}/exhibit-key/{eid}` | candidate | key iff revealed (fallback) |
| `POST /api/sessions/{id}/state` | role-dependent | validated transitions §4.5 |
| `GET/PUT /api/sessions/{id}/rubric` | interviewer | draft rubric state |
| `POST /api/sessions/{id}/finalize` | interviewer | grade, release, burn |
| `GET  /api/sessions/{id}/feedback` | candidate (post-finalize) | released feedback |
| `POST /api/sessions/{id}/recordings/chunk` · `/complete` | participant | §4.6 |
| `GET  /api/sessions/{id}/recordings/{uid}` | the two participants | authed download |
| `GET  /api/dashboard` | any | history, trends, recommendations |
| `GET  /ics/session-{id}.ics` | participant | calendar file |

---

## 6. Phases

Execute one phase per session. Every task fully — no stubs. Prove each
"Done when" with a recorded command → result; checks needing the live VPS or
Hostinger may be deferred **with reason** and listed in the phase report.

### Build order
P1 → all. P2 → P4, P7, P8, P9. P3 → P4. P5 → P6. P4 ∧ P6 → P7. P4 → P10.
P3 is independent of P2 (can run in parallel streams). P11 last.

---

### Phase 1 — Repo discovery, foundations, schema
- **T1.1** Clone/pull; create branch `feature/caseroom`. Inventory the repo:
  stack + versions, auth mechanism and its helper functions, existing tables
  (esp. users and anything case-like), routing/API conventions, mail path,
  deploy layout, `.gitignore` coverage. Write findings + this spec's
  table/column/path mappings into `INTEGRATION.md` at repo root.
- **T1.2** Create gitignored config (match repo convention; else
  `config/caseroom.env.php` + committed `.example`): DB creds reference,
  `SIGNALING_SHARED_SECRET`, `TURN_STATIC_SECRET`, `TURN_HOST`, `SIGNAL_WS_URL`,
  `SMTP_*`, upload dirs, size limits. Confirm `.gitignore` covers it **before
  first commit** (INV-4).
- **T1.3** Write `db/migrations/001_caseroom.sql` from §3 (as mapped in
  T1.1) plus a tiny idempotent PHP migration runner if the repo lacks one.
  Apply to the dev database.
- **T1.4** Scaffold shared PHP helpers consistent with repo style: `db()`
  (PDO, exceptions on), `require_auth()`, `json_out()`, `hmac_token()` /
  `verify_role()` per §4.1, upload validators per INV-5.
- **Done when:** `INTEGRATION.md` exists and answers every T1.1 question;
  `git branch --show-current` = `feature/caseroom`; migration applies cleanly
  twice (idempotent) — show `SHOW TABLES` output; `php -l` passes on every new
  file; grep shows the config file is untracked.

### Phase 2 — Auth integration, rooms, session skeleton
- **T2.1** Wire `require_auth()` to the repo's real auth (or, only if none
  exists, build minimal email+password session auth with `password_hash`,
  regenerated session IDs, and a login page matching repo style — log which
  path was taken).
- **T2.2** Rooms: auto-create one room per user on first login (slug from
  display name, deduped); `/room/{slug}` page shell rendering owner identity
  and placeholder panels.
- **T2.3** Session CRUD: create (given pair, case, roles, rubric template),
  read, and the §4.5 state-transition endpoint with full server-side
  validation of actor + legal transition + consent gating into `live`.
- **T2.4** `POST /api/sessions/{id}/join-token` per §4.1 including TURN cred
  minting (values from config; VPS need not exist yet).
- **Done when:** two test users can log in; each has a room URL; a session
  row can be created and walked `scheduled→lobby` via curl with auth cookies;
  illegal transitions and wrong-actor calls return 403 (show curl evidence);
  join-token response validates against a reference HMAC computed in a
  one-off script; `php -l` clean.

### Phase 3 — Media plane: signaling server + coturn (VPS)
- **T3.1** `signal/` dir in repo: `server.js` (Node ≥ 20, dependency: `ws`
  only) implementing §4.2 exactly, secrets via env, listens on
  `127.0.0.1:8443` for a TLS-terminating proxy. Include `signal/README.md`.
- **T3.2** Unit-test the token verifier and message router with `node --test`
  (no framework): valid/expired/forged tokens; third-socket rejection;
  sdp/ice relay only post-admit; reconnect replaces socket.
- **T3.3** Deploy artifacts: `deploy/signal.service` and
  `deploy/coturn.conf` (use-auth-secret, static-auth-secret placeholder,
  realm, fingerprint, ports 3478 udp/tcp + 5349 tls, cert paths,
  `total-quota`, `user-quota`, `denied-peer-ip` for 127.0.0.0/8, 10.0.0.0/8,
  172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, ::1, fc00::/7,
  `no-multicast-peers`), `deploy/Caddyfile` (wss on 443 → 8443), and
  `deploy/vps-setup.md` runbook (Debian 12: node LTS, coturn, caddy, ufw
  allowing 22/80/443/3478/5349 + relay range 49152–65535/udp).
- **T3.4** Local integration test: run server.js locally; script two `ws`
  clients through hello→knock→admit→sdp/ice relay→bye.
- **Done when:** `node --test` passes (paste summary); the two-client local
  script transcript shows correct relay and rejections; `caddy validate` /
  config lint on deploy files; live-VPS bring-up recorded as deferred if no
  host is available this session.

### Phase 4 — Call experience
- **T4.1** Session page `/session/{id}`: lobby view (device pickers via
  `enumerateDevices`, local preview, **recording-consent checkbox** posting
  to `/consent`, knock state) and live view (remote video full-bleed, local
  PiP, mute/cam toggles, end-call). Vanilla JS modules:
  `signal.js`, `rtc.js`, `ui.js`.
- **T4.2** WebRTC per §4.3: perfect negotiation, bitrate cap verified via
  `getStats()` debug readout, negotiated `ctrl` DataChannel, ICE-restart
  handling with reconnect banner, `?forceRelay=1` flag.
- **T4.3** Knock/admit UX: candidate auto-knocks; interviewer sees admit/deny
  modal; admit + both consents → server transition to `live`; deny returns
  candidate to lobby with message.
- **T4.4** Teardown: end-call → `debrief` transition, tracks stopped, ws
  closed; tab-close (`pagehide`) sends best-effort `bye` + `sendBeacon` state
  ping; survivor sees "peer left".
- **Done when:** on the dev machine, two browser profiles complete a full
  call (evidence: screenshot or getStats bitrate lines ≤ ~1.3 Mbps and
  resolution ≤ 1280×720); consent gating blocks `live` until both boxes
  checked (curl/DB evidence); DataChannel echo test passes; forced-relay mode
  deferred-or-shown depending on VPS availability.

### Phase 5 — Case authoring
- **T5.1** Vendor pdf.js (pin version, local copy, loaded only here).
  `/cases/new` flow: metadata form → PDF upload (INV-5) → thumbnail grid of
  all pages rendered client-side → author multi-selects exhibit pages/ranges
  and orders them.
- **T5.2** Client renders each selected exhibit to WebP per §4.4 params and
  uploads with idx + source_pages; server validates, encrypts AES-256-GCM,
  stores blob + key + iv (T1.4 helpers). JPEG fallback if `toBlob('image/webp')`
  unsupported (Safari ≤ 15) — record mime.
- **T5.3** Rubric template editor: generic templates + per-case override;
  items = {label, dimension ∈ {structure, quant, insight, communication,
  synthesis}, max_points}; store items_json. Seed 1 generic template.
- **T5.4** Publish validation (≥1 exhibit, rubric attached, metadata
  complete); case detail page showing metadata to all, PDF/exhibit access per
  INV-3/6.
- **Done when:** a real multi-page PDF authored end-to-end on dev produces N
  encrypted blobs (show `exhibits` rows + files); a direct unauthenticated
  request to a blob/PDF path returns 403/404 (curl evidence); decrypting one
  blob with a PHP one-off script using stored key/iv yields a valid WebP
  (show file header); `php -l` clean.

### Phase 6 — In-call case machinery (reveal system)
- **T6.1** Interviewer call-side panel: full-PDF viewer (pdf.js already
  vendored; lazy-load), exhibit strip with thumbnails + **Send** buttons,
  sent-state indicators.
- **T6.2** Candidate exhibit tray: locked slots from manifest, preload of all
  encrypted blobs with progress indicator, WebCrypto decrypt-on-key, unlocked
  full-size view (click to enlarge), no download affordance (and INV-6 means
  none is load-bearing).
- **T6.3** Reveal flow per §4.4 steps 3–5 including DataChannel message,
  system-of-record POST, fallback key endpoint, and reconnect reconciliation
  (on rejoin: fetch reveal list, pull missing keys, restore tray state).
- **T6.4** Reveal timeline written with `t_offset_ms`; debrief view lists
  reveals with timestamps for both parties.
- **Done when:** in a two-profile dev call, candidate devtools Network shows
  only ciphertext fetched pre-reveal (evidence: response bytes ≠ WebP magic);
  clicking Send unlocks the exhibit on the far side; killing the DataChannel
  (devtools) then revealing still unlocks via fallback within one poll;
  reveal rows carry sane offsets; reloading the candidate tab mid-call
  restores revealed exhibits.

### Phase 7 — Rubric, feedback, finalize, burn
- **T7.1** Interviewer live checklist beside the call: tick items, per-item
  points + note; autosaves draft to `PUT /rubric` (debounced); persists into
  debrief.
- **T7.2** Finalize: grade = normalized rubric score (editable before
  confirm), writes `feedback.finalized_at`, transitions session, inserts
  `burned`, removes case from candidate's want-queue, releases feedback +
  full PDF to candidate (INV-3 flip).
- **T7.3** Candidate post-finalize view: grade, per-dimension breakdown,
  notes, reveal timeline, link to full PDF, link to own recording.
- **Done when:** full happy path on dev: call → debrief → finalize; candidate
  PDF request 403 pre-finalize and 200 post (curl evidence); burned case no
  longer appears in that user's browse/recommendation/intersection queries
  (SQL evidence); draft rubric survives a page reload.

### Phase 8 — Queues, proposals, room visiting, .ics
- **T8.1** Queue endpoints + buttons on case pages; own-room queue panels.
- **T8.2** Visiting view per §4.7 with the two intersection lists (exclude
  burned) and public-stats-only display.
- **T8.3** Proposal create/inbox/accept/decline/expire (expiry via
  on-page-load sweep — no cron on shared hosting) with nav badge.
- **T8.4** Accept → session creation + .ics per §4.7, emailed through the
  repo's mail path (or SMTP config), plus download link. Validate the file
  against an RFC 5545 linter or import test.
- **Done when:** user A proposes to user B from B's room; B accepts; a
  scheduled session exists linking both + proposal (SQL evidence); the .ics
  imports cleanly into at least one real calendar client or passes a
  validator (state which); declined and expired paths verified; intersection
  math shown correct by a seeded fixture (≥ 3 users, ≥ 6 cases, ≥ 1 burned).

### Phase 9 — Dashboard & recommendations
- **T9.1** Dashboard endpoint + page: upcoming, inbox badge, queues, history
  table (date, case, role, counterpart, grade), per-dimension averages
  (last 10 finalized as candidate).
- **T9.2** The three recommendation rules of §4.8 as bounded queries; panel
  shows up to 5 with the rule that produced each.
- **T9.3** Privacy defaults enforced: grades and feedback never in any
  other-user view or endpoint (audit every Phase 8/9 query).
- **Done when:** seeded fixture produces visibly correct trend numbers
  (hand-computed comparison recorded); each rule demonstrated firing on the
  fixture; a second user's dashboard/API calls cannot retrieve the first
  user's grades (curl evidence).

### Phase 10 — Local recording pipeline
- **T10.1** `recorder.js` per §4.6: feature-detected mime, 60 s timeslice,
  immediate chunk upload with seq + retry/backoff, complete call on debrief,
  visible recording indicator whenever active.
- **T10.2** Chunk endpoint: seq ordering (409 on gap), INV-5 limits, append
  under deny-all dir; complete endpoint finalizes row.
- **T10.3** Authed download passthrough for participants; recording listed on
  the session debrief/finalized views.
- **T10.4** `.htaccess` (or equivalent) deny rules on all upload dirs
  verified.
- **Done when:** a ≥ 3-minute dev call yields a playable audio file per
  participant (play it; note duration and bytes ≈ 32 kbps math); killing the
  tab mid-call loses at most the final minute (chunk count evidence);
  direct URL access to a recording file returns 403/404; oversize chunk
  rejected (curl evidence).

### Phase 11 — Hardening, verify script, deploy runbook
- **T11.1** `scripts/verify_caseroom.sh`: greps for (a) request superglobals
  concatenated into SQL-looking strings, (b) `/api/` files missing the auth
  helper call, (c) secret-looking literals in tracked files, (d) upload dirs
  missing deny rules, (e) `console.log` of SDP/keys. Advisory findings; fix
  or justify each in PROGRESS.md.
- **T11.2** Cross-browser pass: Chrome + Safari (macOS) minimum — call,
  reveal, recording (Safari mp4 path), authoring (WebP fallback). Log quirks
  in INTEGRATION.md.
- **T11.3** Failure-mode pass: mid-call network drop (toggle wifi) recovers
  via ICE restart or surfaces reconnect UI; signaling-server restart mid-call
  → clients reconnect ws and resume; candidate reload mid-call restores
  state (re-verify Phase 6 reconciliation end-to-end).
- **T11.4** Docs: finalize `INTEGRATION.md`; write `DEPLOY.md` — Hostinger
  branch-merge flow (never push main: open PR / leave branch for owner to
  merge), VPS runbook from T3.3 with DNS + cert steps, config checklist,
  and a 10-line smoke test for production.
- **T11.5** Housekeeping: confirm no stray TODOs/stubs (`grep -rn "TODO\|FIXME"`
  on new code), commit log clean, PROGRESS.md complete.
- **Done when:** verify script runs clean or every hit is justified; both
  browsers pass the checklist; the three failure modes behave as specified
  (notes + evidence); DEPLOY.md exists and a cold read of it contains every
  secret/DNS/port step needed; final branch pushed, **main untouched**.

---

## 7. Agent operating rules

1. Branch `feature/caseroom` for everything; **never** commit to or push
   `main` (auto-deploys). Never force-push. Small imperative commits, each
   phase ends with one commit including PROGRESS.md.
2. Maintain PROGRESS.md (phases, evidence lines, deviations, log) so a
   dropped session resumes losslessly.
3. Finish completely: no placeholder functions, no "rest follows the same
   pattern". Genuinely deferred items are listed explicitly at phase end.
4. Verify before claiming done: run it, show the command → result. "Should
   work" doesn't count.
5. Ask only when truly blocked, one question with a recommended default.
   Architecture changes (new table, new dependency, different trust model)
   require asking; everything else is a logged deviation.
6. Match existing repo style; never reformat unrelated code. Comments explain
   *why*.
7. Dependency budget: VPS Node service may use `ws` and nothing else; the PHP
   side uses no Composer packages unless the repo already does; the client
   uses vendored pdf.js on exactly two pages and no framework.

## 8. Flagged decisions for the owner (review, then proceed)

- **D1 turns:443.** coturn TLS sits on 5349, because 443 is taken by the wss
  proxy on the single VPS IP. Networks that allow only 443 will fail TURN.
  Fix later if real users hit it: one extra IP (~€1/mo) dedicated to
  coturn:443. Spec proceeds with 5349.
- **D2 Recording retention.** No auto-deletion in v1; ~28 MB/session-hour
  total. Revisit if storage matters.
- **D3 Consent copy.** Checkbox text is a placeholder ("I consent to this
  session being recorded by both participants for feedback purposes");
  owner supplies final wording — some US states require all-party consent.
- **D4 Casebook copyright.** The system stores user-uploaded school casebook
  content. Distribution breadth is a policy decision outside this build;
  schema supports later restriction via `school_id`.
- **D5 Grades privacy.** Hard default: grades visible only to the graded user
  and the grading interviewer for that session. Any future leaderboard is a
  deliberate product change, not a toggle.

## 9. Environment reference

```
# config/caseroom.env.php (gitignored) — shape, not values
DB_*                    → reuse repo's existing connection config
SIGNALING_SHARED_SECRET → 64 hex chars, same value in signal service env
TURN_STATIC_SECRET      → 64 hex chars, same value in coturn.conf
TURN_HOST               → turn.<domain>
SIGNAL_WS_URL           → wss://signal.<domain>/ws
SMTP_HOST/USER/PASS/FROM (or repo mail path)
UPLOAD_DIR_CASES / _EXHIBITS / _RECORDINGS   → outside webroot or deny-all
MAX_PDF_MB=40  MAX_EXHIBIT_MB=2  MAX_REC_CHUNK_MB=8  MAX_REC_TOTAL_MB=150
```

VPS sizing: 2 vCPU / 4 GB / 20 TB-included traffic class. Expected relay load
at 100 concurrent calls with ~15% relayed ≈ 40 Mbps peak — negligible.
Signaling load is a few KB per call setup.

— end of spec —
