# Backend Gap Execution — Multi-Agent Instructions

Date: 2026-07-17 · Orchestrator: main session · Status: ACTIVE
Roadmap (scope authority): `docs/superpowers/plans/2026-07-17-mycase-backend-gap-roadmap.md`
UX spec (product authority): `docs/superpowers/specs/2026-07-16-mycase-ux-tree-design.md`
Integration branch: `feature/backend-gap` (off `feature/ios-p4` @ 966b175)

This document is the standing brief for every agent working the backend gap.
Each phase (B1–B8) is executed by a **phase lead** agent in an isolated git
worktree. Phase leads run their phase end-to-end: write the implementation
plan, get it reviewed, execute it task-by-task with per-task review, run a
final whole-branch review, and file a report. The orchestrator merges
finished phases into `feature/backend-gap` in wave order and resolves
cross-phase conflicts. **No agent ever merges, pushes to origin, or touches
`main`.**

## 1. Execution topology

| Wave | Phases (parallel) | Depends on |
|---|---|---|
| 1 | B1 scheduling core · B4 rec surfacing · B5 identity/profile | — |
| 2 | B2 guest interviewer · B7 timeline/home | B1 (B2); B4 merged (B7 rebases over dashboard changes) |
| 3 | B3 session-flow (negotiation/swap/recap gate) · B6 community | B1+B2+B4 (B3); B5+B7 (B6) |
| 4 | B8 drills aggregation | B6 + owner decision on gauntlet timing |

Worktrees: `/Users/thomaskgould/dev/bgap-<phase>` on branch `bgap/<phase>-<slug>`,
created by the orchestrator off the current tip of `feature/backend-gap` at
wave start (so wave-2+ phases see all previously merged work).

## 2. Non-negotiable rules (every agent, every dispatch)

**Models.** Every subagent dispatch pins a model explicitly. Implementers,
reviewers, and phase leads: `opus`. Pure read-only lookups may use `scout`
(Haiku). **Never dispatch Fable** (`deep` agent, `model: fable`, or any
omitted-model dispatch that would inherit it). If you hit a problem you'd
normally escalate, write the packaged question (goal / what was tried +
exact errors / file paths / the one question) into your report under
`ESCALATIONS` and continue or mark BLOCKED.

**Git.**
- Work only on your own `bgap/*` branch inside your own worktree.
- Never checkout/commit on `main`, `feature/ios-*`, `feature/caseroom`,
  `feature/drills`, or `feature/backend-gap`. Never push to origin. Never
  force-push or rewrite history. Never run `git worktree remove` or `prune`.
- Commit per completed task, imperative message ("Add proposal counter
  endpoint"), plus WIP commits before any long/risky step.
- Never commit `.env`, secrets, or DB dumps. `.gitignore` already covers
  them — check before your first commit anyway.

**Security (house rules, enforced at review).**
- Parameterized queries only — zero string-interpolated SQL.
- Server-side validation on all input; length/enum/type checks in the
  handler or repository, not just the client.
- State-changing web routes: CSRF check (follow existing pattern in
  `webapp/routes/proposals.py`); native/API routes: follow the existing
  `require_same_origin`/cookie pattern in `webapp/routes/api_v1.py`.
- Auth guard on every new endpoint; add an IDOR test for every endpoint
  that takes a foreign id (session_id, user_id, group_id…). P1 review
  caught a device-token IDOR — assume reviewers will hunt for these.
- Uploads (B5 photos): stored in R2 via the existing storage layer, never
  on local disk inside the web root; validate content-type + size cap.

**Dependencies.** Boring and dependency-free. Any new package needs a
one-line justification in the commit message that adds it to
`requirements.txt`, and must be free-tier friendly. Hand-roll OAuth flows
with `httpx` (already installed) rather than adding provider SDKs.

**Watchdog discipline.**
- Max 2 attempts per failing action (command, test, install). On the second
  failure: skip, record in report, continue if possible; else BLOCKED.
- No timeout-less calls: no browsers, no raw CDP, no interactive prompts,
  no `psql` without a statement, no servers in the foreground (use
  `nohup ... & disown` if you must run one, and kill it before finishing).
- Suite runs: always `timeout 900 .venv-path -m pytest tests/ -q` style
  bounds (see §3 for the exact interpreter path).

**Style.**
- Match repo style exactly; never reformat unrelated code.
- Every new module starts with the 4-line header docblock: Purpose /
  Inputs / Outputs / Run.
- Comments explain why, not what.
- New SQL migrations are idempotent (`IF NOT EXISTS`, `IF NOT FOUND`
  guards) like every existing migration in `db/migrations/`.

**No placeholders.** No TODO stubs, no "rest follows the same pattern."
If something must be deferred, it goes in the report under `DEFERRED` with
a reason.

## 3. Environment bootstrap (phase lead, first task, before any code)

1. `cd /Users/thomaskgould/dev/bgap-<phase>` (your worktree — already created).
2. Interpreter: use the main checkout's venv by absolute path —
   `/Users/thomaskgould/dev/Case-Repo-App-Experience/.venv/bin/python`
   with cwd = your worktree. Alias it in your head as `$PY`. Do not create
   a new venv. If your phase adds a package: `$PY -m pip install <pkg>`
   once, add to `requirements.txt` with justification.
3. **Own database — mandatory.** Tests hit the live DB named in `.env`
   (there is no conftest isolation). Do:
   ```
   createdb caserepo_bgap_<phase>
   psql -d caserepo_bgap_<phase> -v ON_ERROR_STOP=1 -f db/schema.sql
   for f in db/migrations/0*.sql; do psql -d caserepo_bgap_<phase> -v ON_ERROR_STOP=1 -f "$f"; done
   cp /Users/thomaskgould/dev/Case-Repo-App-Experience/.env .env   # worktree-local, gitignored
   # then edit .env: DATABASE_URL=postgresql://localhost/caserepo_bgap_<phase>
   ```
   Seed users a/b/c@yale.edu the way `INTEGRATION.md` §dev-setup describes
   if tests need them (check whether the suite self-seeds first).
4. Baseline: `timeout 900 $PY -m pytest tests/ -q` → expect ~360 passed
   (a handful of e2e_* files are excluded by default collection; do not
   chase them). Record the exact count in your ledger — that number +N is
   your finish line. If baseline is red, STOP → report BLOCKED with output.
5. Your new migrations run against your DB the same way
   (`psql -d caserepo_bgap_<phase> -f db/migrations/0XX_name.sql`) and must
   be re-runnable (idempotent).

## 4. Phase-lead workflow

You are the controller for your phase, not the typist. Work the
subagent-driven-development pattern with your own Opus subagents:

**Step 1 — Plan.** Write
`docs/superpowers/plans/2026-07-17-bgap-<phase>-plan.md` in your worktree
following the writing-plans discipline: header (goal / architecture / tech
stack / global constraints), then bite-sized tasks. Every task: exact file
paths, Interfaces (Consumes/Produces with exact signatures), TDD steps with
complete test code and complete implementation code, run commands with
expected output, commit step. No placeholders — later tasks repeat code
rather than saying "similar to Task N". Global constraints section copies
§2 of this document by reference plus your phase brief (§6) verbatim.
Commit the plan.

**Step 2 — Plan review.** Dispatch a fresh Opus reviewer: inputs are your
plan file, your phase brief (§6 below), and the two authority docs
(roadmap section for your phase + spec sections it cites). It must verify:
every brief requirement maps to a task; interfaces match the brief's
signatures exactly; no placeholder patterns; migration numbers match §5;
tests assert real behavior. Fix findings, commit, then execute. One review
round is required; loop until no Critical/Important findings.

**Step 3 — Execute task-by-task.** For each task, in order:
- Dispatch a fresh Opus **implementer** with: one line of scene-setting,
  the task's text extracted to a brief file, interfaces from earlier
  tasks, the §2 rules, the report-file path. Implementer follows TDD
  (test first, watch it fail, minimal code, green, self-review), runs the
  tests it names, commits, reports DONE / DONE_WITH_CONCERNS /
  NEEDS_CONTEXT / BLOCKED with evidence (command + output).
- Record the pre-dispatch commit as BASE. Generate a diff package
  (`git log --oneline BASE..HEAD`, `git diff --stat BASE..HEAD`,
  `git diff -U10 BASE..HEAD` → one file under `.superpowers/sdd/`).
- Dispatch a fresh Opus **task reviewer**: brief file + report file +
  diff package + the verbatim global-constraints block. Two verdicts
  required: spec compliance AND code quality. Critical/Important findings
  → dispatch a fix subagent (with the covering tests named), then
  re-review. Minors → ledger, triaged at final review.
- Append to your ledger file `.superpowers/sdd/progress.md`:
  `Task N: complete (commits <base7>..<head7>, review clean)`.
  After any interruption, trust the ledger + `git log`, never re-run
  completed tasks.
- Do not pause between tasks; do not ask the orchestrator "continue?".

**Step 4 — Full suite + final review.** Full suite green (baseline + your
new tests; report exact counts). Then dispatch a final Opus whole-branch
reviewer with a diff package spanning `merge-base(feature/backend-gap,
HEAD)..HEAD`, the Minor-findings list, your phase brief, and the spec
sections. It reviews for: spec compliance, security (§2 list), cross-task
consistency, test quality, migration idempotency. One fix subagent for the
complete findings list, re-review, until clean.

**Step 5 — Report.** Write
`docs/superpowers/sdd/bgap-<phase>-report.md` (committed):
status (DONE / DONE_WITH_CONCERNS / BLOCKED) · task list with commit ranges
· suite counts before/after · new endpoints table (method, path, auth) ·
new migrations · interfaces delivered (exact signatures, for later phases)
· DEFERRED · ESCALATIONS (packaged questions, if any) · anything the
orchestrator must know before merging. Final commit, then return a
≤15-line summary: status, branch, head SHA, suite counts, concerns.

## 5. Serialized resources (pre-assigned — do not improvise)

**Migration numbers** (019 is RESERVED for the drills-bank track):

| Phase | Numbers |
|---|---|
| B1 | 020, 021 |
| B5 | 022, 023, 024 |
| B2 | 025 |
| B7 | 026, 027 |
| B3 | 028, 029 |
| B6 | 030, 031, 032, 033 |
| B8 | 034, 035 |

Unused assigned numbers are simply skipped (a gap is fine; a collision is
not). Never renumber or edit another phase's migrations.

**Shared-file etiquette** (api_v1.py is touched by everyone):
- New endpoint clusters go in NEW router modules —
  `webapp/routes/recommendations.py`, `webapp/routes/profile.py`,
  `webapp/routes/groups.py`, etc. — registered with one include line in
  the app factory (follow how existing routers register).
- Edits to existing shared files (`api_v1.py`, `practice.py`,
  `proposals.py`, `push/…`) are allowed only where the brief names them,
  and should be additive (new functions/blocks) rather than rewrites, to
  keep orchestrator merges clean.
- Never edit `db/schema.sql` (migrations only), `INTEGRATION.md`, the
  roadmap, or this file.

## 6. Phase briefs

Before planning, read `docs/superpowers/sdd/bgap-<phase>-report.md` for
every phase your brief's Consumes line names — **reports override briefs**
where they differ (they record what was actually built, incl. deviations
like B1's DD-1). Keep your ledger and diff packages under
`.superpowers/sdd/<your-phase>/` (NOT the bare `.superpowers/sdd/` — same
path across phases = merge conflicts every wave).

Each brief supplements the roadmap section (read it first) and the spec
sections it cites. Where a brief pins a signature, later phases build
against it — deliver it exactly or record the deviation prominently in
your report's Interfaces section.

### B1 — Scheduling core (roadmap §B1; spec §5.2, A3, §8) — branch `bgap/b1-scheduling`
Anchors: `db/migrations/011_caseroom.sql:200` (proposals),
`webapp/repositories/proposals.py` (sweep at :66), `webapp/routes/proposals.py`,
`webapp/repositories/practice_sessions.py:266` (stale sweep),
`webapp/repositories/pairing_tokens.py`, `webapp/push/` (event senders),
the 60-s starting-soon loop (find it via `grep -rn starting_soon webapp/`).

Migration 020: `proposals.case_id` DROP NOT NULL (null = "interviewer
decides"); `to_user_id` DROP NOT NULL; `claim_token TEXT UNIQUE NULL`;
`counter_times_json JSONB NULL`, `counter_by INTEGER NULL REFERENCES users`,
`countered_at TIMESTAMPTZ NULL`; state CHECK gains `'countered'`.
Migration 021: `practice_sessions` state CHECK gains `'missed'`;
`pairing_tokens.case_id` DROP NOT NULL; `pairing_tokens.short_code TEXT
UNIQUE NULL`.

Deliver:
- `POST /api/proposals` accepts `case_id: null` and (`to_user_id: null` →
  response includes `claim_token`). Existing named-recipient flow unchanged.
- `POST /api/proposals/claim/{claim_token}` — any authed user (guests come
  in B2 — leave the auth dependency injectable), not the creator; claiming
  sets `to_user_id`, state stays `pending` for scheduled times or
  auto-accepts for `when=now` proposals (spec table §5.2).
- `POST /api/proposals/{id}/counter` body `{times: [iso8601, ≤3]}` — only
  the recipient, only from `pending`, exactly one round (from `countered`
  the only moves are original-proposer accept/decline). Accepting a counter
  = `POST /api/proposals/{id}/accept` with a `time` chosen from the counter
  times, creator-side. Push event `proposal_countered` to the proposer.
- Expiry per A3, env-tunable via `webapp/settings.py`
  (`PROPOSAL_NOW_EXPIRY_MIN=120`, `SESSION_MISSED_AFTER_MIN=60`):
  now-proposals (no `proposed_times`) expire 2 h after creation; scheduled
  proposals expire at their earliest proposed start; accepted sessions
  never past `lobby` by start+60 min → state `'missed'` (distinct from
  `aborted`; keep the 6-h abort as the outer backstop).
- Move ALL sweeps (proposals, missed, stale) into the existing 60-s
  background loop so app-only clients get correct lifecycle without page
  loads. Keep the lazy page-load sweeps as harmless no-ops or delete them —
  your call, justify in the plan.
- Pairing: mint accepts optional case_id; response now also carries
  `short_code` (6 chars, unambiguous A–Z0–9 set, no 0/O/1/I), and
  `POST /api/practice/pair/claim` accepts `{token}` OR `{short_code}`.
- api_v1 parity: proposals list gains `claim_token`/`counter` fields;
  document every payload change in the report (iOS consumes these later).

Produces (later phases consume): `claim_proposal(token, user_id)` repo fn;
`'missed'` state; injectable auth on claim endpoints (B2); counter-round
push pattern (B3 reuses for swap invites).

### B4 — Recommendation surfacing (roadmap §B4; spec §7) — branch `bgap/b4-recs`
Anchors: `webapp/repositories/dashboard.py:228` (`recommendations()`),
`:59` (`dimension_averages()`), `webapp/routes/rooms.py:34`,
`webapp/routes/api_v1.py:353` (dashboard), `webapp/routes/practice.py`
(join-config), pair status endpoint.

Deliver (no migrations):
- Extend `recommendations(user_id)` →
  `recommendations(user_id, exclude_case_ids: list[int] = [], limit: int = 5)`
  and add a human-readable `why` string per rule (e.g. rule 3 → "Your
  weakest dimension is market sizing — this case weights it heavily").
  Web callers unchanged.
- New router `webapp/routes/recommendations.py`:
  `GET /api/v1/recommendations?exclude=1,2,3` →
  `{recommendations: [{case_id, title, case_type, difficulty, why, rule}]}`.
  "Swap recommendation" = client re-calls with the swapped id in `exclude`.
- `GET /api/v1/dashboard` gains `dimension_averages` (existing shape from
  the web dashboard) and `recommendations` (same shape as above).
- Interviewer-side mouth: `join-config` and `pair/status/{token}`
  responses gain `counterpart_recommendations` (top 3, same item shape) —
  the candidate's recs shown to the interviewer (spec §7.2). Guard: only
  when the requester is the interviewer.
- Keep engine changes pure-SQL/python in the repository layer; no new deps.

Produces: `recommendations(user_id, exclude_case_ids, limit)` signature +
item shape `{case_id, title, case_type, difficulty, why, rule}` (B3 debrief
seeding and B7 home card consume this verbatim).

### B5 — Identity, profile, onboarding (roadmap §B5; spec §9, §4-avatar) — branch `bgap/b5-identity`
Anchors: `webapp/auth/users.py:27` (domain whitelist CHECK — also
`db/schema.sql:88`), `webapp/routes/auth.py`, `webapp/auth/email_sender.py`
(Resend), `webapp/auth/email_verification.py` (token pattern to reuse),
R2 storage layer (find via `grep -rn "R2\|boto\|s3" webapp/ --include=*.py -l`).

OWNER DECISIONS — RESOLVED 2026-07-17 (these override the spec §9 ordering;
record as deviation DV-B5-1 in your plan):
- OD-B5-1: build ALL THREE — Google OAuth, LinkedIn OAuth, email+passcode
  OTP. Both OAuth flows: hand-rolled OIDC via httpx, env-config
  (`GOOGLE_CLIENT_ID/SECRET`, `LINKEDIN_CLIENT_ID/SECRET`), 503 with a
  clear message when creds absent (dev), token exchange mocked in tests.
  Thomas provides the provider apps later — nothing may hard-require live
  creds.
- OD-B5-2 (owner's words, binding): "the only way a person should be able
  to get a sign-up link is if they enter their email account and it is
  verified that their school address is whitelisted. This whitelist is
  built to be expanded. But for now, providing the email is the first
  verification step. That step leads to the ability to make an account
  using your linkedin account and/or google account. Dan has already
  added email capability. Follow the existing code's lead."
  Concretely: signup entry = school email → domain must match the schools
  registry (expandable by inserting rows — no code change to add a school)
  → sign-up link sent via the EXISTING email-verification infra
  (`webapp/auth/email_verification.py` + Resend sender — extend, don't
  replace) → the verified link opens account completion: password (existing
  path) and/or link Google/LinkedIn. `users.school_id` is stamped from the
  verified email's domain at completion — the whitelist IS the school
  verification; no separate later verify step, no code-entry flow.

Migration 022: users gain `bio TEXT`, `photo_key TEXT`, `linkedin_url TEXT`,
`google_sub TEXT UNIQUE NULL`, `linkedin_sub TEXT UNIQUE NULL`,
`school_id INTEGER NULL REFERENCES schools`; replace the hardcoded
email-domain CHECK constraint (schema.sql:88, users.py:27) with
registry-backed server-side validation.
Migration 023: `schools (id, name, domain TEXT UNIQUE, created_at)` seeded
yale.edu / umich.edu / chicagobooth.edu; backfill existing users'
school_id from their email domains.
Migration 024: `notification_settings (user_id PK/FK, proposals BOOL DEFAULT
TRUE, session_reminders BOOL DEFAULT TRUE, feedback BOOL DEFAULT TRUE,
free_now BOOL DEFAULT TRUE, community BOOL DEFAULT TRUE)`.

Deliver:
- New router `webapp/routes/profile.py`: `GET/PUT /api/v1/profile`
  (display_name, bio, linkedin_url; school read-only here),
  `POST /api/v1/profile/photo` (multipart → R2, content-type whitelist
  jpeg/png/webp, ≤5 MB, key `avatars/{user_id}.{ext}`, returns signed/served
  URL the way case files are served), `GET/PUT /api/v1/settings/notifications`.
- Push fan-out helper consults `notification_settings` before sending —
  one choke-point change in `webapp/push/` (find the send-to-user helper),
  category mapping documented in the report.
- Email+passcode OTP login: `POST /api/v1/auth/otp/request {email}` (always
  202 — no user enumeration; 6-digit code, hashed at rest like
  email_verification, 10-min expiry, ≤3 verify attempts) +
  `POST /api/v1/auth/otp/verify {email, code}` → session cookie. Works for
  existing AND new users (new user rows created unverified-profile but
  usable; signup form path stays).
- Google OAuth (hand-rolled, httpx): `GET /auth/google` (redirect w/ state
  cookie, PKCE) + `GET /auth/google/callback` → verify id_token via
  Google's JWKS, upsert on `google_sub`, import name/photo on first link.
  Config via env (`GOOGLE_CLIENT_ID/SECRET`, absent in dev → endpoints 503
  with clear message; tests mock the token exchange).
- Signup flow per OD-B5-2: `POST /api/v1/signup/request {email}` — domain
  must match a schools row (404-style neutral error otherwise, no
  enumeration); sends the sign-up link through the existing verification
  infra. Link target completes the account (password and/or OAuth link)
  and stamps school_id. Web `/signup` follows the same gate. LinkedIn
  OAuth mirrors the Google deliverable above (`/auth/linkedin` +
  callback, upsert on `linkedin_sub`, OIDC id_token via LinkedIn JWKS).
  OAuth completion/link is only reachable for a verified school email —
  an OAuth identity whose email isn't registry-verified gets a clear
  "request a sign-up link first" error. KEEP existing seeded users
  working (a/b/c@yale.edu, passwords unchanged).

Produces: `users.school_id` + `schools` (B6 leaderboards/groups),
`users.photo_key`/`bio`/`linkedin_url` (B6 profiles/forum),
notification-settings choke point (B6 community pushes), OTP + OAuth
session cookies identical to password login (no downstream changes).

### B2 — Guest interviewer (roadmap §B2; spec §6.2) — branch `bgap/b2-guest`
Consumes: B1 claim endpoints (injectable auth), merged into
`feature/backend-gap` before you branch.
Migration 025: `users.is_guest BOOL NOT NULL DEFAULT FALSE`; make
email/password nullable for guest rows if the schema still forbids it.

Deliver: guest claim on open-link and QR endpoints (`claim/{token}`,
`pair/claim`) when unauthenticated → mints `is_guest` user + session
cookie scoped by a `guest_session_id` claim; guests pass auth ONLY for
their session's endpoints (WS, reveals, rubric, finalize, recordings,
join-config) — a dependency `require_session_participant` enforces it;
guests 403 everywhere else (proposals, library, dashboard, profile).
`POST /api/v1/auth/upgrade {email, password}` (or OTP path) converts the
guest row to a real account in place (history keeps FKs). Swap (B3) must
never be offered to guests — expose `is_guest` in session participant
payloads so B3 can gate. Feedback finalize by a guest works (spec: guests
can interview); their name renders as "Guest" (display_name).

Produces: `users.is_guest`, `require_session_participant` dependency,
upgrade endpoint (B3 gates swap on `is_guest`).

### B7 — Timeline & home diagnostic (roadmap §B7; spec §4-Home, §9.4) — branch `bgap/b7-timeline`
Consumes: B4's dashboard/recs shapes (merged).
OWNER DECISION — RESOLVED 2026-07-17 (OD-B7-1): the readiness signal is an
acknowledged STAND-IN until real usage data exists. Build the default
(dimension averages vs a fixed threshold + minimum recent-case count,
labeled "on track" / "needs work") as ONE swap-point function in a new
`webapp/readiness.py` that every caller goes through. REQUIRED deliverable:
`docs/superpowers/notes/2026-07-17-readiness-signal-seams.md` documenting
(1) exactly what the stand-in computes, (2) the swap-point signature,
(3) every data access point available in code today (rubric dimension
averages, session history, drill attempts, timeline statuses — file:symbol
each) that a future, smarter computation can draw on. The doc is reviewed
like code.

Migration 026: `firms (id, name, slug)` seeded Bain/BCG/McKinsey + Big-4 +
common T2 (curate ~12); `firm_deadlines (id, firm_id, cycle_label,
deadline_date, region NULL)` seeded with 2026–27 US dates from public
sources — mark estimates `is_estimate=TRUE`.
Migration 027: `user_firms (user_id, firm_id, added_at, status TEXT CHECK
IN ('tracking','interviewed','offer','rejected','admitted') DEFAULT
'tracking', result_recorded_at NULL)`.

DESIGN DELTA (2026-07-17, "myCase — Design Decisions" §0.1 + §2-7b): the
post-deadline flow ends in **plan reweighting**, never a forum handoff
(there is no forum). Prompt outcomes: Offer → record card; No offer →
reweight response (`{focus_dimension, suggested_drill_type, extra_cases:
[case_id…]}` derived from the diagnostic + the recommendation engine —
document the derivation as a seam in the readiness doc); Waiting → re-ask
in a week (`snooze_until`); Didn't interview → firm drops off the line.
`admitted` remains a recorded status (data only — nothing gates on it).

Deliver: new router `webapp/routes/timeline.py` —
`GET/POST/DELETE /api/v1/timeline/firms` (track/untrack),
`GET /api/v1/timeline` (tracked firms + next deadline + readiness signal +
post-deadline prompt state), `POST /api/v1/timeline/firms/{id}/result`
(the interviewed?→result?→reweight flow above). Extend
`GET /api/v1/dashboard` with `diagnostic` block:
cases done last 60 days, per-dimension strengths (top 2) / weaknesses
(bottom 2), trend (mean grade last 5 vs previous 5), plus `timeline`
summary (next deadline across tracked firms). Nightly-ish deadline-passed
push ("Did you interview at Bain?") from the existing 60-s loop with a
daily guard — respect notification settings if B5 merged (it will be).

Produces: `user_firms.status='admitted'` (B6 forum gate), timeline payload
(UX Home), diagnostic block shape.

### B3 — Session-flow additions (roadmap §B3; spec §6.1–6.4, §7.3, A2, A5) — branch `bgap/b3-sessionflow`
Consumes (all merged by your branch time): B1 (counter pattern, missed),
B2 (`is_guest`, `require_session_participant`), B4 (`recommendations()`).
Migration 028: `practice_sessions` state CHECK gains `'negotiating'` (before
`lobby`); `case_negotiations (id, session_id FK, proposed_case_id, by_user_id,
round INT, state pending|accepted|declined, created_at)`; `practice_sessions.
swapped_from_session_id INTEGER NULL REFERENCES practice_sessions`.
Migration 029: feedback gains `viewed_at TIMESTAMPTZ NULL`, `closed_at
TIMESTAMPTZ NULL`, `case_rating SMALLINT NULL CHECK (case_rating BETWEEN 1
AND 5)`, `feedback_thumbs BOOL NULL`.
DESIGN DELTA (2026-07-17, "myCase — Design Decisions" §0.5, overrides spec
§6.4/A2): recap close-out requires a **1–5 case rating** (same scale as
debrief), NOT a helpful-Yes/No. `feedback_thumbs` stays optional
("Worth it"=true / "Thin"=false), authenticated interviewers only.

Deliver:
- **Negotiation**: sessions created without a case (B1's null-case paths)
  start in `negotiating`. Endpoints on the session:
  `GET /api/practice/{id}/negotiation` (current proposal, whose turn,
  candidate's requested case if the originating proposal carried one,
  interviewer pick sources: candidate's `counterpart_recommendations`,
  interviewer's own done-set = cases they've been candidate on, full
  library allowed), `POST .../negotiation/propose {case_id}` (one
  counter-suggestion each side max — round ≤2), `POST .../negotiation/accept`
  → stamps `practice_sessions.case_id`, state → `lobby`, broadcast
  `session_update` on the signaling WS (existing helper). Sessions created
  WITH a case (legacy paths) skip `negotiating` entirely — zero regression,
  the 290-odd existing session tests must stay green untouched.
- **Role swap** (spec §6.3, A5): `POST /api/practice/{id}/swap` — allowed
  from `debrief`/`finalized`, authed interviewers only (403 for
  `is_guest`), creates a pending swap invite (push to the other party,
  reuse B1's invite/counter push pattern); `POST /api/practice/{id}/swap/accept`
  → new session, roles reversed, same mode, state `negotiating`,
  `swapped_from_session_id` set; recap gate checked on the NEW candidate
  at accept time.
- **Recap gate** (spec §6.4, A2 + design delta §0.5): `GET /api/v1/recaps`
  (unread finalized feedback as candidate, oldest first);
  `POST /api/practice/{id}/recap/viewed` (stamps viewed_at);
  `POST /api/practice/{id}/recap/close {case_rating: int 1–5,
  feedback_thumbs: bool|null}` — case_rating REQUIRED (1–5, same scale as
  debrief; debrief close-out IS this endpoint), thumbs only recorded if
  the interviewer wasn't a guest, stamps closed_at. Expose per-case
  aggregates (avg rating to one decimal + run count, e.g. "4.1 · 12 runs")
  on case list/detail payloads, plus `done_for_you: bool` (burned as
  candidate) and open/done counts — the Library "retired cases" delta
  (§0.4) renders from these. Leave legacy case_votes untouched. Gate helper
  `candidate_gate(user_id) -> Optional[session_id]` in the feedback repo:
  oldest finalized-undelivered… precisely: feedback finalized AND
  closed_at IS NULL → blocked. Enforce (409 with `{blocked_by_recap:
  session_id}`) on the four candidate entries: proposal accept (into
  candidate seat), proposal claim, pair claim, swap accept — and on
  `POST /api/practice` direct creation as candidate. Never blocks
  interviewer seats, drills, or browsing. Debrief close-out in the normal
  flow = the same close endpoint (happy path per spec).
- **Debrief seeding** (spec §7.3): finalize response + the existing
  feedback push gain `next_recommendation` (top rec, B4 shape) and
  `prefill_proposal {to_user_id, case_id}` for "schedule your next".

Produces: gate 409 contract + recap endpoints (UX), negotiation state
machine (UX), swap linkage.

### B6 — Community (roadmap §B6; spec §4-Community) — branch `bgap/b6-community`
Consumes: B5 (schools, profile fields, notification choke point).
DESIGN DELTAS (2026-07-17, "myCase — Design Decisions" §0.1–0.2, override
the spec and the roadmap):
- **The admitted forum is NIXED. No forum anywhere.** Do not build
  forum_threads/forum_posts or a forum router. Community = school standing
  + groups + connections only.
- **No population counts, ever.** No leaderboard payload may carry a total
  member/player count or "of N" data. Standings are expressed as
  percentiles (e.g. 91st). Literal ranks + points are allowed ONLY inside
  a joined group (small cohorts of people who know each other).
  School-vs-school = average member percentile + campus city.
Migrations 030–033 (032 now unused — leave the number vacant): 030
`connections (user_id, friend_id, state pending|accepted, requested_at,
responded_at, PK(user_id,friend_id))`; 031 `groups (id, name, school_id
NULL, created_by, created_at)` + `group_members (group_id, user_id, role
TEXT CHECK IN ('admin','member'), joined_at, PK(group_id,user_id))`;
033 leaderboard indexes as needed.

Deliver (router per domain: `connections.py`, `groups.py`, `forum.py`,
`leaderboards.py`):
- Connections: request/accept/decline/remove, list with profile cards
  (photo/bio via B5); feeds "ping a friend" — extend B1's proposal create
  so a `to_user_id` must be self-or-connection? NO — any known user stays
  allowed (existing behavior); connections are the UX picker source only.
- Groups: create (creator = admin; spec buries this under avatar — API
  doesn't care), join by invite code (6-char, reuse B1's short-code
  helper), leave, transfer-admin; role-gated `GET /api/v1/groups/{id}/progress`
  (per member: cases done, mean grade, drill attempts last 30 d,
  streak) — admin only, 403 members; group leaderboard (sessions
  finalized + drill volume, last 30 d).
- School surfaces: school standing (percentile-based per the delta above;
  school-vs-school = avg member percentile + campus city); school-leader
  role = `school_leaders (school_id, user_id)` seedable (admin-assigned;
  no self-serve path yet), gated per-group rollup view. NO chat/DM/forum
  anywhere. Community pushes (connection request, group invite) through
  B5's settings choke point under `community`.

Produces: `connections` (UX picker; connection rows may carry status
decorations like free-now — join against availability), group/school
leaderboard queries honoring the no-headcount rule (B8 reuses the scoping
CTEs — put them in `webapp/repositories/leaderboards.py`).

### B8 — Drills aggregation (roadmap §B8; spec §4-Drills) — branch `bgap/b8-drills-agg`
Consumes: B6 leaderboard scoping. OWNER DECISION — RESOLVED 2026-07-17
(OD-B8-1): SEAMS ONLY. Build `daily_set()` (date-seeded, same for all
users, N slots) behind the existing `/api/v1/drills` seam returning the 3
existing generator types filling 6 slots, marked `"provisional": true`.
REQUIRED deliverable: `docs/superpowers/notes/2026-07-17-drills-bank-integration.md`
— the exact contract the future question-bank DB plugs into: `daily_set()`
signature and provider interface, per-user template selection hooks,
attempt-scoring interface, the migration-019 reservation, and a worked
"when the bank lands, do these N steps" checklist. Owner intent: "build
documentation and connections to make it super easy for the eventual call
from the questions database for each user." The doc is reviewed like code.
Migration 034: `drill_attempts` gains `score REAL NULL`, `duration_ms INT
NULL`, `set_key TEXT NULL` (e.g. `2026-07-17` for gauntlet membership).
Migration 035: indexes for rank queries.

DESIGN DELTA (2026-07-17, "myCase — Design Decisions" §0.2): results and
boards are percentile-first and must NEVER expose population counts
("of N"). Literal rank + points appear ONLY in the joined-group scope;
school and global scopes are percentiles; school-vs-school = avg member
percentile + campus city.

Deliver: `GET /api/v1/drills/gauntlet` (today's global set) +
`POST /api/v1/drills/gauntlet/attempts` (scored, one submission per user
per day — 409 on repeat); results payload: score, daily percentile
(among today's submitters, no counts), group rank + points (joined-group
scope only; null if unaffiliated), school percentile, vs-peers delta;
`GET /api/v1/drills/boards?scope=group|school|global|schools` honoring the
delta; `GET /api/v1/drills/trends` (daily scores last 60 d + per-type
accuracy); keep the existing per-user daily drill endpoints untouched
(iOS P4 consumes them). Percentile = SQL `percent_rank()` — no new deps.

## 7. Merge protocol (orchestrator only)

Per phase DONE: read report → spot-check suite in the phase worktree →
`git merge --no-ff bgap/<phase>` into `feature/backend-gap` in the base
worktree, resolving conflicts (expected: api_v1.py registrations,
settings.py) → run the FULL suite against a fresh
`caserepo_bgap_integration` DB (schema + all migrations including the
new ones) → commit merge, log in ORCHESTRATION.md → then cut next-wave
worktrees. A red integration suite = fix-forward with one Opus fix agent
in the base worktree, never rewrite phase branches. Thomas merges
`feature/backend-gap` onward; we never touch his branches.

## 8. Report & escalation summary

Statuses: DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED — same
semantics as subagent-driven-development. BLOCKED must contain the
packaged question (goal / tried + exact errors / paths / the one
question). No Fable consults from any agent — packaged questions ride the
report to the orchestrator, who queues them for Thomas.
