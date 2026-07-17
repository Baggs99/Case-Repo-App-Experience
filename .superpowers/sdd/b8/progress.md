# B8 — Drills aggregation & gauntlet seams · progress ledger

Branch: bgap/b8-drills-agg · Worktree: /Users/thomaskgould/dev/bgap-b8 · DB: caserepo_bgap_b8
Interpreter ($PY): /Users/thomaskgould/dev/Case-Repo-App-Experience/.venv/bin/python
Run suite: DATABASE_URL=postgresql://localhost/caserepo_bgap_b8 $PY -m pytest tests/ -q  (no `timeout` binary on this mac → run detached)

## Baseline
- Bootstrap DONE — createdb caserepo_bgap_b8, schema.sql + migrations 0*.sql applied clean, .env copied (DATABASE_URL→caserepo_bgap_b8, gitignored), users a/b/c@yale.edu seeded via scripts/seed_caseroom_dev.py.
- Baseline suite: **585 passed, 0 failed** (evidence: pytest tail "585 passed, 630 warnings in 8.69s"). Finish line = 585 + N new.

## Now
- Executing tasks. Plan APPROVED (fresh Opus review: 0 Critical / 0 Important, 6 Minor).

## Plan review
- Verdict APPROVE. Applied M2 (flaky -1 sentinel → regenerate provably-wrong answers), M3 (score_slot tolerance_factor sorted() guard), M4 (group comment: most-recently-created not "first joined"). Not changed (documented): M1 school_percentile==global (matches B6 my_school_standing.your_percentile — owner nod deferred), M5 cold-start lone submitter reads 0th percentile (percent_rank convention, matches B6), M6 private _TYPES import (mirrors internal use).

## Done
- Plan + plan-review fixes.

## Task ledger
- Task 1 (migrations 034/035): complete (commits 35b0882..9d0f274, review SPEC PASS/CODE PASS, 2 non-blocking Minors: index test asserts name-not-shape [verified correct live], unqualified catalog filters). Test 2/2, idempotent exit 0.
- Task 2 (drills.py gauntlet primitives: daily_set/public_drill/score_slot): complete (commit f52c5f7, review SPEC PASS/CODE PASS, append-only verified byte-identical). Test 8/8. Triaged Minors for final: provisional flag stamped by route (Task 6, verify), header-docblock line, optional test hardening (choices-kept, negative-factor).
- Task 3 (webapp/repositories/gauntlet.py): complete (commit 6e45231, review SPEC PASS/CODE PASS; race-safety [advisory xact lock in one txn, autocommit=False verified], guest-exclusion, FK-cascade all empirically confirmed). Test 6/6. Minors (triaged): shared-date '2026-07-17' hermeticity latent [B6 convention; full-suite run proves it], stale count.
- Task 4 (leaderboards.py ACTIVITY_POINTS_SQL +gauntlet score): complete (commit e0fc323, review SPEC PASS/CODE PASS; B6 PROVABLY SAFE — logical proof + 0 set_key rows + 28/28 green; scope confined to 3 intended regions; guest-exclusion intact). Test new 3 + all B6 green. Minors (triaged, no change — minimize churn on shared file): 0-score gauntlet-only user excluded from population [defensible; POINTS=0 either way; streak still counts], points widens to REAL [order-invariant].
- Task 5 (webapp/gauntlet.py service submit/results_for/trends): complete (commit 8e8e506, review SPEC PASS/CODE PASS; grouped-user rank math proven on live DB — board[rank-2] delta correct; design-delta compliant, no forbidden keys). Test 5/5. Minors → FINAL FIX BATCH: M1 add school_percentile code comment, M2 raise InvalidSubmission (not TypeError) on a slot-less answer + covering test, M3 _group_block docstring wording ("most recently created group you belong to").

## Assumptions
- school_percentile in the gauntlet results = user_global_percentile (the value B6's my_school_standing.your_percentile surfaces on the school card). A distinct within-school population is a future refinement; brief only says "school percentile".
- Gauntlet results "primary group" = most-recently-created joined group (list_my_groups DESC). Persona has one group, so deterministic in practice.
- Trends/percentile scoped to gauntlet rows (set_key IS NOT NULL); the unscored per-user practice drills (/drills/attempts) have no score and stay out of the scored trend.
