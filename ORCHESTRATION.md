# Backend Gap — Orchestration Ledger

Updated: 2026-07-17T00:00Z (update on every wave event)
Authority docs: docs/superpowers/plans/2026-07-17-backend-gap-execution.md (+ roadmap, + UX spec)
Integration branch: feature/backend-gap · base worktree: /Users/thomaskgould/dev/bgap-base

## Wave status

| Phase | Branch | Worktree | Status | Head | Suite |
|---|---|---|---|---|---|
| B1 scheduling | bgap/b1-scheduling | ~/dev/bgap-b1 | MERGED e315b68 | 350d069 | 402 phase / 418 integration |
| B4 recs | bgap/b4-recs | ~/dev/bgap-b4 | MERGED c0f26ca | 27a2e2a | 376 pass (phase + integration) |
| B5 identity | bgap/b5-identity | ~/dev/bgap-b5 | MERGED 7b119ec | 0e978d5 | 420 phase / 478 integration |
| B2 guest | bgap/b2-guest | ~/dev/bgap-b2 | MERGED | 55d0f55 | 451 phase / 545 integration |
| B7 timeline | bgap/b7-timeline | ~/dev/bgap-b7 | MERGED | c1df02c | 452 phase / 512 integration |
| B3 sessionflow | bgap/b3-sessionflow | ~/dev/bgap-b3 | MERGED | 390ef3b | 576 phase / 616 integration |
| B6 community | bgap/b6-community | ~/dev/bgap-b6 | MERGED | d9291ab | 552 phase / 585 integration |
| B8 drills-agg | bgap/b8-drills-agg | ~/dev/bgap-b8 | MERGED | 1b5fb38 | 624 phase / 655 integration |

## Owner decisions

| ID | Question | Answer (2026-07-17) |
|---|---|---|
| OD-B5-1 | LinkedIn OAuth at launch? | ALL THREE: Google + LinkedIn OAuth + email OTP. Thomas supplies provider creds later; code 503s cleanly without them. |
| OD-B5-2 | School registry scope | Whitelist-gated sign-up LINK is the entry step (registry expandable by row insert); verified link → account completion incl. Google/LinkedIn. Follow Dan's existing email-verification code. |
| OD-B7-1 | Readiness-signal definition | Stand-in OK (threshold default); MUST ship seams doc: what it computes + code access points for future data-driven versions. |
| OD-B8-1 | Gauntlet now vs after drills bank | Seams only + bank-integration contract doc ("super easy" plug-in for the eventual per-user question DB call). |

## Design deltas applied 2026-07-17 (source: docs/design/myCase - Design Decisions.md §0)

Briefs for B3/B6/B7/B8 amended BEFORE their dispatch: forum nixed (B6/B7),
percentiles-never-headcounts (B6/B8), recap close-out = required 1–5 rating
+ case aggregates + done_for_you flags (B3), post-deadline flow ends in
plan reweighting (B7). Wave-1 phases (B1/B4/B5) unaffected — verified
against §0 before amending.

## Front-end track (STAGED — dispatch after backend integration is green)

Plan: docs/superpowers/plans/2026-07-17-frontend-execution.md.
Waves FW1–FW7 (F0 foundation → F1 shell → F2/F4 → F7/F8 → F3/F5 → F6 →
F9/F10), max 2 parallel (sim load). Leads/reviewers Opus, implementers
Sonnet except JUDGMENT-marked tasks. Design canon imported to docs/design/
(Mobile canvas truncated in the stale 1-series tail — see README there).
Thomas demo checkpoints: after FW2, FW5, FW7.

## Merge log

- 2026-07-17 B4 → feature/backend-gap @ c0f26ca (phase head 27a2e2a).
  Integration suite 376 passed on fresh caserepo_bgap_integration
  (NOTE: integration DB needs `scripts/seed_caseroom_dev.py` after
  migrations or 135 DB tests skip — added to protocol). API note for iOS:
  recs payload key is `title` (never shipped as `case_title` in /api/v1).
  Final review caught+fixed a grade leak to interviewer surface (33a982b).

## Merge log (cont.)

- 2026-07-17 B1 → feature/backend-gap @ e315b68 (phase head 350d069).
  Integration 418 passed (360+16 B4+42 B1). Sole conflict: both phases'
  .superpowers/sdd/progress.md (add/add) — concatenated; §6 now mandates
  per-phase sdd subdirs. B1 DD-1 seam: case-less accept → needs_negotiation
  + null session; case-less pair claim 409s — B3 builds negotiating from
  these. B1 deferred items ride to B2 (claim_token null hygiene) and B3.

- 2026-07-17 B5 → feature/backend-gap @ 7b119ec (phase head 0e978d5).
  Integration first ran 475/3: migration-023 school backfill only covers
  pre-existing users; fresh-DB flow seeds after migrations → seeded users
  had NULL school_id. Fixed forward in seed_caseroom_dev.py (registry-aware
  school binding) → 478 passed (360+16+42+60). WAVE 1 COMPLETE.

- 2026-07-17 B7 → feature/backend-gap (phase head c1df02c). ZERO conflicts
  (per-phase sdd subdir rule working). Integration 512 passed (478+34).
  Deadline-prompt push maps to notification category session_reminders.

- 2026-07-17 B2 → feature/backend-gap (phase head 55d0f55). Textually
  clean; ONE semantic conflict fixed forward: B2's migration 025 re-created
  the hardcoded email-domain CHECK that B5's 022 had dropped (B2 built
  pre-B5). Resolution: 025 rewritten — constraint users_guest_email_shape
  (is_guest OR email IS NOT NULL); domain policy stays application-level
  (schools registry). Obsolete B2 domain test converted to guard the new
  contract + made hermetic. Integration 545 passed (512+33). WAVE 2 DONE.

- 2026-07-17 B6 → feature/backend-gap (phase head d9291ab). Zero conflicts.
  Applied B6's documented B2 seams at merge: guests excluded from
  ACTIVITY_POINTS_SQL population + connection targeting (guest joins
  already 403 at route layer — seam 3 not needed). swap_invite_pending
  stays hardcoded false until B3 merges (LEFT JOIN seam in B6 report).
  Integration 585 passed (545+40).

- 2026-07-17 B3 → feature/backend-gap (phase head 390ef3b). Zero conflicts.
  Wired B6's swap_invite_pending seam at merge (EXISTS against
  swap_invites in connections.list_accepted — EXISTS not LEFT JOIN to
  avoid row dup when both directions have pending invites). Integration
  616 passed (585+31). B3 DEFERRED notes incl. the Task-7 residual
  (banked earlier) live in bgap-b3-report. 7 of 8 phases merged.

- 2026-07-17 B8 → feature/backend-gap (phase head 1b5fb38). Zero conflicts
  (B8 cut post-seam, extension provably B6-safe). Integration 655 passed.
  **BACKEND GAP COMPLETE: 8/8 phases, 360 → 655 tests, migrations
  020–035 (019+032 vacant by design).** Front-end track FW1 (F0) begins.

## Front-end merge log

- 2026-07-17 F0 → feature/backend-gap (phase head 19e9ce1). Zero conflicts;
  merged tree byte-identical to phase head and diff scope = ios/+docs only,
  so the phase's verified 289-green iOS run stands for the base (backend
  suite untouched). OPERATIONAL (every fe lead): fresh sims need
  `xcrun simctl privacy <sim> grant microphone study.mycase
  study.mycase.CaseRoomTests com.apple.dt.xctest.tool` or the suite hangs
  at the Live Activity test; macOS has no `timeout` — perl alarm pattern.
  F0 process deviation (direct Opus-lead implementation w/ Opus review
  gates, no per-task subagents) accepted — documented in fe-f0-report,
  whole-branch review APPROVE. Deferred to F2: SteppedTimeline label
  hierarchy inversion + flat chip glass variant (explicit actions in
  report). FW2 (F1 shell) dispatched.

- 2026-07-17 F1 → feature/backend-gap (phase head c4d89da). Zero conflicts;
  code tree byte-identical to the 313-green phase head. **FW2 COMPLETE —
  shell demo checkpoint READY** (needs Thomas signing via ship). Backend
  follow-up noted by F1 (non-blocking): GET /api/v1/profile lacks OAuth-link
  flags; avatar LINKED derives from linkedin_url — expose google_sub/
  linkedin_sub presence booleans in a future backend touch.

- 2026-07-17 MAC MINI CUTOVER complete. Orchestration moved MacBook → mini
  @ 72c4351. Baselines re-verified on the mini: backend 655 / iOS 313 (0
  failures) on Xcode 27 beta 27A5218g via DEVELOPER_DIR (no xcode-select —
  sudo pending, see escalations) — no toolchain deviation vs MacBook 26.6.
  **FW3 DISPATCHED**: fe/f2-home (~/dev/fe-f2, DB caserepo_fe_f2, port
  8102, sims 942222D4/653F37B8) + fe/f4-library (~/dev/fe-f4, DB
  caserepo_fe_f4, port 8104, dedicated sims 49C5BC31/7D87AA5A), both cut
  at 72c4351. Opus leads, sonnet implementers, synchronous subagents,
  40-min stall watchdog armed.

- 2026-07-17 F2 → feature/backend-gap @ 0780184 (phase head 6097118, merge
  clean). Fresh integration DB: backend 655, iOS 367/0. §7 sim smoke (real
  server, seeded user, -DevLogin/-startTab hatches): Case tab / avatar
  sheet / Library PASS; Home FAIL (stuck loading) → fix-forward b6e9288:
  `ProfileDetail.school` was `String?` vs B5's `{id,name,domain}` object —
  decode typeMismatch swallowed by HomeViewModel's catch; masked in the
  phase DB (null-school user), surfaced by integration a@yale.edu. iOS
  retyped to `SchoolRef?` + live-payload regression fixture; 368/0; smoke
  step 1 re-run PASS (merge-smoke-1-home-FIXED.png). RESIDUAL (follow-up,
  non-blocking): HomeViewModel.load()'s single catch still swallows decode
  errors silently — contract wants loud dev asserts; sibling VMs may share
  the pattern. F2 owner-gates for the FW3 demo: (1) phone tonight strip is
  LIGHT per canvas pixel-truth vs DD §2 "dark" prose; (2) secondary-label
  weight 600. F2 backend follow-ups: recap star-rating missing from any
  GET; set-user-deadline endpoint (Timeline "Set date" inert until then).

- 2026-07-17 F4 → feature/backend-gap @ 3844702 (phase head 097c681, 22
  commits). Auto-merge clean incl. RootShell (both FW3 phases mounted
  NavigationStacks — compile-verified). Fresh integration DB: backend 655;
  iOS FULL suite **413/0** (368 + 45 F4) INCLUDING SessionViewModelTests —
  F4's reported mic-TCC hang was environmental (its sim under 2.5h dual-
  phase load), NOT an Xcode-27-beta blocker; no action for F5. §7 smoke
  PASS all 5 steps (Home w/ school-fix holding, Case, avatar sheet, NEW
  Library w/ chips+toggles+counts, case detail via -startCaseDetail seam);
  crash sweep clean. **FW3 COMPLETE.** F4 seams/deviations (report):
  rec/scheduled row decorations fixture-only (cases payload lacks B4
  cross-ref); detail CTA → .caseTab interim until F3 case-prefill;
  "Market Sizing" chip exact-match may under-match live compound
  case_type; history joined by case_title (no case_id in payload — backend
  follow-up candidate); CasesViewModel retained (Pair/Propose pickers).
  Smoke nav facts for later phases: tab arg is `caseTab`; -startCaseDetail
  <id> exists; push-permission dialog overlays first launch (grant via
  simctl not permitted — dismiss manually or ignore).

- 2026-07-17 FW4 DISPATCHED: fe/f7-drills (~/dev/fe-f7, DB caserepo_fe_f7,
  port 8107, sims 942222D4 + iPad 653F37B8) + fe/f8-community (~/dev/fe-f8,
  DB caserepo_fe_f8, port 8108, sims 49C5BC31 + iPad 7D87AA5A), cut post-
  FW3. Opus leads, sonnet implementers (F7 run-mechanics JUDGMENT → opus),
  synchronous subagents, watchdog re-armed.

- 2026-07-17 F8 → feature/backend-gap @ a3b0d27 (phase head 0ee9dc2). Merge
  clean. Fresh integration DB: backend 655; iOS FULL **455/0** (413 + 42).
  §7 smoke PASS (Home live, Community live w/ correct empty-states on the
  sparse seed, Library regression clean, avatar sheet shows "Administer a
  group"); group-create sheet not smoke-driven (fixture-only -GroupCreate
  Fixtures route — real flow needs tap-driving; covered by VM tests +
  phase shots). Crash sweep clean. F8 stayed inside the pinned AppRoute
  enum (groupCreate = router bool, no new case). Contract note: B6
  report's "swap_invite_pending always false" line is STALE (pre-B3) —
  /connections serves it live. Known MINOR deferred: admin member-progress
  Retry re-runs board load, not progress fetch. F7 still in flight —
  FW4 closes at its merge.

## Escalations queued for Thomas

- B5 THOMAS MANUAL (bgap-b5-report.md): create Google Cloud + LinkedIn
  developer apps (redirect URIs + env vars listed there); set
  WEBAPP_SESSION_SECRET in prod .env. Non-blocking: OAuth 503s cleanly
  until then; all flows mocked in tests.
- B7: all seeded firm deadline dates are curated ESTIMATES
  (is_estimate=TRUE) — replace with real 2026-27 cycle dates before launch.
- B8 assumption awaiting owner nod: school_percentile currently =
  percentile within the GLOBAL population (not school-internal);
  duration_ms captured now for the future unified performance score.
- B5 DEFERRED (tracked, unscheduled): OTP/signup rate-limiting,
  login_otp_codes reaping, orphaned-avatar cleanup, stale Booth template copy.

## Relayed review verdicts (for phase leads / merge-time checks)

- B3 Task 7 Important #1 (concurrent double-accept race): RESOLVED per
  relayed Opus re-review (2026-07-17) — claim_invite single-winner under
  READ COMMITTED verified, loser 409s pre-create, gate precedes claim,
  SQL parameterized, guards intact; tests/test_b3_swap.py 4 passed.
  RESIDUAL (non-blocking, check at B3 merge): if create_negotiating_session
  raises after claim, invite is left state='accepted' w/ null session and
  invitee cannot retry (404). Optional hardening: one txn around
  claim+create+attach, or reset invite to pending on create failure.
  If absent from bgap-b3-report DEFERRED, add at merge.
