# F10 Guest Web — Ledger
Baseline: 655 passed (caserepo_fe_f10, seeded). Branch fe/f10-guestweb @ ae46fed.

## Tasks
- Plan: written docs/superpowers/plans/2026-07-17-fe-f10-plan.md — pending plan-review.
- Plan-review: Opus, 1 Critical (lifecycle) + I2/I3 + minors → plan revised (commit 5aa48ae).
- Task 1 (link-gate): complete, commit 2b9d0b3, review BOTH PASS. 4 tests green.
  Minors for final triage: gate subtitle shows case_title twice (use case framing);
  test doesn't assert Set-Cookie; redundant case_id IS NOT NULL (harmless).
- Task 2 (console-lite): complete. `GET /g/session/{id}` (guest_web.py) +
  guest_console.html (canvas 8a gIsLive, verbatim styling) + guest_console.js
  (lifecycle driver: consent→lobby, poll for candidate consent, live clock,
  release, score-overlay finalize). 6 new tests drive the REAL lifecycle
  (consent/lobby/live/reveal/debrief/finalize) end-to-end incl. IDOR 403,
  real-non-participant 404, candidate-seat redirect, no-exhibit guard, and
  the post-finalize 303 to /g/session/{id}/keep. 10/10 green
  (`pytest tests/test_f10_guest_web.py -q`). Also curl-verified live against
  a dev server (port 8110) through finalize; smoke-test rows cleaned up.
  boot.caseType always "CASE" (get_practice_session's join has no case_type
  column — DV-F10-1 already covers dropping the read-aloud/guidance text,
  this is the same shape of gap, not flagged separately).
