# myCase — UX Tree & Navigation Design

Date: 2026-07-16 · Status: draft for owner review
Source brief: `mycase/layout-site.txt` (owner brain-dump, 2026-07-16) + owner decisions in session.
Visual reference: `mycase/myCase Style Guide.html`, `mycase/myCase Interviewer Console.html`
(working design profiles — owner notes they need adjustment; visual polish is out of scope here).

## 1. Purpose

Define the full navigation tree, the Case section in detail (scheduling model,
recommendation surfaces, feedback recap gate, role swap), and per-platform
mapping for web, phone, and tablet. This is the UX spec; implementation
planning follows separately.

## 2. Structural principles

1. **The candidate owns the navigation.** All tabs are candidate-first.
2. **The interviewer is a flow, not a destination.** Interviewers arrive via
   QR/link (guest allowed), land directly in the console, and leave. No tab
   depends on being an interviewer.
3. **Live sessions are full-screen takeovers** (like a phone call), entered
   from the Case tab or a QR/link — never from nav. Both roles.
4. **One scheduling primitive** (§5). Every way to start a session is a way
   to create or answer a proposal.
5. **Recommendations are the spine, not a widget** (§7). Every session ends
   by seeding the next.

## 3. Global chrome

```
┌────────────────────────────────────────────── ⊙ avatar ┐   avatar: top-right, every screen
│                       (content)                        │
├────────────────────────────────────────────────────────┤
│   Home     Library    ⬤ CASE     Community    Drills   │   Case: center, raised
└────────────────────────────────────────────────────────┘
```

- **Phone/tablet:** 5-slot tab bar, Case raised in the center, Drills at the
  end (owner call: habit loop gets edge visibility). Profile/account lives
  behind the avatar, outside main nav.
- **Web:** same five buckets as a left sidebar (collapsible), avatar top-right.
- **Tablet:** identical tabs; the interviewer console is the tablet hero
  surface (landscape split view, §8).

## 4. Navigation tree

```
myCase
├── HOME  (login lands here)
│   ├── Diagnostic snapshot — strengths/weaknesses, cases done (2 mo), trend
│   ├── "Focus on ___" + recommended next case/drill  → deep-links to Case / Drills
│   ├── Timeline strip — firm deadlines (Bain/BCG/McK + chosen firms), readiness signal
│   │   └── Timeline detail: add firms · post-deadline prompts
│   │        (interviewed? → result? → connect with admittees → Community forum)
│   ├── Streak + today's-drill card → Drills
│   └── Upcoming sessions digest → Case › Upcoming
│
├── LIBRARY  (browse)
│   ├── Case tiles + filters (type, difficulty, industry, done/not)
│   └── Case detail: PDF · your history with it · rating · "Get cased on this" → Case flow
│
├── ⬤ CASE  — detailed in §5–6
│
├── COMMUNITY
│   ├── My groups + school (joined via school-email verification)
│   │   ├── Group page: members · group leaderboard
│   │   │   └── [GROUP ADMIN, role-gated] member progress — cases done, feedback,
│   │   │       drill performance/frequency · transfer leadership
│   │   └── School page: school leaderboard
│   │        └── [SCHOOL LEADER, role-gated] per-group performance · group leaders · global view
│   ├── Connections (friend profiles — feeds "ping a friend" in Case)
│   └── Admitted forum: firm/office threads, LinkedIn/email connect (no chat)
│
├── DRILLS  (end slot)
│   ├── Today's gauntlet — 6 types, ≤5 min, same set for everyone daily
│   ├── Results: score · daily percentile · school/group rank · vs peers
│   │    └── "Practice ___" → weak-section drills
│   └── Trends over time · leaderboards (bridge to Community)
│
└── ⊙ AVATAR  (top-right, outside main nav)
    ├── Account: photo, bio, password, LinkedIn/Google links, school verification
    ├── Notifications / settings
    ├── "Administer a group" (deliberately buried here per brief) → create group → admin role
    └── Sign out
```

## 5. Case section

### 5.1 Landing layout — verbs on top, spine below

Fixed action header (always visible), then a scrollable spine:

```
⬤ CASE
├── ACTION HEADER (fixed)
│   ├── Get cased now
│   │   ├── In person → QR/broadcast pairing (proposal auto-accepted, when = now)
│   │   └── Remote    → ping a friend · live-now board · send a link
│   ├── Case someone  → scan QR · open invites · your queue
│   └── Schedule for later → proposal composer (§5.2)
│
└── SPINE (scrolls; top-to-bottom = next-to-past)
    ├── [if unread recap] "Finish your last recap" card → recap gate (§6.4)
    ├── Next up for you — top recommended case + why ("weak on market sizing")
    │    └── [Get cased on this] [Preview PDF] [Swap recommendation]
    ├── Upcoming — accepted sessions (calendar-integrated, §5.3)
    ├── Pending — proposals awaiting an answer: Accept · Suggest new time · Decline
    └── History — session log (case, interviewer, date, duration)
         └── Feedback detail · full case PDF · rating given
```

### 5.2 Scheduling model — the proposal primitive

**proposal = who + when + optional case.** Every start path is a proposal:

| Path | Under the hood |
|---|---|
| QR in-person pairing | proposal created **and** accepted in one act, when = now |
| Ping a friend / live-now board | proposal, when = now |
| Send a link (text/email) | open proposal, claimable by anyone incl. guest |
| Schedule for later | proposal, when = future → accept / counter |

Composer rules (simplicity is the feature):

- **Who:** friend picker · shareable link · (in person: QR replaces this).
- **When:** quick-picks, not a calendar widget — `Now · In 1 hour · Tonight 8pm
  · Pick a time…` (native picker only on the last).
- **Case:** defaults to "interviewer decides"; one tap switches to "request:
  [top recommendation]" or pick from Library.
- **Responding:** three buttons — `Accept · Suggest new time · Decline`.
  One counter round, not a thread. The app is the calendar, not the
  conversation; time-haggling happens over text. **No chat, ever.**
- **Expiry:** unaccepted "now" proposals expire after 2 h; unaccepted scheduled
  proposals expire at their proposed start. Accepted sessions never joined are
  marked missed 60 min after start (A3).

### 5.3 Calendar integration (owner requirement)

On **accept**, both parties get the session on their real calendar with zero
extra thought:

- **iOS:** EventKit insert prompt (built, P1) — one tap, then silent for
  subsequent accepts if permission granted.
- **Web:** `.ics` attached to the acceptance state + "Add to calendar" button
  on every Upcoming row (endpoint built, P8).
- **Reminders:** proposal/accepted push + starting-soon push at T-60 s (built).
- **Home-screen widget:** next-session widget with countdown (built, P4).
- **During session:** Live Activity / Dynamic Island timer (built, P3).

New work here is *affordance only* — surfacing "Add to calendar" and the
accept-time prompt; the machinery exists.

## 6. Session takeover (not in nav)

### 6.1 Flow

```
Pairing (QR / link / broadcast)
  → Case negotiation
      interviewer picks: own preference | recommended-for-candidate | from own done-set
      candidate's requested case shown · one counter-suggestion allowed each
  → LIVE
      Candidate: dark screen → exhibits appear as toggleable pages when released
      Interviewer console: prompt script · exhibit release toggles · feedback notes
        · timer · "Display PDF" fallback always one tap away
      Remote mode adds video panes both sides
  → Debrief
      Interviewer: finalize + send feedback
      Candidate: reads feedback + full PDF → rates case (clears recap, §6.4)
      [Swap roles] button (§6.3)
      "Next recommended: [case]" + [Schedule your next session] (pre-filled proposal)
  → Auto-logged to Case › History for both (interviewer too, unless guest)
```

### 6.2 Guest interviewer path

QR/link → guest-or-login gate → straight into the console, **no app chrome** →
post-session: "Create an account to keep this session on your record?" The
console must never depend on a tab existing.

### 6.3 Role swap (owner requirement)

On the debrief screen, **if the interviewer is authenticated** (never for
guests), both parties see `Swap roles & go again`. Tap → swap invite to the
other party → on accept, a new session is created with roles reversed, same
mode (in-person/remote), fresh case negotiation (the new interviewer picks).
The recap gate (§6.4) applies to the new candidate before going live —
normally already satisfied, since they just rated in debrief.

### 6.4 Feedback recap gate (owner requirement)

Every feedback report is read before the user takes on their next case:

- **Happy path:** the debrief rating (§6.1) is the recap — reading + rating
  there clears it. The gate is the backstop for people who bail early.
- **Gate rule:** a user with an unread delivered recap cannot start or accept
  a session **as candidate** (any Get-cased path, accepting a proposal,
  accepting a swap into the candidate seat). Never blocks interviewing,
  drills, or browsing.
- **Recap page:** the feedback report, scroll-to-end enforced (close-out
  control disabled until the bottom is reached), closed by answering
  **"Was this case helpful?" Yes / No** (required). If the interviewer was
  authenticated, an optional feedback-quality thumbs appears on the same
  screen (A2). This guarantees every case gets graded.
- **Multiple unread:** cleared oldest-first, one page at a time.
- **Not yet delivered:** if the interviewer never finalized, there is nothing
  to read — no gate.
- Recaps stay re-readable forever in Case › History.

## 7. Recommendation surfaces — one engine, three mouths

1. **Case landing spine** leads with "Next up for you" + the why; every start
   path pre-fills its case request with it (recommendation → session ≈ 2 taps).
   Home's recommendation card deep-links here.
2. **The recommendation travels with the candidate:** the profile an
   interviewer receives at pairing includes "Recommended for [name]" — the
   same list, interviewer-side.
3. **Debrief ends by seeding the next session:** feedback lands → engine
   updates → "Next recommended" + pre-filled schedule CTA. No session ends in
   a dead end.

## 8. Platform mapping

- **Phone:** tab bar per §3; session takeover portrait; candidate-first.
- **Tablet:** same tabs; interviewer console is the hero — landscape split:
  prompt script left, exhibit toggles + notes right, PDF fallback persistent.
- **Web:** sidebar nav; console fully functional in-browser for guest
  interviewers; QR pairing via camera, 6-character code as manual fallback.

## 9. Entry flows

1. **Onboarding:** LinkedIn / Google / email+passcode → import name/photo/bio
   → school-email verification (code) → join group (skippable) → Home.
2. **Guest interviewer:** §6.2.
3. **Post-drill:** results → "Practice ___" → weak-section drills.
4. **Timeline advance:** deadline passes → "did you interview?" → result →
   "connect with admittees" → Community forum.

## 10. Built vs. new

**Exists (backend + much UI):** full session flow (QR pairing, negotiation,
reveals, console, feedback, WebRTC remote), proposals + accept + .ics,
starting-soon push, EventKit add, widgets, Live Activity, drills + streaks,
free-now availability, dashboard, case browse/library.

**New surfaces this spec adds:** groups/schools + role-gated admin views,
timeline/firm deadlines, admitted forum, percentile/leaderboard aggregation,
live-now board UI, recap gate, role swap, proposal quick-pick composer,
recommendation engine surfacing (engine itself: dashboard recs exist; the
three-mouth plumbing is new).

## 11. Out of scope (deliberate)

- No chat, anywhere (owner brief).
- No availability calendars / future-slot booking with strangers — the only
  stranger surface is live-now.
- No separate interviewer app or interviewer tabs.
- Visual design adjustments to the working design profiles (tracked
  separately; profiles need owner-directed changes).

## 12. Assumptions

- **A1:** Community earns its tab at launch; if launch needs to be leaner it
  can start avatar-nested without moving anything else.
- **A2:** Recap close-out requires the case rating; interviewer
  feedback-quality thumbs is optional, shown only for authenticated
  interviewers.
- **A3:** Expiry windows in §5.2 (2 h now-pings, start-time for scheduled,
  missed at +60 min) are defaults, tunable server-side.
- **A4:** "Tonight" quick-pick = 20:00 local.
- **A5:** Role swap keeps the same mode (in-person/remote) as the session it
  follows.
