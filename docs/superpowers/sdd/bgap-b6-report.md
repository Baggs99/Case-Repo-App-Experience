# Phase B6 Report — Community (connections, groups, schools standings)

**Status:** DONE
**Branch:** `bgap/b6-community` · **Worktree:** `/Users/thomaskgould/dev/bgap-b6` · **DB:** `caserepo_bgap_b6`
**Branch point (merge-base with `feature/backend-gap`):** `c7bccb8` (includes merged B1 + B4 + B5 + B7)
**Suite:** baseline **512 passed** → final **552 passed / 0 failed** (+40 net-new B6 tests).

Implements the B6 brief §6 and its DESIGN DELTAS: **NO FORUM ANYWHERE** and **NO POPULATION COUNTS EVER** (percentiles only; literal ranks+points only inside a joined group; school-vs-school = avg member percentile + campus city). Plan: `docs/superpowers/plans/2026-07-17-bgap-b6-plan.md`. Ledger: `.superpowers/sdd/b6/progress.md`. Per-task + whole-branch diff/review artifacts: `.superpowers/sdd/b6/diffs/`.

---

## Tasks (each: fresh Opus implementer → diff package → fresh Opus task-reviewer)

| Task | Scope | Commit range | Review |
|---|---|---|---|
| Plan | Plan + plan-review round-1 fixes (C1/C2/I1 + minors) | `e554705`..`65bbb8b` | REQUEST_CHANGES → fixed → clean |
| 1 | Migration 030 (connections) + connections repo | `65bbb8b`..`162e27f` | SPEC+CODE PASS |
| 2 | Connections router + main.py registration | `bcadc28`..`b0b5668` (+ fix `b8dc4fb`) | SPEC PASS / CODE CHANGES→fixed→clean |
| 3 | Migration 031 (groups/group_members/school_leaders/invite_code/campus_city) + groups repo | `c2af3a9` | SPEC+CODE PASS (0 findings) |
| 4 | Migration 033 (leaderboard index) + leaderboards repo (B8 scoping CTEs) | `02091e7` | SPEC+CODE PASS |
| 5 | Groups router (detail+board, admin-gated progress) + registration | `c2b840e` | SPEC+CODE PASS |
| 6 | Leaderboards router (school standing/board/leader rollup) + registration | `3ba5065` | SPEC+CODE PASS |
| Final | Whole-branch review over `c7bccb8..HEAD` | (no fix needed) | **APPROVE** — MINORs only |

**Whole-branch review:** APPROVE. All 6 dimensions PASS (spec coverage, security, cross-task consistency, is_guest seam, migration idempotency re-run twice = exit 0, test quality 40/40). Both design deltas clean (no forum; no population-count leaks). Only MINORs; the one new finding — the `created` bool on the `POST /api/v1/connections/requests` response (the intentional push-gating flag) — is harmless and is documented as shipped in the endpoint + Interfaces tables below, so it is left in place rather than churned.

**Plan review (round 1):** REQUEST_CHANGES — 2 CRITICAL (repo tests never bootstrapped the DB pool; `join_by_code` read role on a second connection → `None`), 1 IMPORTANT (`transfer_admin` to self orphaned the group), 7 MINOR. All fixed in `65bbb8b`; reviewer pre-cleared → no Critical/Important remained.

**Task 2 fix (`b8dc4fb`):** the task-2 review found the connection-request push fired on every idempotent re-request. Fixed by adding a `created` bool to `request()`'s return and gating the push on it. This changed `request()`'s return shape (see Interfaces).

---

## New endpoints (16)

All `/api/v1` routes; auth = `require_auth_api` (401 JSON) on every endpoint. Mutating routes additionally carry `require_same_origin` (`_MUTATING`); read-only GETs correctly omit it. All verified by passing integration tests (TestClient).

### Connections (`webapp/routes/connections.py`)
| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/api/v1/connections` | required | `{connections:[{user_id,display_name,photo_url,bio,free_now,swap_invite_pending}]}` — accepted only; `free_now` via availability join; `swap_invite_pending` always `false` (B3 seam) |
| GET | `/api/v1/connections/requests` | required | `{incoming:[card],outgoing:[card]}` (pending) |
| POST | `/api/v1/connections/requests` | required + same-origin | `{to_user_id}`; 400 self, 404 unknown user; else `{state,created}`; community push to target only on a genuinely-new request |
| POST | `/api/v1/connections/{user_id}/accept` | required + same-origin | only the TARGET accepts; 404 if no pending row; `{state:"accepted"}` |
| POST | `/api/v1/connections/{user_id}/decline` | required + same-origin | 404 if none; 204 |
| DELETE | `/api/v1/connections/{user_id}` | required + same-origin | 204 idempotent (either party) |

### Groups (`webapp/routes/groups.py`)
| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/api/v1/groups` | required | `{groups:[{id,name,school_id,invite_code,role}]}` |
| POST | `/api/v1/groups` | required + same-origin | `{name}` (1–100 chars, 422 blank); creator=admin; `{id,name,school_id,invite_code,role:"admin"}` |
| POST | `/api/v1/groups/join` | required + same-origin | `{invite_code}`; 404 bad code; `{…,already_member}`; community push to admins on genuinely-new join |
| GET | `/api/v1/groups/{id}` | required, **member-only** | 404 non-member (no existence leak); `{group,members[],leaderboard[{user_id,display_name,photo_url,points,rank,streak}]}` |
| POST | `/api/v1/groups/{id}/leave` | required + same-origin | 409 sole-admin-with-others; else 204 (last member deletes the group) |
| POST | `/api/v1/groups/{id}/transfer` | required + same-origin, **admin-only** | `{user_id}`; 403 member, 404 non-member, 400 self-target, 404 target-not-member; 200 |
| GET | `/api/v1/groups/{id}/progress` | required, **admin-only** | 403 member / 404 non-member; `{members:[{user_id,display_name,cases_done,mean_grade,drill_attempts_30d,streak}]}` |

### Leaderboards / school surfaces (`webapp/routes/leaderboards.py`)
| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/api/v1/leaderboards/school` | required | `{school:{school_id,name,campus_city,avg_member_percentile,rank}|null, your_percentile:float|null}` |
| GET | `/api/v1/leaderboards/schools` | required | `{schools:[{school_id,name,campus_city,avg_member_percentile,rank}]}` — school-vs-school, NO counts |
| GET | `/api/v1/leaderboards/schools/{school_id}/groups` | required, **school-leader-only** | 403 if not a `school_leaders` row for that school; `{groups:[{group_id,name,avg_member_percentile}]}` |

Registered additively in `webapp/main.py` (3 `include_router` lines: `connections`, `groups`, `leaderboards`; 3 imports).

## New migrations (030/031/033 — idempotent, each applied + re-applied cleanly; 032 deliberately vacant)

- **030** `db/migrations/030_connections.sql`: `connections(user_id, friend_id, state pending|accepted, requested_at, responded_at, PK(user_id,friend_id))` + distinct-user CHECK + `idx_connections_friend`.
- **031** `db/migrations/031_groups_and_community.sql`: `groups(id, name, school_id NULL→schools, invite_code, created_by→users, created_at)` + partial-unique `idx_groups_invite_code`; `group_members(group_id→groups CASCADE, user_id→users CASCADE, role CHECK('admin','member') DEFAULT 'member', joined_at, PK)` + `idx_group_members_user`; `school_leaders(school_id, user_id, PK)`; **`ALTER TABLE schools ADD COLUMN IF NOT EXISTS campus_city TEXT`** + backfill (New Haven / Ann Arbor / Chicago, guarded `WHERE campus_city IS NULL`). The `school_leaders`, `invite_code`, and `campus_city` additions are beyond the brief's literal "groups + group_members" — required to deliver the invite-code join, school-leader role, and school-vs-school campus city.
- **033** `db/migrations/033_leaderboard_indexes.sql`: partial index `idx_feedback_finalized ON feedback(finalized_at) WHERE finalized_at IS NOT NULL`.

## Interfaces delivered (B8 consumes the leaderboard scoping CTEs — PINNED signatures)

**`webapp/repositories/leaderboards.py`** — B8's `webapp/repositories/leaderboards.py` reuse per the brief. Build against these exactly:
```
POINTS_PER_SESSION: int = 10          # tunable weight
POINTS_PER_DRILL: int = 1             # tunable weight
ACTIVITY_POINTS_SQL: str              # CTE body `activity_points AS (SELECT user_id, points …)`,
                                      #   points = finalized-candidate-sessions*10 + drills*1,
                                      #   BOTH windowed to the last 30 days; only active users.
                                      #   B8 extends the points expression with gauntlet drill scores.
scope_user_ids(scope: str, *, user_id: int, group_id: int | None = None) -> list[int]
                                      #   scope ∈ 'group'|'school'|'global'; membership scoping.
group_leaderboard(group_id: int) -> list[dict]
                                      #   [{user_id, display_name, photo_key, points, rank, streak}] (points desc, rank 1-based)
group_progress(group_id: int) -> list[dict]
                                      #   [{user_id, display_name, cases_done, mean_grade, drill_attempts_30d, streak}]
user_global_percentile(user_id: int) -> float | None      # 0–100, one decimal; None if no 30-day activity
school_standings() -> list[dict]      #   [{school_id, name, campus_city, avg_member_percentile, rank}] (avg desc, rank 1-based)
my_school_standing(user_id: int) -> dict                  # {school: {…}|None, your_percentile: float|None}
school_group_rollup(school_id: int) -> list[dict]         # [{group_id, name, avg_member_percentile}]
```
**Percentile population (consistent across all three functions):** every percentile is `percent_rank()` over ALL 30-day-active users. B8's percentile surfaces should intersect `scope_user_ids(...)` with the `activity_points` population (documented seam — `scope_user_ids('global')` returns all users, not just active ones).

**`webapp/repositories/connections.py`:** `request(requester_id, target_id) -> {"state": "pending"|"accepted", "created": bool}` (raises ValueError on self; `created` True only on a genuinely-new INSERT); `accept(requester_id, accepter_id) -> bool`; `decline(requester_id, decliner_id) -> bool`; `remove(a, b) -> None`; `are_connected(a, b) -> bool`; `list_accepted/list_incoming/list_outgoing(user_id) -> list[dict]`.

**`webapp/repositories/groups.py`:** `create_group(name, creator_id) -> dict`; `join_by_code(code, user_id) -> dict|None`; `leave_group(group_id, user_id) -> 'left'|'deleted'` (raises PermissionError for sole-admin-with-others); `transfer_admin(group_id, from, to) -> bool`; `list_my_groups`, `get_group`, `list_members`, `member_role`, `is_member`, `is_admin`, `admin_ids`, `is_school_leader(user_id, school_id) -> bool`.

**Schema additions consumable downstream:** `schools.campus_city` (backfilled yale/umich/booth); `school_leaders(school_id, user_id)` (admin-assigned, seedable — no self-serve path); `groups.invite_code`.

## Push notification category mapping

Community pushes go through B5's choke point `push_to_user(..., category="community")` (honored end-to-end within this wave per the B5 report). Two senders, both fired via `background.add_task` (never awaited inline), both respecting the `community` notification setting:
- **connection request** → target user (only on a genuinely-new request; not on idempotent re-request or auto-accept).
- **group join** → the group's admins, excluding the joiner (only on a genuinely-new join).

## Security posture (§2, verified per-task + whole-branch)

- Parameterized SQL only across all new code; the only f-strings are trusted column-list constants (`_CARD`, `_MEMBER`) and int/CTE constants (`POINTS_PER_SESSION`, `POINTS_PER_DRILL`, `ACTIVITY_POINTS_SQL`) — no user value is ever interpolated.
- `require_auth_api` on all 16 endpoints; `require_same_origin` on all 10 mutating routes; read-only GETs omit it. Cross-origin 403 tested per router.
- IDOR/role gates (all tested): connections accept/decline only by the target; connection remove only touches the caller's own rows; group detail member-only (404 non-member); group progress + transfer admin-only (403 member, 404 non-member — membership checked before admin so non-members never get 403); transfer self-target 400; school rollup school-leader-only (403, keyed on session `user.id`, no own-school fallback). Identity is always `user.id` from the session.
- No population counts leaked: enforced by the shared `_assert_no_counts` JSON-walker (defined in `tests/test_b6_connections_api.py`, imported by the groups + leaderboards API tests) plus the repo-level no-count test. Internal `COUNT(*)`/`percent_rank()` never surface as payload keys.
- No forum anywhere (no `forum_*` table or router).

## SEAMS for later phases (documented, not guessed)

- **Guests (`users.is_guest`, B2 unmerged — column ABSENT on this branch):** no B6 code references `is_guest`; nothing breaks when B2 adds the column. When B2 merges, add a guest exclusion at these exact points:
  1. `webapp/repositories/leaderboards.py` `ACTIVITY_POINTS_SQL` — add `AND NOT COALESCE(u.is_guest, FALSE)` to the `FROM users u` scan so guests are excluded from leaderboards/percentiles/standings.
  2. `webapp/routes/connections.py` `_user_exists` / connection targeting — optionally reject connection requests to guest rows.
  3. `webapp/repositories/groups.py` join/membership — optionally bar guests from joining groups.
  A `to_regclass`/column-existence guard was considered but not added (the column simply does not exist, so no query references it); the seam is a one-line WHERE addition per point when B2 lands.
- **Swap-invite decoration (`swap_invite_pending`, B3 unmerged — no swap table on this branch):** the connection card field is hard-coded `False` in `webapp/routes/connections.py` (`_card`). When B3 lands a swap-invite table, populate it by LEFT JOINing the connection rows against pending swap invites between the two parties in `connections.list_accepted` (add the column there) and surfacing it in `_card`.

## DEFERRED / known MINORs (none block merge)

- `connections.request()` theoretical opposite-direction race (concurrent `request(a,b)` + `request(b,a)`) → two pending rows instead of an auto-accept; non-corrupting (either side can accept). Harden with `FOR UPDATE` or a normalized `least/greatest` unique constraint if desired.
- `connections` route `_user_exists`→FK-INSERT TOCTOU (500 not 404 if the target is deleted in between); vanishingly unlikely.
- `groups` route `group_detail` TOCTOU (500 if the group is self-deleted between `_require_member` and `get_group`); self-race only.
- `leaderboards`: `my_school_standing` recomputes the full board to pick one row (perf, fine at ≤ a handful of schools); `streak_days` called per-member in a Python loop (N+1, fine for small cohorts).
- `group_progress` mixes all-time `cases_done`/`mean_grade` with 30-day `drill_attempts_30d` — matches the brief verbatim ("cases done, mean grade, drill attempts last 30 d"); the `_30d` suffix self-documents it.
- Pre-existing `webapp/main.py` import block is not strictly alphabetical (`files`/`exhibits`) — untouched by B6; new imports slotted reasonably.

## ESCALATIONS

None. No Fable/deep consults were used or required; no BLOCKED states.

## Notes for the orchestrator before merging

- **Expected merge conflict:** `webapp/main.py` only — 3 additive `include_router` lines + 3 imports near the end of the app factory (same conflict class as B5/B7). All other B6 files are new.
- **Integration DB rebuild** picks up migrations 030/031/033 (032 vacant — a gap, not a collision). All idempotent; the `schools.campus_city` ALTER is additive on B5's `schools` table (023) and re-runs as `UPDATE 0`.
- **B8 consumes** `webapp/repositories/leaderboards.py` (pinned signatures above) — the scoping CTEs (`ACTIVITY_POINTS_SQL`, `scope_user_ids`) are the reuse point; B8 extends the points expression with drill scores (migration 034).
