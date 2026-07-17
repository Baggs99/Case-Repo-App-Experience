# B4 — Recommendation surfacing · SDD ledger

Branch: bgap/b4-recs · DB: caserepo_bgap_b4 · Baseline: 360 passed (green)

## Ledger
- Env bootstrap: DB created, schema+18 migrations applied, seeded a/b/c@yale.edu, baseline 360 passed.
- Plan: docs/superpowers/plans/2026-07-17-bgap-b4-plan.md (4 tasks). Plan-review APPROVED (be5c476 applied nits).
- Task 1: complete (commits be5c476..ee446b6, review clean). recommendations() extended: why/exclude/limit/canonical shape; 5 new tests green; test_dashboard.py untouched+green.
