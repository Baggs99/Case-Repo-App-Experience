# B4 — Recommendation surfacing · Phase report

Branch: `bgap/b4-recs` · Worktree: `/Users/thomaskgould/dev/bgap-b4` · DB: `caserepo_bgap_b4`
Merge-base with `feature/backend-gap`: `16cea76` · Branch head: `33a982b`

## Status: DONE

One engine, three mouths delivered per spec §7. All review findings resolved and re-reviewed clean. No migrations (B4 is schema-free). No new dependencies. Full suite green.

## Suite counts

| | Count |
|---|---|
| Baseline (before) | **360 passed** |
| After (full suite) | **376 passed** (360 baseline + 16 new) |

New tests: 11 in `tests/test_recommendations.py` (5 engine + 4 native list + 2 dashboard) + 5 in `tests/test_counterpart_recs.py` (interviewer mouth + IDOR/role). Existing test files untouched and green (byte-compat verified). Command: `DATABASE_URL=postgresql://localhost/caserepo_bgap_b4 <venv> -m pytest tests/ -q`.

## Tasks (commit ranges)

| Task | Deliverable | Commit(s) | Review |
|---|---|---|---|
| Plan | Plan + plan-review nits | `e52ae13`, `be5c476` | plan-review APPROVED |
| 1 | Extend `recommendations()`: `why` + `exclude` + `limit` + canonical item shape (`case_title`→`title`); room.html lockstep | `ee446b6` | clean (both verdicts) |
| 2 | New router `GET /api/v1/recommendations`; main.py registration | `355639d` | clean (both verdicts) |
| 3 | `/api/v1/dashboard` additively gains `dimension_averages` + `recommendations` | `0922bf6` | clean (both verdicts) |
| 4 | `counterpart_recommendations` on join-config (interviewer-only) + pair/status (owner-only) + IDOR/role tests | `3e5ce60` | clean — no IDOR |
| Final fix | Drop candidate mean grade from difficulty-ladder `why` (T9.3) | `33a982b` | re-review CLEAN |

(Interleaved `.superpowers/sdd` ledger commits: `3bbe5a9`, `ccb8499`, `b779490`, `d923dc8`.)

## New / changed endpoints

| Method | Path | Auth | Change |
|---|---|---|---|
| GET | `/api/v1/recommendations?exclude=1,2,3` | `require_auth_api` (session cookie); 401 unauth; 400 non-int exclude | **NEW** — `{recommendations: [<item>]}` |
| GET | `/api/v1/dashboard` | `require_auth_api` | **EXTENDED (additive)** — gains `dimension_averages` (existing web shape) + `recommendations` (`<item>`) |
| GET | `/api/practice/{session_id}/join-config` | `require_auth_api`; non-participant 404 | **EXTENDED (additive)** — gains `counterpart_recommendations` (top 3) **only when `role == "interviewer"`** |
| GET | `/api/practice/pair/status/{token}` | `require_auth_api`; non-owner 404 (via `pairing_repo.status`) | **EXTENDED (additive)** — gains `counterpart_recommendations` (claimant candidate's top 3; `[]` before claim) |

Only one genuinely new endpoint; the other three are additive extensions to existing GETs. All GETs; no CSRF/same-origin needed (matches the existing `/api/v1` GET pattern). No state-changing routes added.

## New migrations

None. B4 is schema-free — no `db/` file touched.

## Interfaces delivered (later phases build against these VERBATIM)

Repository function (B3 debrief seeding + B7 home card consume this directly):

```
webapp/repositories/dashboard.py
recommendations(user_id: int, exclude_case_ids: list[int] = [], limit: int = 5) -> list[dict]
```

Item shape — identical across the repo return and all three mouths:

```
{case_id: int, title: str, case_type: str, difficulty: str, why: str, rule: str}
rule ∈ {"coverage-gap", "difficulty-ladder", "weak-dimension"}
```

- `exclude_case_ids` drops those case ids from every rule (powers "Swap recommendation" — client re-calls with the swapped id excluded). Read-only; the shared-default `[]` is never mutated (the mutable default is the pinned signature — do NOT "fix" it to `None`, it would break the verbatim contract).
- `limit` caps the returned list (rules produce ≤3 items today).
- `why` is human-readable per rule and carries NO numeric grade (T9.3 — see below).
- Counterpart mouths call `recommendations(session["candidate_id"], limit=3)` — the candidate's recs, interviewer-side.

## Security notes

- Parameterized SQL only. `exclude` threaded via `%(exclude)s::int[]` (empty-list default verified working against Postgres); the only f-string interpolation in queries is the pre-existing `_ELIGIBLE` / `_RATING` module constants — zero interpolated values.
- `exclude` validated server-side (`_parse_exclude` → 400 on any non-int token, before the DB call).
- IDOR/role guard on `counterpart_recommendations` audited end-to-end by the security reviewer: a candidate (no key), a non-participant (404 at `_session_or_404`), and a non-owner poller (404 at `pairing_repo.status`, before recs are computed) can never obtain it. Recs are always for `session["candidate_id"]`, never the requester.
- **T9.3 fix (`33a982b`):** the difficulty-ladder `why` originally embedded the candidate's numeric mean grade (`"You're averaging 4.2…"`), which surfaced to the interviewer via `counterpart_recommendations` — contradicting the module's own invariant ("grades never appear in any other-user surface"). Softened to `"You're consistently scoring well on recent cases — ready to step up to {difficulty} {case_type}."` for everyone (same-output contract preserved); the ≥3-session / ≥4.0-mean gate is byte-for-byte unchanged. No `why` now embeds a grade/score/percentage. The weak-dimension `why` reveals the candidate's weakest dimension *name* (a category), which is the intended §7.2 signal, not a grade.

## Notes for the orchestrator (before merging)

1. **Key rename `case_title` → `title`** on `recommendations()` output. This was mandated by the pinned Produces item shape (B3/B7 consume `title`). In-repo consumers were the web `/api/dashboard` (rooms.py, roadmap-designated web-only, not in `/api/v1`) and `webapp/templates/room.html` line 115 (updated to `rec.title` in lockstep — the room page renders identically). No test or JS reads the old key (`rubric.js`'s `case_title` is on an unrelated feedback object). Existing tests untouched and green. **Any external/iOS client reading `case_title` off a recommendations payload must switch to `title`** — but recs were not previously exposed in `/api/v1`, so no shipped native client depends on it.
2. **New iOS-consumable payloads (later waves):** `GET /api/v1/recommendations`; `/api/v1/dashboard` `+dimension_averages +recommendations`; join-config `+counterpart_recommendations` (interviewer only); pair/status `+counterpart_recommendations` (`[]` until claimed).
3. **Shared-file edits are additive:** `api_v1.py` (+2 dashboard keys), `practice.py` (2 handlers + 1 import), `main.py` (router registered just before `api_v1` include — distinct path, no collision). Expected merge-conflict points with sibling phases are `main.py` (include list) and possibly `api_v1.py` dashboard handler.
4. **Client-label note (for the iOS/web team, not an engine issue):** the `why` strings are second-person ("Your weakest dimension is quant"). On the interviewer-facing `counterpart_recommendations` surface, the client should frame these as *the candidate's* ("Recommended for [name]"), since the same engine output feeds both the candidate's own view and the interviewer's.

## DEFERRED

None.

## ESCALATIONS

None. No Fable consults were needed; no BLOCKED states.
