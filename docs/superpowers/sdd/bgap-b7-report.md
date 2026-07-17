# B7 — Timeline & Home Diagnostic · Phase report

Branch: `bgap/b7-timeline` · Worktree: `/Users/thomaskgould/dev/bgap-b7` · DB: `caserepo_bgap_b7`
Merge-base with `feature/backend-gap`: `edce22c` (includes merged B1 + B4) · Branch head: `3a1396d`

## Status: DONE

New router `webapp/routes/timeline.py` (5 endpoints), `/api/v1/dashboard` extended additively with `diagnostic` + `timeline`, readiness stand-in behind one swap-point (`webapp/readiness.py`, OD-B7-1), daily-guarded deadline-passed push with a B5-settings seam, and the REQUIRED seams note. All 8 tasks implemented TDD-first, each with a fresh Opus implementer + fresh Opus task-reviewer (both verdicts PASS on every task). Whole-branch Opus review returned one Important test-only finding (I-1), fixed and re-verified. No migrations beyond the assigned 026/027; no new dependencies; no forum anywhere.

## Suite counts

| | Count |
|---|---|
| Baseline (before) | **418 passed** |
| After (full suite) | **452 passed** (418 + 34 new) |

Command: `DATABASE_URL=postgresql://localhost/caserepo_bgap_b7 <venv> -m pytest tests/ -q` → `452 passed`. New tests: `test_b7_firms.py` (4), `test_b7_user_firms.py` (8), `test_b7_readiness.py` (4), `test_b7_diagnostic.py` (3), `test_b7_timeline_api.py` (12: 11 timeline + 1 dashboard), `test_b7_deadline_prompt.py` (3). Regression guards run per task (`test_b1_maintenance`, `test_dashboard`, `test_api_v1_sessions`) all stayed green.

## Tasks (commit ranges)

| Task | Deliverable | Commit | Review |
|---|---|---|---|
| Plan | Plan + plan-review C1 fix (seed all 5 rubric dims) | `05c4e9c`, `e7e2c51` | plan-review CHANGES→fixed→clean |
| 1 | Migration 026 (firms + firm_deadlines + seed) + `firms` repo | `c0bfab5` | SPEC+CODE PASS |
| 2 | Migration 027 (user_firms) + `user_firms` repo | `afdd389` | SPEC+CODE PASS |
| 3 | `webapp/readiness.py` swap-point + reweight | `a734e38` | SPEC+CODE PASS |
| 4 | `dashboard.diagnostic()` (additive) | `293d41b` | SPEC+CODE PASS |
| 5 | `timeline_service.py` + `routes/timeline.py` + registration | `9bd3e37` | SPEC+CODE PASS (IDOR verified) |
| 6 | `/api/v1/dashboard` +diagnostic +timeline (additive) | `53f5e82` | SPEC+CODE PASS |
| 7 | Deadline-passed push + daily guard + B5 seam | `e56d529` | SPEC+CODE PASS |
| 8 | Readiness-signal seams note (REQUIRED) | `ce7c3d7` | SPEC+CODE PASS (24/24 citations resolve) |
| Final | I-1: guard `next_deadline` subscript (test-only) | `c63b413` | whole-branch review → CLEAN after fix |

(Interleaved `.superpowers/sdd/b7/` ledger + diff/review artifacts: `682acec`, `8d9b35e`, `49e1639`, `bbbe7c6`, `40d9597`, `0a231b2`, `0b21950`, `724917a`, `3a1396d`.)

## New / changed endpoints

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/api/v1/timeline` | `require_auth_api` (401 unauth) | Timeline-detail: `{as_of, readiness, firms:[…]}` per-firm deadline + readiness_tag + prompt state |
| GET | `/api/v1/timeline/firms` | `require_auth_api` | Add-a-firm catalog: `{firms:[{firm_id,name,slug,tracked,next_deadline}]}` |
| POST | `/api/v1/timeline/firms` | `require_auth_api` + `require_same_origin` | Body `{firm_id}`; track (idempotent); 404 unknown firm |
| DELETE | `/api/v1/timeline/firms/{firm_id}` | `require_auth_api` + `require_same_origin` | Untrack; 204 (per-user no-op if not tracked) |
| POST | `/api/v1/timeline/firms/{firm_id}/result` | `require_auth_api` + `require_same_origin` | Body `{outcome}` ∈ `offer\|no_offer\|waiting\|didnt_interview`; 400 bad outcome; **404 if the user doesn't track the firm (IDOR guard)** |
| GET | `/api/v1/dashboard` | `require_auth_api` | **EXTENDED (additive)** — gains `diagnostic` + `timeline`; all B4/pre-existing keys unchanged |

Post-deadline outcomes (DESIGN DELTA — never a forum): `offer`→status `offer` + record; `no_offer`→status `rejected` + `{reweight:{focus_dimension,suggested_drill_type,extra_cases}}`; `waiting`→status `interviewed` + `snooze_until` (re-ask in a week); `didnt_interview`→row untracked (drops off the line, DV-B7-1).

## New migrations

| # | File | Contents |
|---|---|---|
| 026 | `db/migrations/026_firms_and_deadlines.sql` | `firms(id,name,slug UNIQUE)` + `firm_deadlines(id,firm_id,cycle_label,deadline_date DATE,region,is_estimate)` unique `(firm_id,cycle_label,region)` + index; seeds 12 firms + 12 US 2026 full-time deadlines |
| 027 | `db/migrations/027_user_firms.sql` | `user_firms(user_id,firm_id,added_at,status CHECK IN ('tracking','interviewed','offer','rejected','admitted') DEFAULT 'tracking',result_recorded_at,snooze_until)` PK `(user_id,firm_id)`, both FKs `ON DELETE CASCADE` |

Both idempotent (`IF NOT EXISTS` / `ON CONFLICT DO NOTHING`) — re-applied twice against `caserepo_bgap_b7` with no error, counts stable (firms 12, firm_deadlines 12). `snooze_until` is a DELTA-mandated addition beyond the brief's column list (DV-B7-2). `db/schema.sql` untouched (migrations only).

## Interfaces delivered (B6 / F2 consume these VERBATIM)

**`user_firms.status='admitted'`** (B6 forum-gate source — B6's forum is NIXED, so this is *data only*; nothing in B7 sets or gates on `admitted`). Recorded via a future path; the CHECK permits it.

**Timeline payloads (F2 / UX Home + Timeline-detail):**
```
GET /api/v1/timeline →
  {as_of: str,
   readiness: {label:'on_track'|'needs_work', ready:bool, focus_dimension:str|None,
               recent_case_count:int, threshold:float, min_cases:int},
   firms: [{firm_id:int, name:str, slug:str, status:str, added_at:str,
            deadline: {cycle_label, deadline_date:str, region, is_estimate,
                       days_remaining:int, passed:bool} | None,
            readiness_tag: 'on_track'|'focus'|'early',
            prompt: {show: bool}}]}

GET /api/v1/timeline/firms →
  {firms: [{firm_id:int, name:str, slug:str, tracked:bool, next_deadline: <block>|None}]}

GET /api/v1/dashboard  (additive keys) →
  diagnostic: {cases_done_60d:int, dimensions:[{dimension,avg_score,samples}],
               strengths:[…top2], weaknesses:[…bottom2], focus_dimension:str|None,
               trend: {recent_avg:float|None, previous_avg:float|None,
                       delta:float|None, direction:'up'|'down'|'flat'|None}}
  timeline:  {tracked_count:int,
              next_deadline: {firm_id,name,slug,cycle_label,deadline_date:str,
                              days_remaining:int, readiness_tag:str} | None}
```

**Readiness swap-point (OD-B7-1 — one function every caller goes through):**
```
webapp/readiness.py
  readiness_signal(user_id:int) -> dict            # keys above; STAND-IN, firm-independent
  suggested_drill_type(dimension:str|None) -> str  # ∈ drills._TYPES
  reweight_payload(user_id:int) -> {focus_dimension, suggested_drill_type, extra_cases:[int]}
  READINESS_THRESHOLD=3.0 (/5)  READINESS_MIN_CASES=3  DIAGNOSTIC_WINDOW_DAYS=60
```
Reweight `extra_cases` reuses `dashboard.recommendations(user_id, [], limit=2)` (B4 engine, item key `case_id`). Full seam map: `docs/superpowers/notes/2026-07-17-readiness-signal-seams.md`.

**Repos (later phases may reuse):** `webapp/repositories/firms.py` (`list_firms`, `get_firm`, `all_deadlines`), `webapp/repositories/user_firms.py` (`track`, `untrack`, `is_tracked`, `get`, `list_tracked`, `record_result`, `mark_waiting`, `firms_needing_prompt`, `mark_prompted`), `webapp/timeline_service.py` (`timeline_view`, `firm_catalog`, `next_deadline_summary`).

## Notes for the orchestrator (before merging)

1. **Shared-file edits are additive:** `webapp/main.py` (+2: import + include before `api_v1`), `webapp/routes/api_v1.py` (+1 import, +2 dashboard keys), `webapp/maintenance.py` (adds `sweep_deadline_prompts` + daily guard + B5 seam; `run_maintenance_pass(settings, *, as_of=None)` keeps the existing positional call working and the exact expired→missed→aborted→starting_soon order; `maintenance_loop` byte-identical). Expected merge-conflict points with siblings: `main.py` include list, `api_v1.py` dashboard handler, `maintenance.py` return dict.
2. **B5 notification-settings seam (B5 unmerged on this branch):** `webapp/maintenance.py:_deadline_notifications_allowed` checks `to_regclass('notification_settings')` and **fails open** (pushes) when the table is absent or on any error; when B5 is merged it honors the user's `session_reminders` flag. **Category mapping assumption:** deadline-prompt → `session_reminders` (the closest B5 category). If B5 ships a dedicated timeline/deadline category, update that one line. B5's own push choke-point will double-guard post-merge (harmless — same result).
3. **`GET /api/v1/dashboard` new iOS-consumable keys:** `diagnostic`, `timeline` (in addition to B4's `dimension_averages`, `recommendations`). New native surfaces: the 5 `/api/v1/timeline*` endpoints.
4. **Integration DB:** the merge-integration run must apply migrations 026 + 027 (and, for the deadline-push tests, seed users a/b/c). Migrations are idempotent.

## FLAG FOR THOMAS — seed deadline dates are estimates

All 12 `firm_deadlines` rows are `is_estimate=TRUE`: a **curated 2026–27 US full-time stand-in**, no authoritative source consulted (no web-search per the brief). MBB/Roland Berger anchor the design persona (McKinsey 2026-09-12, BCG 2026-09-30, Bain 2026-10-08, Roland Berger 2026-07-02 = an intentional *passed* deadline for the prompt fixture). **Replace with real cycle dates before launch** (edit migration 026's seed or update rows directly). Clients can read `is_estimate` to badge unverified dates.

## Known issues (non-blocking — final-review Minors, none affect correctness)

- **M-1:** `firm_deadlines_unique(firm_id,cycle_label,region)` is NULLS-DISTINCT; a *future* `region=NULL` seed row would re-insert on re-apply. Untriggered (all seeds `region='US'`). If NULL-region rows are ever added, use `NULLS NOT DISTINCT` (PG15+) or `COALESCE(region,'')`.
- **M-2:** `firms ON CONFLICT (slug) DO NOTHING` advances `firms_id_seq` on no-op re-apply (harmless SERIAL gap).
- **M-3:** `reweight_payload` derives `dimension_averages` twice (once via `readiness_signal`, once inside `recommendations`) — perf only, on the rare `no_offer` path.
- **M-4:** `diagnostic` strengths/weaknesses overlap when a user has <4 rubric dimensions (acceptable snapshot; the generic template has 5, so untriggered).
- **M-5:** test coverage gap — no explicit cross-origin-403 test on mutating routes; `GET /timeline/firms` 401 not directly asserted. Protections are present in code (`_MUTATING` on all 3 state-changers, `require_auth_api` on all 5).
- **M-6:** `test_daily_guard_runs_once_per_day` doesn't isolate the guard from the snooze throttle (1-then-0 holds even without the guard). The guard is a documented perf optimization; double-push prevention (the correctness property) is separately proven by the snooze throttle.

## DEFERRED

None.

## ESCALATIONS

None. No Fable consults were needed; no BLOCKED states.
