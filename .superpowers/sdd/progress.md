# B4 — Recommendation surfacing · SDD ledger

Branch: bgap/b4-recs · DB: caserepo_bgap_b4 · Baseline: 360 passed (green)

## Ledger
- Env bootstrap: DB created, schema+18 migrations applied, seeded a/b/c@yale.edu, baseline 360 passed.
- Plan: docs/superpowers/plans/2026-07-17-bgap-b4-plan.md (4 tasks). Plan-review APPROVED (be5c476 applied nits).
- Task 1: complete (commits be5c476..ee446b6, review clean). recommendations() extended: why/exclude/limit/canonical shape; 5 new tests green; test_dashboard.py untouched+green.
- Task 2: complete (commit 355639d, review clean). GET /api/v1/recommendations router + main.py registration; 9 tests green in test_recommendations.py.
- Task 3: complete (commit 0922bf6, review clean). /api/v1/dashboard additively gains dimension_averages + recommendations; 11 tests in test_recommendations.py + 8 in test_api_v1_sessions.py green.

## Minor findings (triage at final review)
- M1 (Task 2): _parse_exclude accepts negative/underscore/unicode int forms as harmless read-only no-ops (int() semantics). Not a spec violation; optional hardening only.
