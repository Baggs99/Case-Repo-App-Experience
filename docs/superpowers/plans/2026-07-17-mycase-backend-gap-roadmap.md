# myCase Backend Gap Roadmap

Date: 2026-07-17 · Status: gap analysis + phase outline (not an implementation plan)
Spec: `docs/superpowers/specs/2026-07-16-mycase-ux-tree-design.md` (draft, awaiting owner review)
Baseline audited: branch `feature/ios-p4` @ 966b175 (4-scout backend inventory, 2026-07-17)

Per-phase TDD implementation plans (superpowers:writing-plans) are authored at
execution time, one per phase, after owner sign-off on the spec. UX/UI is
tracked separately and out of scope here. The drills question bank is a
separate WIP track (`feature/drills`, ~/Desktop docs) integrating later behind
the `/api/v1/drills` seam — B8 below covers only the aggregation around it.

**Migration numbering: 019 is RESERVED for the drills bank. This roadmap's
migrations start at 020.**

## What the backend already has (verified)

- Full session flow: QR pairing (`pairing_tokens`, 10-min TTL), consent,
  state machine, exhibit reveals + AES keys over WS, rubric → finalize →
  feedback, recordings (chunked upload), remote WebRTC (mode col, TURN
  minting), session `.ics`.
- Proposals: create (from/to user, case, role, ≤3 times), inbox,
  accept/decline; lazy sweeps (7-day proposal expiry, 6-h stale-session abort)
  in `webapp/repositories/proposals.py:66` / `practice_sessions.py:266`.
- Recommendation engine: 3 SQL rules (coverage-gap, difficulty-ladder,
  weak-dimension) in `webapp/repositories/dashboard.py:228` — web-only
  (`/api/dashboard`, room pages); NOT exposed in `/api/v1`.
- Dashboard: dimension averages (last 10), streaks, next session
  (`api_v1.py:353`).
- Drills: per-user deterministic daily drill (3 types), attempts, streaks
  (`webapp/drills.py`, migration 017).
- Free-now availability: set/clear/list free users + instant-match push
  (migration 018, `api_v1.py:193`).
- Push: APNs device tokens, proposal/accept/knock/feedback/starting-soon/
  free-now events; Live Activity.
- Auth: email+password, email verification + password reset via Resend,
  domain whitelist (@yale.edu, @umich.edu + 1 guest), `display_name` only.
- Case library: browse/search/detail, PDF/exhibits, useful/not-useful votes
  (library-level, migration 007).

## Gaps vs spec (by section)

| Spec § | Gap | Current state |
|---|---|---|
| 5.2 | "Interviewer decides" case | `proposals.case_id NOT NULL` (011_caseroom.sql:204) |
| 5.2 | One-counter "Suggest new time" | accept/decline only |
| 5.2/A3 | Expiry: 2 h now / at-start scheduled / missed +60 min | 7-day expiry, 6-h abort, no `missed` state, page-load-lazy sweeps (iOS-only usage never triggers them) |
| 5.2 | Send-a-link open proposals | `to_user_id NOT NULL`; no claim tokens |
| 5.1 | Ping a friend | no friends/connections concept anywhere |
| 5.1 | Live-now board | GET availability lists free users — needs enrichment only (mostly done) |
| 8 | 6-char manual pairing code | 32-char urlsafe tokens only |
| 6.1 | Case negotiation (pick sources, 1 counter each) | proposer/QR-minter pre-picks the case; `pairing_tokens.case_id` bound at mint |
| 6.2 | Guest interviewer (link/QR, no account; post-session claim) | hard email whitelist, `require_auth_api` everywhere |
| 6.3 | Role swap | nothing (no "swap" in codebase) |
| 6.4 | Recap gate | feedback table has NO read/viewed tracking (011:145); no gate logic; no required case-helpful rating at close-out; no feedback-quality thumbs |
| 7 | Rec surfacing: api_v1 + why-text + swap-rec; interviewer-side "recommended for [name]"; debrief seeding | engine exists, zero of the three mouths plumbed to `/api/v1` or sessions |
| 4 Home | Timeline/firm deadlines + post-deadline prompts + readiness | nothing (only `cases.firm`) |
| 4 Home | Diagnostic snapshot in api_v1 (strengths/weaknesses, 2-mo trend) | api_v1 dashboard lacks dimension data + recs |
| 4 Community | Groups/memberships/roles, transfer leadership, member-progress views | nothing |
| 4 Community | Schools, school verification, school leaderboards, school-leader role | domain whitelist only, hardcoded CHECK |
| 4 Community | Admitted forum (threads/posts, firm/office) | nothing |
| 4 Drills | Same-set-for-all daily gauntlet, 6 types | per-user seed, 3 types (`drills.py:115`) |
| 4 Drills | Score/percentile/school+group rank/trends | `drill_attempts` has boolean `correct` only; zero ranking infra |
| 9 | OAuth (Google/LinkedIn), email+passcode OTP | email+password only |
| Avatar | Profile (photo, bio, links), edit endpoints, avatar upload | `display_name` only |
| Avatar | Notification settings | none (push fires unconditionally) |

## Phases

Order = dependency order; B4 is deliberately early (small, unblocks B3/B7).

### B1 — Scheduling core: the proposal primitive (§5.2) — M
- Migration 020: `case_id` nullable ("interviewer decides"), `to_user_id`
  nullable + claim token for send-a-link open proposals, counter fields
  (`countered_times_json`, `countered_at`, one round enforced), `missed`
  session state.
- `POST /api/proposals/{id}/counter` + accept-of-counter; push events.
- Spec expiry: now-proposals +2 h, scheduled at proposed start, accepted
  never-joined → `missed` at +60 min (env-tunable, A3). Move all sweeps into
  the existing 60-s starting-soon loop (kill page-load-lazy dependence).
- Pairing: 6-char short-code fallback; `pairing_tokens.case_id` nullable
  (case chosen in negotiation, B3).
- Done when: full proposal lifecycle (open link → claim → counter → accept →
  session; now-ping expiry; missed marking) passes API tests driven purely
  through `/api/v1` with no web page loads.

### B2 — Guest interviewer (§6.2) — M
- Guest identity: flagged `users` row (`is_guest`, null email/password) —
  keeps every FK working. Session-scoped cookie minted on open-link/QR claim;
  guest can drive console endpoints for that session only.
- Post-session upgrade: create account → guest rows re-attached.
- Guests never see swap, never accrue history until upgrade.
- Done when: an unauthenticated browser claims a link, runs a full session
  through finalize, then upgrades and owns the history row.

### B3 — Session-flow additions (§6) — L
- Case negotiation: pre-lobby `negotiating` state; interviewer pick sources
  (own preference / recommended-for-candidate via B4 / own done-set),
  candidate's requested case shown, one counter-suggestion each; over the
  existing signaling WS + REST for pre-join.
- Role swap: `POST /api/practice/{id}/swap` (authed interviewers only, from
  debrief/finalized) → swap invite → accept creates reversed session, same
  mode (A5); recap gate checked on the new candidate.
- Recap gate: migration — feedback `viewed_at`, `closed_at`; close-out
  requires "Was this case helpful?" (reuse `case_votes`, now required) +
  optional feedback-quality thumbs (new column) when interviewer authed (A2).
  Gate check on every candidate-seat entry (create practice, accept proposal,
  pair claim, swap accept), oldest-first, no gate if never finalized.
- Debrief seeding: finalize response + push carry next-recommendation +
  prefilled-proposal payload (§7 mouth 3).
- Done when: gate blocks a candidate with an unread recap on all four entry
  points and clears via close-out; swap round-trip creates a reversed session.

### B4 — Recommendation surfacing (§7) — S (do before/with B3)
- `GET /api/v1/recommendations`: list + human-readable "why" per rule +
  exclude-param for "Swap recommendation".
- Counterpart recs in join-config / pair status (interviewer-side
  "Recommended for [name]").
- Add recs + dimension averages to `/api/v1/dashboard` (Home card).
- Done when: all three mouths return the same engine output over api_v1.

### B5 — Identity, profile, onboarding (§9, avatar) — L
- Profile: photo (R2 upload), bio, LinkedIn/Google link fields;
  GET/PUT `/api/v1/profile`.
- Auth: Google OAuth + email+passcode OTP (Resend infra exists); keep
  password path. LinkedIn OAuth = owner decision (app review overhead).
- Migration: replace hardcoded email CHECK with a `schools` registry
  (domain → school); school-email verification code binds user → school.
- `notification_settings` table + endpoint; push fan-outs consult it.
- Done when: fresh signup via Google or passcode lands verified with a
  school binding and an editable profile.

### B6 — Community (§4) — L
- Connections: mutual request/accept; feeds composer "ping a friend"
  (until then B1's who-picker is any-known-user).
- Groups: `groups`, `group_members` (admin/member), create ("administer a
  group" via avatar), join, transfer leadership; role-gated member-progress
  endpoints (cases done, feedback, drill perf/frequency).
- Schools: leaderboard; school-leader role with per-group views.
- Leaderboard queries (sessions now; drill scores land in B8).
- Admitted forum: threads (firm/office) + posts, connect via profile
  links (B5); `admitted` status sourced from B7 results. No chat, ever.
- Done when: two seeded users form a group, admin sees member progress,
  leaderboards rank, a forum thread posts.

### B7 — Home: timeline & diagnostic (§4) — M
- `firms` reference table (seed Bain/BCG/McK + curated list), `user_firms`,
  deadline data; post-deadline prompt state machine (interviewed? → result? →
  connect) feeding `admitted` for B6.
- Extend `/api/v1/dashboard`: 2-month diagnostic window (strengths/
  weaknesses, cases done, trend), timeline strip payload, readiness signal
  (definition = owner decision; default: dimension-average threshold).
- Done when: Home renders entirely from one api_v1 payload against seeded
  deadlines.

### B8 — Drills aggregation & gauntlet (§4) — M, partially blocked on bank
- Global daily gauntlet: date-only seed (same set for everyone), 6 types
  ≤5 min — needs the question bank; keep behind `/api/v1/drills` seam and
  hold until the DRILLS TRACK lands (recommended) rather than extending the
  3-type generator twice.
- Migration: scored attempts (score, duration, gauntlet set id) — coordinate
  with the bank's migration 019.
- Percentile-of-day, school/group rank, vs-peers, trends endpoints
  (group/school scoping from B6); leaderboards bridge to Community.
- Done when: two users complete the same daily set and get score, daily
  percentile, and group rank from api_v1.

## Cross-cutting

- All sweeps/schedulers consolidated in B1's loop — nothing may rely on web
  page loads once clients are app-only.
- House rules on every new route: parameterized SQL, server-side validation,
  CSRF (web) / same-origin (native pattern already in repo), auth guards.
- Backend suite is 360 green at baseline; each phase extends it.
- Push additions per phase: counter received (B1), swap invite (B3),
  group/forum activity (B6 — respect B5 settings).

## Open owner decisions (defaults if unanswered)

1. LinkedIn OAuth at launch → default NO (Google + passcode first; LinkedIn
   needs app review).
2. School registry launch list → default curated (Yale, UMich, Booth + add
   flow), not any-.edu.
3. Readiness-signal definition (§4 timeline) → default dimension-average
   threshold vs target-firm deadline proximity.
4. Gauntlet before/after bank → default AFTER (bank is WIP; avoid building
   the 6-type generator twice).
5. Guest identity model → default flagged users row (FK simplicity).
6. A1 (Community tab at launch) — backend identical either way; B6 builds
   regardless.
