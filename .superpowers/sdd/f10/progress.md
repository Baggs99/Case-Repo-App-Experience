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
- Task 2 (console-lite): complete, commit 77bf016, review BOTH PASS. 10 tests green; full lifecycle curl-smoked.
  Fold into Task 3: M1 fetch real cases.case_type for kicker (not "CASE"); M2 assert finalize grade==4.0;
  M3 drop `session` from template context (only boot needed). M4 optional fetch .ok hardening (skip).
- Task 3 (keep + upgrade + on-the-record): complete. `GET /g/session/{id}/keep`
  + `GET /g/session/{id}/saved` (guest_web.py) + guest_keep.html (canvas 8a
  gIsPost, verbatim styling; guest branch = upgrade ask w/ inline JS POSTing
  the EXISTING /api/v1/auth/upgrade; non-guest branch = plain "Saved to your
  record.") + guest_saved.html (gIsMade staircase-draw "On the record.",
  unique gradient id g26; `?guest=1` → honest "Kept for now." close state,
  no false on-the-record claim; canvas's "Demo: back to the link" debug
  link omitted, production has no reset path). Folded in M1 (real
  cases.case_type via one extra get_case_by_id lookup), M2 (finalize
  response grade==4.0 regression guard on the existing lifecycle test), M3
  (guest_console render context now just `{"boot": boot}` — confirmed
  guest_console.html never referenced `session.*`). 6 new tests: keep
  pre-finalize 303, keep post-finalize guest upgrade-ask markup, non-guest
  claimer "Saved to your record." (no upgrade form), upgrade happy path
  (fresh guestkeep+<uuid>@yale.edu, is_guest flips to FALSE, then /saved
  shows "On the record."), upgrade bad-domain 400 surfaced, /saved?guest=1
  "Kept for now." close copy. 16/16 green
  (`pytest tests/test_f10_guest_web.py -q`).
