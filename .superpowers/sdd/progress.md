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
