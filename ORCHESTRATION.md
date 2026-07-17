# Backend Gap — Orchestration Ledger

Updated: 2026-07-17T00:00Z (update on every wave event)
Authority docs: docs/superpowers/plans/2026-07-17-backend-gap-execution.md (+ roadmap, + UX spec)
Integration branch: feature/backend-gap · base worktree: /Users/thomaskgould/dev/bgap-base

## Wave status

| Phase | Branch | Worktree | Status | Head | Suite |
|---|---|---|---|---|---|
| B1 scheduling | bgap/b1-scheduling | ~/dev/bgap-b1 | DISPATCHED w1 | — | — |
| B4 recs | bgap/b4-recs | ~/dev/bgap-b4 | DISPATCHED w1 | — | — |
| B5 identity | bgap/b5-identity | ~/dev/bgap-b5 | DISPATCHED w1 | — | — |
| B2 guest | bgap/b2-guest | — | WAITING w2 (needs B1 merged) | — | — |
| B7 timeline | bgap/b7-timeline | — | WAITING w2 (needs B4 merged) | — | — |
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

## Merge log

(none yet)

## Escalations queued for Thomas

(none yet)
