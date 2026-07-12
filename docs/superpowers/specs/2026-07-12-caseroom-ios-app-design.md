# CaseRoom iOS App — Design Spec

Date: 2026-07-12 · Status: approved by Thomas (brainstorm session) · Branch: `feature/caseroom`

## Context for a cold reader

CaseRoom is a 1:1 case-interview practice platform (case repository + live
practice sessions) built into this repo (`Baggs99/Case-Repo-App-Experience`,
FastAPI + Jinja2 + Postgres + R2). Working copy: `/Users/thomaskgould/dev/Case-Repo-App-Experience`
(the `~/Documents/Projects/mycase/Case-Repo-App-Experience` path is a symlink — never work through it).
Web app status: phases 1–10 of 11 done; see repo `PROGRESS.md` and `INTEGRATION.md` (binding
spec→repo deviations DV-1..13). Web spec: `docs/caseroom-spec.md`. Brand: `mycase/myCase Style Guide.html`
(in the sibling `mycase/` project dir).

**This spec covers the iPhone app** and the backend changes it needs. Platform research
basis: `/Users/thomaskgould/Documents/Projects/AppleDev/ios-features.md` (iOS 26/27
capability reference with evidence grades — consult it before relying on any Apple API;
respect its [VERIFY-FIRST] flags).

### What exists today (server side, reuse — don't rebuild)

- Auth: email signup (school-domain allowlist), argon2id, server-side sessions,
  HttpOnly cookie, 30-day expiry. No JWT.
- Case repo: 467 cases, full-text search + filters, PDF download, page previews.
- Sessions: state machine `scheduled → lobby → live → debrief → finalized`, consent
  gate before live. Signaling WebSocket `/ws/practice/{session_id}` with message types
  knock/admit/sdp/ice/bye. In-process peer map ⇒ **single-worker only**.
- Exhibits: server renders PDF pages → WebP ≤1800px, AES-256-GCM encrypted; client
  preloads ciphertext; reveal key currently sent over WebRTC DataChannel; server logs reveals.
- Rubric: 5-point dimensions, click-to-score, draft autosave; finalize = grade 0–5.0 + notes;
  feedback released to candidate post-call.
- Recordings: mic-only MediaRecorder, chunked upload (8 MB chunks, 150 MB cap,
  409 = chunk already applied), both participants.
- Scheduling: want/give queues, proposals (message + up to 3 times), accept → session
  + .ics email via Resend.
- Dashboard: finalized count, weekly streak, last-50 history, per-dimension trend,
  SQL recommendations (coverage gaps, difficulty ladder, weak dimension).

## Decisions made (do not relitigate)

1. **Native SwiftUI iPhone app** — not a wrapper, not a PWA. Built with iOS 26 SDK
   (system controls get Liquid Glass free); deployment target iOS 17+.
2. **v1 includes live calls** (full app, not a companion), but built session-spine:
   the no-media session core ships before WebRTC media.
3. **In-person mode is NOT a new session type.** It is a standard session with video
   off and exhibits on — same state machine, same rubric, same history/streak credit.
4. **Nearby pairing v1 = QR one-time token** (interviewer shows, candidate scans).
   Bring-devices-close (GroupActivities / MultipeerConnectivity) is an enhancement
   pending API verification — [VERIFY-FIRST].
5. **Exhibit key reveal moves from DataChannel to the signaling WebSocket**, so
   exhibits work with no RTCPeerConnection (video-off sessions). Server keeps logging
   reveals. Web client migrates to the same path (one protocol, two clients).
6. **Push = APNs direct from FastAPI** (HTTP/2 + .p8 key). No Firebase, no paid service.
7. **Goals ranked**: session liquidity (push) ≥ daily habit ≥ Siri/system integration.
   Post-session AI analysis is a fall item.
8. All Apple-Intelligence features are runtime-gated
   (`SystemLanguageModel.default.availability`) with non-AI fallbacks — the FM hardware
   floor (iPhone 15 Pro+) excludes many students, so fallbacks are mandatory, not polish.

## Architecture

- **One backend, two frontends.** FastAPI grows a `/api/v1/*` JSON layer beside the
  Jinja2 pages. No logic forks: routes call the same service functions as the pages.
- **Auth for the app**: reuse server sessions via URLSession cookie storage. If APNs
  device-token registration proves awkward against cookie expiry, mint long-lived
  device tokens then — decision deferred to implementation, default is cookies.
- **Signaling**: the app speaks the existing WS protocol. Single-worker constraint
  stands for now; Redis pub/sub is the known scale fix, deferred.
- **Exhibit crypto on device**: CryptoKit AES-256-GCM decrypt of the same ciphertext
  blobs. No plaintext before reveal, same as web.
- **In-person recording**: interviewer's device records the room mic; same chunked
  upload endpoints (8 MB / 150 MB / 409-idempotent).
- **App structure**: SwiftUI, four tabs — Today / Cases / Sessions / You. System
  components over custom chrome (Liquid Glass for free, iOS 27 forward-compatible).
  Brand: translate myCase tokens (see style guide) to asset-catalog colors; token-based
  light/dark like the web session page.

## Phases (session-spine roadmap)

### P1 — Foundation + liquidity
App shell (4 tabs), `/api/v1` for auth + case browse/search/detail + proposals inbox
+ accept/decline + dashboard stats; APNs infra server-side; pushes for knock, proposal
received, proposal accepted, session starting soon, feedback released; EventKit
calendar add on accept (write-only access, `NSCalendarsWriteOnlyAccessUsageDescription`).
**Done when:** a proposal push arrives on a real iPhone, accepting it in-app puts the
session in the phone's calendar.

### P2 — Session core, no media → in-person mode ships
Native session screen: lobby/knock/admit over existing WS; exhibit
fetch → decrypt → reveal (WS-keyed, decision 5); interviewer rubric + timer clipboard;
candidate exhibit view; audio recording + chunked upload; finalize flow. QR pairing:
interviewer's phone displays a one-time session token QR, candidate scans
(VisionKit `DataScannerViewController`), both land in the lobby of a video-off session.
**Done when:** two iPhones in one room run a full case — exhibits revealed, rubric
scored, room audio recorded — and it finalizes into history like any session.

### P3 — Remote media → full parity
WebRTC audio/video on the session screen (same perfect-negotiation protocol as
`static/js/rtc.js`); the video-off toggle used remotely = phone-screen practice mode;
Live Activities + Dynamic Island for lobby countdown and live session timer
(ActivityKit; push-updated via ActivityKit push tokens). Requires TURN for cellular
NAT — forces the pending owner decision (Cloudflare Calls vs self-hosted coturn).
**Done when:** iPhone↔desktop video session completes over cellular.

### P4 — Habit + Siri layer
- Drill of the day: on-device Foundation Models generates solo drills (market sizing,
  mental math, framework recall) with `@Generable` guided generation checking
  structured answers; offline, zero API cost. Fallback on non-AI hardware: server
  drill bank (plain templates), same UI.
- Widgets: streak + next-session, home and lock screen (WidgetKit).
- App Intents + App Entities: cases, sessions, proposals as entities; intents
  Start Drill / Next Session / I'm Free Now → Siri, Shortcuts, Action button,
  interactive widgets. (Entities are deliberately early: iOS 27 Siri AI + Spotlight
  semantic index pick them up in fall for free.)
- "Free now" availability toggle + instant-match push.
**Done when:** drill runs offline on AI hardware and via fallback in the simulator;
widgets show live data; Siri executes all three intents.

### Fall wave (iOS 27 GA ~Sept 2026) — explicitly deferred, do not build now
Entity schemas into Spotlight semantic index; Siri AI Q&A over sessions/cases;
PCC free tier (Small Business Program gate) backing drills on non-AI hardware;
on-device transcription (verify SpeechAnalyzer) + FM feedback summaries of recordings.

## Risks & open items

- **TURN provider** — unavoidable owner decision before P3 ships. (Already on the
  pending list with prod hosting + consent copy.)
- **App Review**: recording requires visible consent — existing consent gate covers
  it; keep it prominent in-app. Session recording of minors n/a (university users).
- **Proximity pairing API** unverified — QR is the committed path; bring-close is upside.
- **Single-worker signaling** — fine at current scale; revisit before any launch push.
- **Apple dev account** ($99/yr) needed at P1 for push entitlements; APNs .p8 key is
  a secret → gitignored config, never committed (repo security rules apply).
- Assumed: iPhone-first (iPad later), English-only, existing brand tokens translate.

## References

- iOS capability doc: `~/Documents/Projects/AppleDev/ios-features.md` (evidence-graded)
- Web-app spec: `docs/caseroom-spec.md` · Deviations: `INTEGRATION.md` · State: `PROGRESS.md`
- Implementation plan: `docs/superpowers/plans/2026-07-12-caseroom-ios-app-plan.md`
