# myCase Front-End Execution — Multi-Agent Instructions (phone + tablet)

Date: 2026-07-17 · Orchestrator: main session · Status: STAGED (dispatch begins
when the backend gap waves have merged into `feature/backend-gap` and its
integration suite is green)
Design authority (canon, in priority order):
1. `docs/design/myCase - Design Decisions.md` — every token, recipe, rule,
   and screen decision; its §0 deltas OVERRIDE the UX spec.
2. `docs/design/myCase Mobile.dc.html` (iPhone canvas; truncated tail — see
   `docs/design/README-design-import.md`) and
   `docs/design/myCase Tablet.dc.html` (complete) — pixel truth. Canvas
   support files: `docs/design/ios-frame.jsx`, `docs/design/support.js`.
3. `docs/superpowers/specs/2026-07-16-mycase-ux-tree-design.md` — IA + flows
   where the decisions doc is silent.
Backend contracts: each `docs/superpowers/sdd/bgap-*-report.md` (Interfaces
section) + `docs/superpowers/plans/2026-07-17-backend-gap-execution.md` §6
pinned signatures. **Reports win over briefs where they differ.**

Target surfaces:
- **iOS app (`ios/`, SwiftUI, XcodeGen)** — iPhone AND iPad from one code
  base. This is 90% of the work.
- **Guest interviewer web console-lite** (F10) — server-rendered pages in
  `webapp/`, per Mobile canvas §8a. The broader web redesign is explicitly
  NOT designed yet (Decisions §6) and is out of scope.

## 1. Execution topology

Same orchestration model as the backend run: one **phase-lead agent per
phase** in an isolated git worktree (`/Users/thomaskgould/dev/fe-<phase>`,
branch `fe/<phase>-<slug>`, cut by the orchestrator from the then-current
`feature/backend-gap` tip), running the subagent-driven loop (plan → plan
review → per-task implementer + reviewer → final whole-branch review →
report). The orchestrator merges finished phases back in wave order.

| Wave | Phases | Depends on | Notes |
|---|---|---|---|
| FW1 | F0 design foundation | backend merged | solo — everything consumes it |
| FW2 | F1 shell & navigation | F0 | solo — owns the tab/router seams |
| FW3 | F2 Home+Timeline · F4 Library | F1 | 2-way parallel |
| FW4 | F7 Drills · F8 Community | F1 (F7 payloads from B8; if B8 slips, F7 builds against the B8 brief shapes with fixtures) | 2-way parallel |
| FW5 | F3 Case tab · F5 Session takeover+recap | F1 (F3 links F5's recap route — contract pinned §6) | 2-way parallel |
| FW6 | F6 Interviewer consoles (phone+tablet hero) | F5 (shares session plumbing) | solo (largest) |
| FW7 | F9 Onboarding retrofit · F10 Guest web | F0 (F9); B2 merged (F10) | 2-way parallel |

**Hard cap: 2 phases in parallel** — every phase builds and runs iOS
simulators on a 16 GB M2 Pro; more than two concurrent xcodebuild+sim
stacks thrashes the machine.

## 2. Non-negotiable rules (every agent, every dispatch)

Everything in the backend execution doc §2 applies verbatim (models: leads
and reviewers `opus`; **implementers default `sonnet`** — the canvases make
most screen work well-specified transcription — escalate a task's
implementer to `opus` only where the phase brief marks it JUDGMENT; scout
for lookups; NEVER Fable. Git rules, watchdog rules, 2-attempt rule, no
placeholders, report statuses: all identical).

Front-end additions:

**Design fidelity.**
- The Decisions doc §5 checklist is the review rubric. Reviewers reject:
  icon sets/emoji (staircase mark only), rounded content corners (square
  content, capsule glass), outlined secondary buttons (underline text
  instead), >1 glass hero per screen, >3 greens per screen, non-tabular
  timer/score numerals, population counts anywhere.
- Copy is design-owned: reuse the exact strings from the canvases
  (kickers, button labels, serif asides). Do not paraphrase. The persona
  data (Amara etc., Decisions §3) is for SwiftUI Previews and UI-test
  fixtures ONLY — live screens bind to the API.
- Colors/typography come from F0's token layer only — no hex literals in
  screen code (reviewers grep for `#` and `Color(red:` outside the token
  files).

**Evidence.** A screen task is DONE when: unit/VM tests green + the app
builds + a simulator screenshot of the screen (`xcrun simctl io booted
screenshot`) is saved under `.superpowers/sdd/shots/<task>.png` and the
implementer's report affirms it matches the canvas anchor (list any
deliberate deviations). Phone shots on the iPhone 17 sim; tablet shots on
an iPad Pro 11" sim, landscape.

**iOS project mechanics (P1–P4 lessons — violations have shipped bugs).**
- `Info.plist` keys go in `info.properties` files via project.yml — NEVER
  `INFOPLIST_KEY_*` build settings (silently dropped; P1 critical).
- After any project.yml change: regenerate (`xcodegen generate` in `ios/`)
  and commit both. Never hand-edit the .xcodeproj.
- Existing deep links (`caseroom://` scheme), widgets, App Intents, APNs
  registration, and the App Group `group.study.mycase` must keep working —
  F1 owns remapping their routes to the new tab structure; later phases
  may not touch them without a brief line saying so.
- Keep the whole existing iOS test suite green (record the baseline count
  at bootstrap; it is ~273+); add VM tests for every new screen.
- Build/test command shape: `timeout 1200 xcodebuild -project ios/*.xcodeproj
  -scheme <scheme> -destination 'platform=iOS Simulator,name=iPhone 17' test`
  (adjust to the repo's actual scheme; e2e scripts stay untouched).

**API discipline.** Screens consume the existing `APIClient` + Codable
model pattern (`ios/CaseRoom/...` — follow P1–P4 file layout). New
endpoints from the backend phases get Codable models matching the shapes
in the bgap reports exactly; decode failures in dev assert loudly. No
screen fetches raw JSON ad hoc.

**Web (F10 only).** Vanilla server-rendered templates + the existing CSS
approach (token ramps in base.html). No frameworks, no build steps.

## 3. Environment bootstrap (every phase lead, first task)

1. `cd /Users/thomaskgould/dev/fe-<phase>`; interpreter for any backend
   bits = the main checkout's venv (backend doc §3). iOS work: Xcode 26 CLI
   already on the machine.
2. Backend DB for the dev server: create `caserepo_fe_<phase>` exactly per
   backend doc §3 (schema + ALL migrations incl. the merged 020+ set), own
   worktree `.env`. Run the backend server when driving real screens:
   `nohup .venv-path main.py serve --host 0.0.0.0 --port 81<NN> &` (unique
   port per phase; kill it before finishing).
3. Baselines: backend suite green (record count) AND
   `xcodebuild ... test` green (record count) AND `xcodegen generate`
   idempotent. Red baseline → BLOCKED with output, immediately.
4. Read, in order: this doc §2 + your §5 brief; the Decisions doc IN FULL;
   your screens' canvas sections (anchors in the brief); the bgap reports
   your brief names.

## 4. Phase-lead workflow

Identical to backend doc §4 (plan → plan-review → task loop with fresh
implementer per task + task reviewer + fix loops → full suites → final
whole-branch review → committed report `docs/superpowers/sdd/fe-<phase>-report.md`
→ ≤15-line summary). **Dispatch every subagent with `run_in_background:
false` (synchronous)** — a lead that ends its turn waiting on a background
child is stranded (nothing re-invokes it); F1 hit exactly this. Your loop
is sequential anyway. Two further changes:
- Implementer model defaults to `sonnet`; tasks marked JUDGMENT in the
  brief dispatch `opus` implementers.
- Every screen task's reviewer receives the screenshot path(s) and the
  canvas anchor id, and must compare against the canvas before approving.

## 5. Phase briefs

### F0 — Design foundation (`fe/f0-foundation`) — ALL JUDGMENT (Opus) — M
The token + component layer everything else imports. New group
`ios/CaseRoom/DesignSystem/`:
- `Tokens.swift`: light palette (#EFF2F6 page, #0D1C31 ink, #515A66 muted —
  owner-locked, #A9B4C4 faint, #C9D2DF/#DDE3EB hairlines, #FFFFFF surface),
  dark takeover palette (#081222/#101E36/#E9EEF5/#7C8CA8/#3D5075/#24365A/
  green #2FC07E), accent green #1B9A5F (single theme constant — the host
  `accent` tweak analog), cobalt #2E56C0 links. Type scale per Decisions §1
  (tab H1 28/800/-0.03em … kickers 9.5–10/600/.15em caps), tabular numerals
  helper.
- Fonts: bundle Archivo (400–800) + Source Serif 4 (400/600 + italics) TTFs
  (Google Fonts, OFL — commit the license files), registered via
  info.properties (NOT INFOPLIST_KEY). Font helpers `.archivo(_:weight:)`,
  `.serifVoice(_:)`.
- Glass: `GlassPanel` / `GlassChip` / `GlassSheet` modifiers reproducing
  the §1 recipes (gradient fill + blur + white hairline border + the two
  inset highlights; dark-glass variant; scrim + `rise` transition
  0.32s cubic-bezier(0.22,1,0.36,1)). Honor
  `accessibilityReduceTransparency` → solid-white fallback (the
  `body.solid` analog). JUDGMENT: native iOS 26 glass/material APIs vs
  hand-built — decide per-component by fidelity against canvas
  screenshots; document the choice.
- `StaircaseMark` Shape (path M4 35 H15 V25 H26 V15 H37 V4 H45, viewBox
  48×40, ink→green gradient, trim-based draw animation, length 74) +
  `SteppedTimeline` view (literal stepped line, non-scaling 2px stroke,
  TODAY dot, 3-col firm labels).
- Chrome: top pills (wordmark chip + avatar pill / ‹ Back + context label),
  floating 5-slot glass tab bar w/ raised center CASE circle (active
  states per §1), toast capsule, header scroll fade, background tint
  blobs + giant faint staircase.
- Motion constants: rise 420ms + 120–150ms stagger, 160ms hover-lift,
  press scale .96, blinkdot. Nothing bounces.
- Deliver a `DesignSystemGallery` debug screen (all components, light+dark)
  — the phase's screenshot evidence, and later phases' visual reference.
Produces: every token/component name above (later briefs use them as-is).

### F1 — Shell & navigation (`fe/f1-shell`) — JUDGMENT-heavy — M
Replace the 4-tab structure with: HOME · LIBRARY · ⬤CASE · COMMUNITY ·
DRILLS + avatar sheet (no You tab). Route registry mapping every deep link
(`caseroom://…`, widget taps, push taps, App Intents) onto the new tree —
audit `ios/` for all entry points (P1/P4 built them) and keep each working
(JUDGMENT). Avatar sheet per canvas 7a: profile header + Edit, Linked
accounts, School VERIFIED, notifications toggle, Sign out, buried
"Administer a group" (→ F8's create-group route; stub target until FW4
lands — the route enum ships now). iPad: same tabs, 560pt centered bar,
top row wordmark|H1|avatar. Session takeover presentation seam:
`fullScreenCover` route F5/F6 will fill (pinned:
`AppRoute.sessionTakeover(sessionID:)`).
Consumes: B5 profile/settings endpoints. Existing tab content temporarily
re-homed (Cases→Library, Today→Home, Sessions→Case, You→avatar) so the
app stays shippable mid-transition.

### F2 — Home + Timeline detail (`fe/f2-home`) — mostly Sonnet — M
Canvas 3a (CANON) + 7b; tablet 2a. Home: date kicker + greeting, gauntlet
glass hero (streak squares, cohort footer), dark tonight strip (blink dot),
flat DIAGNOSTIC block (bars + FOCUS tag + "Next case for the gap" + Swap),
stepped TIMELINE block → timeline detail: headline, big stepped line,
readiness rows, add-a-firm chips, passed-deadline prompt flow (Offer /
No offer→reweight card / Waiting / No — copy verbatim from canvas).
Consumes: `/api/v1/dashboard` (B4+B7 diagnostic + recs + timeline summary),
`/api/v1/timeline*` (B7), `/api/v1/recommendations?exclude=` (B4, Swap),
drills daily/gauntlet (B8 shapes, fixtures if unmerged). Tablet: two-column
per canvas 2a incl. "LAST NIGHT — LOGGED" strip.

### F4 — Library (`fe/f4-library`) — mostly Sonnet — M
Canvas 5a; tablet 2c (master–detail 1fr/470px). Type chips + Everything/
Not done/Done toggles + "N OPEN · N DONE" live count; retired-done rules
per delta §0.4 (greyed below "DONE — YOURS TO INTERVIEW WITH" divider,
detail CTA flips to "Case someone with this", faint "Get re-cased anyway —
won't count toward diagnostics"). Case detail: rating+runs aggregate, your
history, case-pack PDF row. Consumes: `/api/v1/cases*` with B3's
`done_for_you`, aggregates, counts.

### F7 — Drills (`fe/f7-drills`) — run mechanics JUDGMENT, rest Sonnet — L
Canvas 5b; tablet 2b. Gauntlet hero (six types grid, DAY N, begin/re-run),
the timed run (real clock, progress bar, keypad + sign toggle — reuse P4
drill input), percentile result (mark draw + points + weak-section CTA),
16-bar 4-week trend, scoped boards C-14/WHARTON/GLOBAL/SCHOOLS with
percentile-not-headcount copy (delta §0.2 — never render an "of N").
Consumes: B8 gauntlet/boards/trends + existing P4 drill endpoints (drill
run must keep the FM on-device path working). JUDGMENT: run loop timing +
FM engine integration.

### F8 — Community (`fe/f8-community`) — mostly Sonnet — M
Canvas 6a; tablet 2d. School hero card (№2 THIS WEEK style, avg pctl,
campus city), YOUR GROUPS → group page (weekly points board w/ streak col,
TOP FIVE ADVANCE, admin-only member progress note, transfer leadership),
CONNECTIONS rows (FREE NOW state from availability; "swap invite pending"
decoration), group create flow from the avatar sheet ("YOU'RE THE ADMIN").
NO forum (delta §0.1). Consumes: B6 connections/groups/leaderboards +
availability.

### F3 — Case tab (`fe/f3-case`) — sheets JUDGMENT, spine Sonnet — L
Canvas 3b (CANON); tablet 1b (tray hero + two-column spine). Slim verb bar
(phone) / tray with inline live-now board (tablet); recap-gate card →
F5's recap route; NEXT UP w/ Swap; UPCOMING (accepted rows animate in,
add-to-calendar affordance → existing EventKit); PENDING rows Accept /
New time / Decline + sent-awaiting rows; HISTORY. Three glass sheets:
Get cased now (QR square + 6-char code + live-now board w/ Ping + expiry
copy + copy-link), Case someone (Scan QR primary, open invites,
interviewer log, "never gated" note), Schedule composer (WHO chips / WHEN
quick-picks Now·1h·Tonight 8pm·Pick a time / CASE: Interviewer decides ⟂
Request:[rec]; serif rule line). Consumes: B1 (counter, claim links,
short-codes, quick-pick semantics), B4 recs, B2 guest-visible states,
availability, existing pairing/EventKit. Gate 409 (`blocked_by_recap`)
handling on every candidate entry → routes to recap.

### F5 — Session takeover + recap gate (`fe/f5-session`) — ALL JUDGMENT — L
Canvas 4a/4b + 6b; dark palette until debrief. Refit the existing session
screen into the takeover: lobby seats (READY/JOINED), negotiation stage
(their pick / counter-once / "THEY KEPT THEIR PICK"), LIVE (glass clock
pill, video panes when remote, CASE/EX pills w/ new-dot, exhibit toast on
reveal, exhibit table/bars rendering), debrief (avg, bars, feedback line,
required 1–5 rating = the recap close endpoint, Schedule-next prefilled,
Swap roles → invite sent, Close). Recap gate screens per 6b: report page
(rubric bars + serif paragraphs + PDF row) + floating close-out sheet
(scroll-to-end unlock at bottom−16, RATE THIS CASE 1–5 cells required,
thumbs, "Gate cleared."). Consumes: B3 (negotiation/swap/recap endpoints +
WS broadcasts), existing signaling/WebRTC/reveal stack — DO NOT touch the
transport layers (P2/P3 code); this phase is presentation + the new B3
flows only.

### F6 — Interviewer consoles (`fe/f6-console`) — ALL JUDGMENT — L
Phone console per canvas 8b (6-stage chips, serif read-aloud, exhibit
Release/SENT·mm:ss/Recall, per-stage 1–10 strip + evidence note, bottom
bar Previous/Display PDF/Next→Finalize, tap-to-start clock). **Tablet hero
per canvas §7-1a**: top bar (case | CANDIDATE | master clock chip w/ N LEFT
+ under-5-min green | Finalize & send), 45-min cap progress bar, grid
1fr/380px — stage script + exhibits + SCORE THIS STAGE block | right rail
(candidate feed w/ LIVE chip + self-view, SEGMENT TIMER w/ laps, RUBRIC —
LIVE 12-dim mini-cells sharing the score handler, running avg). PDF mode
overlaying left pane only (rail stays live), authored pager. Consumes:
existing rubric/reveals/finalize + B3 negotiation + B4
counterpart-recommendations (interviewer pick sources). Rubric autosave
pattern exists (P2) — reuse.

### F9 — Onboarding retrofit (`fe/f9-onboarding`) — JUDGMENT for style retrofit — M
Canvas 1d flow retrofitted to turn-3 language (Decisions: bg #EFF2F6,
#515A66 muted, calmer greens — the canvas section is stale AND its markup
is in the truncated tail: implement from the Decisions §2-1d prose + F0
tokens + the 8a/3-series look; flag uncertainty in the report rather than
inventing new patterns). Flow: welcome (mark draws) → school-email gate →
passcode keypad (auto-advance at 6) → account completion incl.
Google/LinkedIn (B5's flow — OAuth via ASWebAuthenticationSession) →
group join (skippable) → "You're in." STEP N OF 05 progress = mark
drawing. Consumes: B5 signup/OTP/OAuth endpoints.

### F10 — Guest web console-lite (`fe/f10-guestweb`) — mostly Sonnet — S
Canvas 8a as server-rendered pages in `webapp/`: link-gate (guest or
log in, zero chrome), console-lite (clock, read-aloud, one release,
finalize), post-session "keep it on a record?" → account upgrade (B2).
Reuse the existing session-page JS where possible; style with the token
values (this is the ONE designed web surface; the rest of web is out of
scope per Decisions §6). Consumes: B2 guest claim/upgrade + existing
console endpoints. CSRF + `require_session_participant` enforced.

## 6. Cross-phase pinned contracts

- `AppRoute` enum (F1): `.home, .library, .caseTab, .community, .drills,
  .avatarSheet, .timelineDetail, .caseDetail(id), .recap(sessionID),
  .sessionTakeover(sessionID), .groupPage(id), .drillRun` — later phases
  add cases only via their brief.
- Recap route + gate handling (F5 ↔ F3): F3 navigates
  `.recap(sessionID)` on any `blocked_by_recap` 409.
- Score-cell component (F0) is shared by F5 debrief, F6 rubric cells,
  recap 1–5 (F5) — one component, three sizes (24/16pt cells).
- Persona fixtures live in ONE file (`PreviewFixtures.swift`, F0) — the
  Decisions §3 data verbatim; phone previews July-16 state, tablet
  previews July-17 state (Decisions §7 day-advance).

## 7. Merge protocol & kickoff (orchestrator)

Backend integration green → cut `fe/f0-foundation` → dispatch FW1 → merge
→ FW2 → … exactly as backend doc §7 (fresh integration DB + both suites +
an end-to-end sim smoke: login → Home → Case → sheet → Library). Thomas
demo checkpoints after FW2 (shell), FW5 (session flows), FW7 (full app) —
listed in ORCHESTRATION.md; on-device run needs his signing (ship tool).

## 8. Open items for Thomas (non-blocking to start)

1. Google + LinkedIn OAuth app credentials (B5 report will list exact
   fields) — needed before F9 can be verified end-to-end with live OAuth
   (mocked flows verify everything else).
2. The Mobile canvas's truncated 1-series tail: if you want the 1d
   onboarding markup preserved verbatim, export the full file from the
   design project into `docs/design/`; otherwise F9 proceeds from the
   Decisions-doc prose (stated above).
3. Demo checkpoints per §7 — say the word and the current wave's build
   ships to your 15 Pro.
