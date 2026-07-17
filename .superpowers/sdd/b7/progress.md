# B7 — Timeline & home diagnostic · ledger

Branch: `bgap/b7-timeline` · Worktree: `/Users/thomaskgould/dev/bgap-b7`
DB: `caserepo_bgap_b7` · Interpreter: `/Users/thomaskgould/dev/Case-Repo-App-Experience/.venv/bin/python`

## Bootstrap
- DB created; schema + migrations 002–021 applied; `.env` DATABASE_URL → caserepo_bgap_b7 (gitignored, verified).
- Seeded a/b/c@yale.edu + Dev Dummy Case via scripts/seed_caseroom_dev.py.
- **Baseline: 418 passed** (green) — evidence: `DATABASE_URL=…/caserepo_bgap_b7 $PY -m pytest tests/ -q` → `418 passed, 422 warnings in 5.36s`.
- Finish line = 418 + N new tests.

## Plan
- Written: docs/superpowers/plans/2026-07-17-bgap-b7-plan.md (8 tasks). Migrations 026/027 applied to DB (idempotent, re-applied twice). Deviations DV-B7-1..5 recorded in plan.

## Plan review
- Opus reviewer: VERDICT CHANGES REQUIRED → C1 (Task3/Task4 fixtures seeded only 3 of 5 generic-template dims → insight/synthesis default to 0.0 and steal "weakest" from quant). Fixed: seed all 5 dims (mirror test_dashboard). Also applied M1 (relative snooze date) + M2 (mutating-route auth test). Baseline (M3) already verified = 418.

## Tasks
- Task 1: complete (commits e7e2c51..c0bfab5, review clean SPEC+CODE PASS). Migration 026 + firms repo. Deviation: implementer added TestClient(app) pool-init scaffolding to test setUpClass (plan omitted it) — correct+minimal. Suite 418→422.
  - Minors for final triage: (a) firm_deadlines unique (firm_id,cycle_label,region) is NULLS-DISTINCT → a future region=NULL seed row would re-insert on re-apply (not triggered; all seeds region='US'); (b) ON CONFLICT advances firms_id_seq on no-op re-apply (harmless).
  - LESSON: Tasks 2/3/4 tests also call pool-backed repos in setUpClass without TestClient — implementers MUST add the same scaffolding (reference tests/test_b7_firms.py).

(executing task-by-task)
- Task 2: complete (commits 682acec..afdd389, review clean SPEC+CODE PASS). Migration 027 + user_firms repo (9 fns). Pool-init scaffolding added to test. Suite 422→430.
- Task 3: complete (commits 8d9b35e..a734e38, review clean SPEC+CODE PASS). webapp/readiness.py swap-point + reweight. C1 fixture fix held (quant strictly weakest). Suite 430→434.
  - Minor for final triage: reweight_payload calls dimension_averages twice (once via readiness_signal, once inside recommendations) — low-freq path, plan-verbatim.
- Task 4: complete (commits 49e1639..293d41b, review clean SPEC+CODE PASS). dashboard.diagnostic() additive (+59/-0), regression guard green. Suite 434→437.
  - Minor for final triage: strengths/weaknesses overlap when <4 dims (acceptable snapshot; fixture seeds 5 so untriggered).
- Task 5: complete (commits bbbe7c6..9bd3e37, review clean SPEC+CODE PASS). timeline_service + router + main.py registration (additive +2). IDOR exhaustively verified: no hole. Suite 437→448.
  - Minors for final triage: no explicit cross-origin 403 test on mutating routes; GET /timeline/firms 401 not directly asserted (mechanism proven elsewhere).
- Task 6: complete (commits 40d9597..53f5e82, review clean SPEC+CODE PASS). /api/v1/dashboard additive +diagnostic +timeline (+6/-0 in api_v1.py). Suite 448→449.
  - Minor for final triage: TestDashboardTimelineKeys asserts next_deadline.slug=='mckinsey' via real clock — time-bomb after 2026-09-12 (seed dates are is_estimate stand-ins). Consider guarding next_deadline-None at final review; flag to Thomas.
- Task 7: complete (commits 0a231b2..e56d529, review clean SPEC+CODE PASS). maintenance.py: sweep_deadline_prompts + daily guard + B5 seam (fail-open). b1-maintenance regression green. Suite 449→452.
  - Minor for final triage: test_daily_guard_runs_once_per_day doesn't isolate guard from snooze throttle (1-then-0 holds even without guard). Could clear snooze between r1/r2. Low value.
- Task 8: complete (commits 0b21950..ce7c3d7, review clean SPEC+CODE PASS). readiness-signal-seams.md — all 24 file:symbol citations resolve, factually accurate. No new tests (doc).

## Full suite (post all tasks)
