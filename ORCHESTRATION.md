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
| B2 guest | bgap/b2-guest | ~/dev/bgap-b2 | DISPATCHED w2 | — | — |
| B7 timeline | bgap/b7-timeline | ~/dev/bgap-b7 | DISPATCHED w2 | — | — |
| B3 sessionflow | bgap/b3-sessionflow | — | WAITING w3 (needs B1,B2,B4) | — | — |
| B6 community | bgap/b6-community | — | WAITING w3 (needs B5,B7) | — | — |
| B8 drills-agg | bgap/b8-drills-agg | — | WAITING w4 (needs B6 + OD-B8-1) | — | — |

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

## Escalations queued for Thomas

- B5 THOMAS MANUAL (bgap-b5-report.md): create Google Cloud + LinkedIn
  developer apps (redirect URIs + env vars listed there); set
  WEBAPP_SESSION_SECRET in prod .env. Non-blocking: OAuth 503s cleanly
  until then; all flows mocked in tests.
- B5 DEFERRED (tracked, unscheduled): OTP/signup rate-limiting,
  login_otp_codes reaping, orphaned-avatar cleanup, stale Booth template copy.
