# B1 Scheduling Core — SDD Progress Ledger

Branch: bgap/b1-scheduling · DB: caserepo_bgap_b1 · Interpreter: /Users/thomaskgould/dev/Case-Repo-App-Experience/.venv/bin/python

## Baseline
- 2026-07-17: env bootstrapped (own DB caserepo_bgap_b1, schema + migrations 002-018, seeded a/b/c@yale.edu + dummy case).
- Baseline suite: **360 passed** (`.venv/bin/python -m pytest tests/ -q`, 6.22s). Finish line = 360 + N.

## Tasks
(pending plan authoring)

## Plan
- Plan written: docs/superpowers/plans/2026-07-17-bgap-b1-plan.md (9 tasks, full TDD code). Commit 378d81a.
- Plan review (Opus, agent abca4f15): SOUND, no Criticals. 3 Important + 7 Minor — ALL applied to plan:
  I-1 respond() non-participant → 404 (DV-11); I-2 maintenance_loop sleep-first + full-suite regression; I-3 claim_proposal(token,...) param matches brief; M-1 rooms.py:48 sweep noted; M-2 keep sweep_expired() in accept; M-3 self-claim-by-code test; M-4 case-less scheduled accept test; M-5 regen token in mint retry; M-7 starting_soon docstring. M-6 (partial unique index vs UNIQUE) = deliberate, report-noted.

## Tasks
- Task 1: complete (commits f1721cf..6a72e75, review CLEAN — migrations 020/021 idempotent, spec-compliant)
- Task 2: complete (commit ab30892, review CLEAN — env-tunable expiry settings, suite 362 green)
- Task 3: complete (commit 62fb963, review CLEAN — nullable case/recipient + claim_token, suite 366 green)
- Task 4: complete (commit bcab307, review PASS both verdicts — claim endpoint + claim_proposal(token,user_id), suite 373 green). NOTE (carried to final review, Minor): the 2-file isolated-pair failure is a PRE-EXISTING second-resolution email-filename collision in dev ConsoleEmailSender (webapp/auth/email_sender.py:90 uses %Y%m%dT%H%M%SZ granularity + B1 test classes don't clean output/emails/); exposed not caused by Task 4; full suite green via wall-clock spacing. Optional hardening: sub-second filenames or tearDownClass email cleanup.
- Task 5: complete (commit 193e09e, review CLEAN — one-round counter + counter-accept state machine, DV-11 preserved, suite 380 green)
- Task 6: complete (commit a7ba0b2, review PASS both verdicts — A3 expiry (now/scheduled/countered) + sweep_missed, suite 389 green). MINOR findings carried to final review: (m6a) stale "8-day" comment at routes/proposals.py:93; (m6b) sweep_missed 'live'/protected-state + 'lobby'-branch untested; (m6c) no sweep idempotency/re-run test; (m6d) latent naive-datetime ::timestamptz cast edge (client sending offset-less ISO → resolved vs DB TimeZone GUC; all current tests tz-aware; consider normalizing to UTC in create/counter_proposal).
- Task 7: complete (commit 1002191, review CLEAN — sleep-first maintenance_loop runs all sweeps unconditionally, clean shutdown, suite 390 green). MINOR (final review): (m7a) dead code webapp/push/starting_soon.py:58-71 starting_soon_loop now unreferenced (+ import asyncio would be unused if removed) — optional cleanup.
