# Phase B8 Report — Drills aggregation & gauntlet seams

**Status:** DONE
**Branch:** `bgap/b8-drills-agg` · **Worktree:** `/Users/thomaskgould/dev/bgap-b8` · **DB:** `caserepo_bgap_b8`
**Branch point (merge-base with `feature/backend-gap`):** `8da1114` (includes merged B1+B2+B4+B5+B6+B7) · **Head:** `01bf224`
**Suite:** baseline **585 passed** → final **624 passed / 0 failed** (+39 net-new B8 tests).

Implements the B8 brief §6 under **OD-B8-1 (SEAMS ONLY)** and the **DESIGN DELTA §0.2** (percentile-first; NO population counts; literal rank+points ONLY inside a joined group). A global date-seeded 6-slot gauntlet (3 existing generator types × 2, every payload `"provisional": true`), server-scored with one submission per user per day, percentile-first results/boards/trends, reusing B6's `webapp/repositories/leaderboards.py` scoping CTEs (extended with gauntlet score). The REQUIRED bank-integration contract doc is delivered and reviewed like code. Plan: `docs/superpowers/plans/2026-07-17-bgap-b8-plan.md`. Ledger: `.superpowers/sdd/b8/progress.md`. Per-task + whole-branch diff/review artifacts: `.superpowers/sdd/b8/diffs/`.

---

## Tasks (each: fresh Opus implementer → diff package → fresh Opus task-reviewer)

| Task | Scope | Commit(s) | Review |
|---|---|---|---|
| Plan | Plan + plan-review fixes (M2/M3/M4) | `1a50f3f`, `35b0882` | **APPROVE** (0 Crit/0 Imp, 6 Minor) |
| 1 | Migrations 034 (score/duration_ms/set_key) + 035 (rank indexes) | `9d0f274` | SPEC PASS / CODE PASS |
| 2 | `drills.py` gauntlet primitives: `daily_set`/`public_drill`/`score_slot` (pure, append-only) | `f52c5f7` | SPEC PASS / CODE PASS |
| 3 | `repositories/gauntlet.py`: scored submission (advisory-locked one-per-day), daily percentile, trends | `6e45231` | SPEC PASS / CODE PASS |
| 4 | `repositories/leaderboards.py` `ACTIVITY_POINTS_SQL` + `POINTS_PER_GAUNTLET_POINT` (B6-safe extension) | `e0fc323` | SPEC PASS / CODE PASS |
| 5 | `webapp/gauntlet.py` service: `submit`/`results_for`/`trends` (percentile-first composition) | `8e8e506` | SPEC PASS / CODE PASS |
| 6 | `routes/drills.py` 4 endpoints + `main.py` registration | `403b255` | SPEC PASS / CODE PASS |
| 7 | REQUIRED `docs/superpowers/notes/2026-07-17-drills-bank-integration.md` + structural guard | `b426cae` | SPEC PASS / CODE PASS |
| Final | Whole-branch review over `8da1114..HEAD` | `9fdf199` (diff) | **APPROVE** (0 Crit/0 Imp, 7 Minor) |
| Fixes | One fix batch for the 7 Minors → re-review | `01bf224` | **CLEAN** |

**Plan review (round 1):** APPROVE. 0 Critical / 0 Important; 6 Minor (M1 school-vs-global percentile label, M2 flaky `-1` sentinel test, M3 negative-target `tolerance_factor`, M4 group-comment, M5 cold-start 0th-percentile UX, M6 private-symbol import). Applied M2/M3/M4 before execution; M1/M5/M6 accepted as documented.

**Whole-branch review:** APPROVE, 0 Critical / 0 Important, 7 Minor. All 7 fixed in `01bf224` (one fix agent), re-reviewed **CLEAN** (42/42 targeted green, no scope creep — `leaderboards.py` untouched by the fix). Notable fix: the guest-exclusion percentile test was made **discriminating** (previously passed even if the guest filter were removed).

---

## New endpoints (4) — router `webapp/routes/drills.py` (prefix `/api/v1`, registered additively in `webapp/main.py` as `drills as drills_routes`)

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/api/v1/drills/gauntlet` | `require_auth_api` | Today's global date-seeded set (SAME for everyone), 6 slots, answers redacted (`public_drill`), `provisional:true`; carries `streak`, `submitted`, and `result` (the results payload) once submitted |
| POST | `/api/v1/drills/gauntlet/attempts` | `require_auth_api` + `require_same_origin` | Body `{answers:[{slot,value?,choice_index?,duration_ms?}] × 6}`; server re-scores vs the regenerated set; one submission/user/day → **409** repeat (`{error:"already_submitted",set_key}`); **422** malformed; returns the results payload |
| GET | `/api/v1/drills/boards?scope=group\|school\|global\|schools` | `require_auth_api` | `group` (opt `group_id`, **is_member IDOR gate → 403**) = literal ranks+points+streak (joined-group only); `school` = school card + your_percentile; `global` = your_percentile; `schools` = school-vs-school avg-percentile + campus city. NO counts anywhere |
| GET | `/api/v1/drills/trends` | `require_auth_api` | `{daily:[{date,score}] (60d), by_type:[{drill_type,attempts,correct,accuracy}], weakest:drill_type\|null}` |

Existing per-user endpoints `/api/v1/drills/daily`, `/api/v1/drills/templates`, `POST /api/v1/drills/attempts` are **untouched** (iOS P4 unaffected); `drills.py`'s `daily_drill`/`generate_drill`/`bank_document` are byte-identical.

## New migrations (034/035 — idempotent, applied + re-applied cleanly)

- **034** `db/migrations/034_drill_scores.sql`: `drill_attempts` gains `score REAL`, `duration_ms INTEGER`, `set_key TEXT` (all NULL; existing P4 rows unaffected). `ADD COLUMN IF NOT EXISTS`.
- **035** `db/migrations/035_gauntlet_rank_indexes.sql`: partial indexes `idx_drill_attempts_setkey (set_key,user_id) WHERE set_key IS NOT NULL` and `idx_drill_attempts_user_setkey (user_id,set_key) WHERE set_key IS NOT NULL`. `CREATE INDEX IF NOT EXISTS`.

Migration **019 is RESERVED for the drills-bank track and was NOT touched** (B8 used 034/035 only).

## Interfaces delivered (F7 frontend consumes these payloads — PINNED)

**`GET /api/v1/drills/gauntlet` →**
```
{date:str, set_key:str, provisional:true,
 slots:[{slot:int, drill_type:str, key:str, prompt:str, numbers:[str], choices?:[str]}]  # NO answer/explanation
 streak:int, submitted:bool, result: <results payload>|null}
```
**`POST /api/v1/drills/gauntlet/attempts` → results payload (also embedded as `gauntlet.result`):**
```
{score:float, slots_correct:int, slots:int, points_awarded:int,
 daily_percentile:float|null,                      # percent_rank among today's submitters, guests excluded
 group: {group_id:int, name:str, rank:int, points:int, points_behind_next:int|null} | null,  # joined-group ONLY (literal rank+points)
 school_percentile:float|null,                     # == B6 my_school_standing.your_percentile (global percentile shown on the school card)
 vs_peers_delta:int|null,                          # == group.points_behind_next ("8 behind №5")
 weak_section: {drill_type:str, label:str} | null, # drives "Practice market sizing"
 streak:int, set_key:str, provisional:true}
```
**`GET /api/v1/drills/boards?scope=…` →**
```
group   → {scope:"group", group:{id,name}|null, entries:[{user_id,display_name,photo_key,points,rank,streak}]}
school  → {scope:"school", school:{school_id,name,campus_city,avg_member_percentile,rank}|null, your_percentile:float|null}
global  → {scope:"global", your_percentile:float|null}
schools → {scope:"schools", schools:[{school_id,name,campus_city,avg_member_percentile,rank}]}
```
**`GET /api/v1/drills/trends` →** `{daily:[{date:str,score:float}], by_type:[{drill_type,attempts,correct,accuracy}], weakest:str|null}`

**Repos/services (later phases may reuse):**
```
webapp/drills.py                 GAUNTLET_SLOTS=6; daily_set(on:date|None)->list[dict] (full, incl answer, +slot);
                                 public_drill(wire)->dict (redacted); score_slot(wire,*,value,choice_index)->bool
webapp/repositories/gauntlet.py  AlreadySubmitted; record_submission(user_id,set_key,slots); has_submitted;
                                 submission_summary->{score,slots_correct,slots}|None; daily_percentile->float|None;
                                 daily_scores(user_id,days=60); per_type_accuracy; weakest_type
webapp/gauntlet.py               InvalidSubmission; GAUNTLET_TYPE_LABELS; submit(user_id,answers,on=None)->results;
                                 results_for(user_id,set_key)->dict|None; trends(user_id)->dict
webapp/repositories/leaderboards.py  POINTS_PER_GAUNTLET_POINT=2 (gauntlet run-score → activity points)
```

## Leaderboard extension (the one shared-file edit — provably B6-safe)

`ACTIVITY_POINTS_SQL` now = `sessions*10 + practice_drills*1 + SUM(gauntlet score)*2`, where the drill-count subquery filters `set_key IS NULL` (practice only) and a new subquery sums gauntlet score over `set_key IS NOT NULL`; the population WHERE gains `OR gauntlet_score>0`; guest exclusion `AND NOT COALESCE(u.is_guest, FALSE)` preserved. **For all B6/seed data (zero `set_key` rows) every value is byte-identical** — proven logically and by running all B6 leaderboard/group tests green alongside the new tests (40/40 cross-cut). This is the sanctioned reuse point ("your gauntlet counts"); B6 boards/standings now reflect gauntlet performance with no code change on B6's side.

## Security posture (§2, verified per-task + whole-branch)

- **Parameterized SQL only.** The sole f-string in any query is the trusted `ACTIVITY_POINTS_SQL` CTE (only int `POINTS_*` constants baked in); every gauntlet-repo query uses `%(name)s`/`%s`, including `pg_advisory_xact_lock(%s,%s)`. Zero user-value interpolation.
- **Auth on all 4 endpoints** (`require_auth_api`, which also 403s guests); `require_same_origin` on the mutating POST only (cross-origin POST → 403, tested); read GETs omit it.
- **Guests excluded from every ranking population** — `daily_percentile` and `ACTIVITY_POINTS_SQL` both carry `NOT COALESCE(u.is_guest, FALSE)`; a discriminating repo test proves the daily-percentile exclusion.
- **Answer redaction:** the gauntlet wire never carries `answer`/`explanation` (whitelist `public_drill`); the server re-scores on submit against the regenerated set, so the leaderboard can't be gamed from the payload.
- **IDOR:** `scope=group` gates on `groups_repo.is_member(gid, user.id)` (checked before any group data; identity always the session `user.id`) → 403 non-member, tested.
- **One-per-day race safety:** `pg_advisory_xact_lock(_LOCK_NS, user_id)` + in-transaction existence re-check + `executemany`, all in one `autocommit=False` transaction → concurrent double-submit blocks then raises `AlreadySubmitted`.
- **No population counts leaked:** every new payload passes B6's `_assert_no_counts` (gauntlet GET, results, all 4 board scopes, trends — including populated-payload variants). No key contains `count/total/num_/of_n/n_members/n_players/population`.

## Assumptions (recorded instead of asking)

- `school_percentile` in the results payload = `user_global_percentile` — the same value B6's `my_school_standing.your_percentile` surfaces on the school card (the persona's "88TH" standing). A distinct within-school population is a future refinement; the brief only says "school percentile." (Plan-review M1; owner nod deferred to the orchestrator.)
- The results/`_group_block` "primary group" = the user's most-recently-created joined group (`list_my_groups` orders `created_at DESC`). Deterministic in practice — the persona has one group.
- Trends + daily percentile are scoped to gauntlet rows (`set_key IS NOT NULL`); the unscored per-user practice drills (`/drills/attempts`) have no score and stay out of the scored trend.
- **Scoring is intentionally simple** (per-slot 1.0/0.0 → run score = count correct; `POINTS_PER_GAUNTLET_POINT=2`). §0.2's unified `f(accuracy, time, complexity)` score is explicitly owner-flagged future work; `duration_ms` is captured now so it's available when that lands.

## Accepted (documented, non-blocking) knowns

- A gauntlet-**only** user who scores exactly 0 (all 6 wrong) is not added to `activity_points` (0 points either way; their streak still counts via `drill_attempts`). `daily_percentile` uses its own CTE and correctly includes them.
- `activity_points.points` widens to `double precision` (the gauntlet term); order-invariant and `group_leaderboard` casts `int(points)` — no float ever serializes.
- Migration index test asserts index **name** (shape/predicate verified live).

## DEFERRED

None.

## ESCALATIONS

None. No Fable/`deep` consults used or required; no BLOCKED states.

## Notes for the orchestrator (before merging)

1. **Expected merge conflicts (both additive, same class as prior waves):**
   - `webapp/main.py` — +1 import (`from webapp.routes import drills as drills_routes`, aliased to avoid colliding with the `webapp.drills` module) + 1 `include_router` after `api_v1`.
   - `webapp/repositories/leaderboards.py` — the `ACTIVITY_POINTS_SQL` body + `POINTS_PER_GAUNTLET_POINT` constant (B6 also owns this file; the edit is additive and B6-number-preserving — see the leaderboard-extension section). If another wave-4 phase touched this file, reconcile by keeping BOTH the gauntlet `ga` subquery and any other additions.
   All other B8 files are new.
2. **Integration DB rebuild** picks up migrations 034/035 (idempotent; re-run twice = exit 0). No `db/schema.sql` edit.
3. **New iOS/native surfaces:** the 4 `/api/v1/drills/*` endpoints above. Existing `/drills/daily|templates|attempts` unchanged.
4. **"Done when" satisfied:** two users completing the same daily set each get score, daily percentile (100.0 / 0.0), and group rank+points from api_v1 (`tests/test_b8_drills_api.py::test_two_users_same_set_get_percentile` + `test_group_board_populated_via_route`).
