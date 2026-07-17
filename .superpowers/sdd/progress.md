# B4 — Recommendation surfacing · SDD ledger

Branch: bgap/b4-recs · DB: caserepo_bgap_b4 · Baseline: 360 passed (green)

## Ledger
- Env bootstrap: DB created, schema+18 migrations applied, seeded a/b/c@yale.edu, baseline 360 passed.
- Plan: docs/superpowers/plans/2026-07-17-bgap-b4-plan.md (4 tasks). Plan-review APPROVED (be5c476 applied nits).
- Task 1: complete (commits be5c476..ee446b6, review clean). recommendations() extended: why/exclude/limit/canonical shape; 5 new tests green; test_dashboard.py untouched+green.
- Task 2: complete (commit 355639d, review clean). GET /api/v1/recommendations router + main.py registration; 9 tests green in test_recommendations.py.
- Task 3: complete (commit 0922bf6, review clean). /api/v1/dashboard additively gains dimension_averages + recommendations; 11 tests in test_recommendations.py + 8 in test_api_v1_sessions.py green.
- Task 4: complete (commit 3e5ce60, review clean — no IDOR). counterpart_recommendations on join-config (interviewer-only) + pair/status (owner-only); 3 IDOR/role tests pass; 5 new tests. NOTE: implementer fixed a plan-fixture bug (joinable-session INSERT needed NOT NULL rubric_template_id) via get_default_rubric_template_id — sound, security-reviewer confirmed.

- Full suite after Task 4: 376 passed (360 baseline + 16 new).
- Final whole-branch review (16cea76..d923dc8): APPROVED FOR MERGE; 1 IMPORTANT (privacy: difficulty-ladder why leaked candidate mean grade to interviewer via counterpart_recommendations — T9.3). Fixed: commit 33a982b (softened why, gate untouched). Re-review CLEAN. Full suite 376 green.

## Minor findings (dispositioned)
- M1 (Task 2): _parse_exclude accepts negative/underscore/unicode int forms as harmless read-only no-ops (int() semantics). SHIP as-is (reviewer decision) — not a spec violation.
- MINOR (final): weak-dimension/weakest why is second-person ("Your weakest dimension is quant") — client-label concern for the iOS/web team framing counterpart recs as the candidate's; no engine change (same-output contract). weakest.replace('_',' ') only humanizes underscores — harmless for current dimension names.
