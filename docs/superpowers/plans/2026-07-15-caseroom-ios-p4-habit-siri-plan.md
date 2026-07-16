# CaseRoom iOS App — Phase 4 (Habit + Siri Layer) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship P4 of the CaseRoom iPhone app — the habit layer: a **drill of the day** (on-device Foundation Models on AI hardware, server template bank on everything else — same UI), **home/lock-screen widgets** (streak + next session + free-now), **App Intents + App Entities** (Start Drill / Next Session / I'm Free Now via Siri, Shortcuts, Action button, interactive widgets), and a **"free now" availability toggle with instant-match push**.

**Architecture:** Deterministic truth, generative dressing. A shared **template bank** (server-owned JSON: mental-math op specs, market-sizing scenarios with reference answers, framework-recall Q&A) is interpreted by seeded deterministic generators on BOTH the server (`webapp/drills.py`, feeds `GET /api/v1/drills/daily` for non-AI hardware) and the device (Swift interpreter, feeds the Foundation-Models engine). **The 3B on-device model never decides an answer** — it only rewrites the stem for variety, and its output is validated (must contain the drill's numbers verbatim) with a plain-template fallback. Attempts POST to a new `drill_attempts` table, which powers a daily `streak_days` stat added to `/api/v1/dashboard`. Widgets read a `WidgetSnapshot` JSON the app writes into a new **App Group** container (no widget networking) — the same App Group also hosts a **shared cookie store** so interactive-widget intents (which run in the widget extension's process) can call the API authenticated. "Free now" is an `availability` row with **lazy expiry** (`free_until > now()` filters everywhere — no sweep loop), and toggling on pushes `kind="free_now"` to the other currently-free users, deep-linking into a native propose-now sheet.

**Tech Stack:** FastAPI + Postgres (existing) · SwiftUI, iOS 26 SDK / target iOS 17 · `FoundationModels` (@Generable — **first `@available`-gated code in the repo**) · `WidgetKit` (`StaticConfiguration` + `TimelineProvider` — new; the extension currently holds only the Live Activity) · `AppIntents` · XCTest / pytest. **Zero new SPM or pip dependencies** — everything is a system framework or stdlib.

---

## Defaults taken (owner may veto — none gate execution)

- **DF-1 · Daily streak definition:** a UTC calendar day counts toward `streak_days` if the user completed ≥1 drill **or** has a `finalized` session that day; the streak survives through the current day (yesterday-anchored). The existing weekly `streak_weeks` stays untouched.
- **DF-2 · Instant-match audience:** toggling free pushes to **all other currently-free users** (school-scale is a handful of classmates). Push fires only on a fresh toggle-on, not on window extension.
- **DF-3 · Free window default:** 60 minutes (client sends `minutes`, server clamps 5–240).
- **DF-4 · Template bank is v1 + a seam:** ~30 curated templates in-repo. The Desktop drills-DB track later replaces the bank behind the same `/api/v1/drills/*` contract; its migration renumbers to 019+ (P4 takes 017/018 — verified free on disk, the reservation was only a PROGRESS note).
- **DF-5 · Dates in UTC** for daily seeds and streaks (matches the existing `date_trunc('week', ...)` UTC convention).

---

## Global Constraints

- Branch: create **`feature/ios-p4`** from `feature/caseroom`. **Never push. Never touch main.** Thomas merges.
- Parameterized SQL only (`%s` / `%(name)s`). New mutating endpoints: `Depends(require_auth_api)` + `dependencies=_MUTATING`; GETs auth-only. Errors: `HTTPException(status, detail=...)`; non-participant resources 404 not 403 (DV-11 convention).
- Push payloads use `data={"kind": <str>, ...}` (NOT `type`). New kind: `"free_now"` (+ `user_id`, `name`). Pushes no-op when `push_enabled()` is false (dev).
- Migrations: `017_drill_attempts.sql`, `018_availability.sql` — idempotent (`IF NOT EXISTS`), `TEXT + CHECK` not enums, `timestamptz DEFAULT now()`, applied with `python main.py apply-sql-migration db/migrations/NNN_*.sql`. Style exemplar: 016.
- iOS: deployment target **17.0**, iOS 26 SDK, simulator `iPhone 17`. Every FoundationModels touch: `@available(iOS 26.0, *)` on types, `if #available(iOS 26.0, *)` at call sites — there is NO existing version-gating in the repo; do not lower the floor.
- **FM never owns correctness.** Answers come from the deterministic interpreter; FM dressing is validated (all numeric literals of the drill must appear verbatim in the rewritten stem) else plain render.
- App Group id: **`group.studio.ogee.caseroom`** — new `entitlements:` blocks in `project.yml` for BOTH `CaseRoom` and `CaseRoomWidgets`. Guard every container access (`containerURL(...)` can be nil in unprovisioned builds) with a `.shared`-storage fallback.
- New Info.plist keys go under `project.yml` target `info.properties` (NEVER `INFOPLIST_KEY_*`), then `xcodegen generate`. Run all `xcodebuild` in the FOREGROUND.
- Backend tests: `unittest` style, gate DB tests `@unittest.skipUnless(_READY, ...)` importing `_DB_URL/_READY/_HTTPX` from `tests.test_ws_integration`; mint session cookies directly (`create_session` + `SESSION_COOKIE_NAME` from `webapp.auth.sessions` — TestClient can't use /login). Resolve seeded user ids by email at runtime, never hardcode. Push assertions: monkeypatch `events.send_push` + `events.load_settings` (the `test_push_events.py` pattern).
- iOS tests: XCTest, stub network via `StubURLProtocol` (`APIClientTests.swift:15`, `sessionConfiguration`), VM tests via injected protocol stubs, fixtures in `CaseRoomTests/Fixtures/` (folder resource).
- Commit at the end of every task (imperative message). Update `PROGRESS.md` only at phase boundaries (orchestrator owns it).
- **Scope boundary:** No fall-wave iOS 27 features (Spotlight semantic index, Siri AI Q&A, PCC). No drills-DB population (Desktop track). No video/session-layer changes. `AppIntentsTesting` is iOS 27 beta — manual Shortcuts verification instead.

### Verified existing interfaces (recon 2026-07-15 — authoritative)

**Backend** — `webapp/routes/api_v1.py`: `router = APIRouter(prefix="/api/v1")` (`:35`), `_MUTATING = [Depends(require_same_origin)]` (`:37`), auth via `require_auth_api` → `User` (`user.id`, `user.email`). Body-model pattern: `LiveActivityBody` (`:50-53`). `GET /api/v1/dashboard` (`:262-274`) returns `{"sessions_finalized": int, "streak_weeks": int, "next_session": {...}|null}` from `sessions_repo.public_stats(user.id)` (`practice_sessions.py:194-225`) + `list_upcoming_for_user` + `_upcoming_session_json` (`api_v1.py:194-207`: `{id, role, other_user, case_title, scheduled_at, state, ended_at:null, grade:null}`). Registered `app.include_router(api_v1_routes.router)` (`main.py:150`).
**Push** — `push_to_user(user_id, *, title, body, data=None, interruption_level=None)` (`events.py:32`, never raises, deletes 410 tokens); `notify(...)` fire-and-forget (`events.py:67`); `push_enabled(settings)` (`events.py:26`). Trigger idiom: `background.add_task(push_to_user, uid, title=..., body=..., data={"kind": ..., ...})` (`proposals.py:66-71,93-98`). Existing kinds: proposal/accepted/knock/feedback/starting_soon.
**Data layer** — `with get_pool().connection() as conn: with conn.cursor(row_factory=dict_row) as cur:`; `FOR UPDATE` for transitions; commit on clean exit. `create_proposal(*, from_user_id, to_user_id, case_id, from_role, message, proposed_times) -> dict` (`proposals.py:41`); proposal HTTP wrappers live at **`POST /api/proposals`** etc. (NOT /api/v1 — native-compatible, `require_same_origin` passes with no Origin). `users` has `id/email/display_name`; `practice_sessions` has `state/ended_at/interviewer_id/candidate_id` with per-user indexes. Settings: add fields to the frozen `Settings` dataclass + `load_settings()` (`settings.py`) — P4 needs no new env keys.
**iOS** — `actor APIClient: SessionService, PairService` (`APIClient.swift:67`), `static let shared`, `init(session: URLSession = .shared)` (`:77`), base URL from Info.plist `API_BASE_URL` (`:78-83`), private generic `send<Response>` / `send<Body,Response>` / `sendNoContent` (`:361-390`), snake_case + custom two-formatter ISO8601 date strategy (`:88-127`). Public methods incl. `dashboard() -> DashboardStats` (`:205`), `registerDevice(token:)` (`:211`), `proposals()/acceptProposal/declineProposal` (`:178-190`) — **no createProposal exists**. Models (`Networking/Models.swift`): `DashboardStats` (`:72`: `sessionsFinalized`, `streakWeeks`, `nextSession: SessionSummary?`), `SessionSummary` (`:61`: `id, role, otherUser, caseTitle, scheduledAt?, state?, endedAt?, grade?`), `CaseSummary/CaseDetail/Proposal/User`.
**App shell** — `CaseRoomApp` (`App/CaseRoomApp.swift:13`) injects `SessionStore` + `PushCoordinator` environments; `RootTabView` (`App/RootTabView.swift:14`) tabs `enum RootTab { case today, cases, sessions, profile }`; Today = `TodayView(selectedTab:)` + `TodayViewModel`; ProfileView reuses `TodayViewModel`. Deep links: `enum PushRoute { case proposals; case session(Int) }` (`PushCoordinator.swift:16-19`), parsed by `PushCoordinator.route(from:)` (`:31-43`, reads `kind` + `session_id`), consumed by `RootTabView.onChange(of: pushCoordinator.pendingRoute)` (`:47-51`, currently always → `.sessions`). Logout resets push reg via `sessionStore.onLogout` → `pushCoordinator.resetRegistration()` (`CaseRoomApp.swift:29-31`).
**Widget extension** — `CaseRoomWidgets` target (bundle `studio.ogee.caseroom.widgets`), sources `[CaseRoomWidgets, CaseRoom/LiveActivity]` (`project.yml:39`); `@main CaseRoomWidgetsBundle: WidgetBundle` (`SessionLiveActivity.swift:108-113`) contains ONLY `SessionLiveActivity()`. **No entitlements files exist anywhere; no App Group; no #available; no AppIntents/FoundationModels imports** (all verified-absent).
**project.yml** — `bundleIdPrefix: studio.ogee`, `deploymentTarget iOS 17.0`, WebRTC SPM pinned 150.0.0. Info.plist injection via target `info: {path, properties}` (custom keys like `API_BASE_URL` live here). Tests: `CaseRoomTests` target, 155 tests. Workflow: `cd ios && xcodegen && xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test`.

---

## Phase A — Backend: drills + streak + availability

### Task 1: Migration 017 — drill_attempts + attempts endpoint + daily streak in dashboard

**Files:**
- Create: `db/migrations/017_drill_attempts.sql`, `webapp/repositories/drill_attempts.py`
- Modify: `webapp/routes/api_v1.py` (attempts endpoint + dashboard fields)
- Test: `tests/test_drills_api.py` (new)

**Interfaces (produces):**
- Table `drill_attempts(id, user_id, drill_type, source, drill_key, correct, completed_at)`.
- `record_attempt(user_id: int, *, drill_type: str, source: str, drill_key: str | None, correct: bool) -> dict` (returns inserted row).
- `streak_days(user_id: int) -> int` — consecutive UTC days ending today-or-yesterday where the user has ≥1 drill attempt OR ≥1 finalized session (DF-1).
- `attempted_today(user_id: int) -> bool` (UTC).
- `POST /api/v1/drills/attempts` body `{drill_type, source, drill_key?, correct}` → 204.
- `GET /api/v1/dashboard` response gains `"streak_days": int, "drill_done_today": bool` (existing keys unchanged).

- [ ] **Step 1: Migration**
```sql
-- db/migrations/017_drill_attempts.sql
-- P4 habit layer: one row per completed solo drill (on-device FM or server
-- bank). Powers the daily streak; superseded-in-place by the drills-DB track.
CREATE TABLE IF NOT EXISTS drill_attempts (
    id          serial      PRIMARY KEY,
    user_id     int         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    drill_type  text        NOT NULL CHECK (drill_type IN ('market_sizing','mental_math','framework_recall')),
    source      text        NOT NULL CHECK (source IN ('on_device','server')),
    drill_key   text,
    correct     boolean     NOT NULL,
    completed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_drill_attempts_user_day
    ON drill_attempts (user_id, completed_at);
```
- [ ] **Step 2: Apply + verify** — `python main.py apply-sql-migration db/migrations/017_drill_attempts.sql`; `psql "$DATABASE_URL" -c '\d drill_attempts'` shows the table.
- [ ] **Step 3: Failing tests** (`tests/test_drills_api.py`, unittest + `@unittest.skipUnless(_READY, ...)`, session-cookie mint pattern, resolve user ids by email; clean up inserted `drill_attempts` rows for the test user in setUp AND tearDown so the suite stays hermetic): (a) `record_attempt` inserts + returns row; (b) `streak_days`: 0 with no data → insert attempts at UTC today and today-1 → 2; a gap (today-3) doesn't extend; an attempt ONLY yesterday still yields 1 (yesterday-anchored); a finalized session day counts (insert a `practice_sessions` row with `state='finalized', ended_at=now()` for the user via SQL, then delete it in cleanup); (c) `POST /api/v1/drills/attempts` → 204 and the row lands; invalid `drill_type` → 422; unauthenticated → 401; (d) `GET /api/v1/dashboard` includes `streak_days` + `drill_done_today` and they move after an attempt. RUN → FAIL.
- [ ] **Step 4: Implement** — repository with the canonical pool/dict_row pattern. Streak SQL (one round-trip, computed in Python from distinct days):
```python
_DAYS_SQL = """
SELECT DISTINCT day FROM (
    SELECT (completed_at AT TIME ZONE 'UTC')::date AS day
      FROM drill_attempts WHERE user_id = %(u)s
    UNION
    SELECT (ended_at AT TIME ZONE 'UTC')::date AS day
      FROM practice_sessions
     WHERE state = 'finalized' AND ended_at IS NOT NULL
       AND (interviewer_id = %(u)s OR candidate_id = %(u)s)
) d ORDER BY day DESC LIMIT 400;
"""
```
Walk the sorted days: streak = consecutive run ending at UTC-today or UTC-yesterday. Endpoint: Pydantic `DrillAttemptBody(drill_type: Literal['market_sizing','mental_math','framework_recall'], source: Literal['on_device','server'], drill_key: str | None = Field(default=None, max_length=200), correct: bool)`; handler mirrors `POST /api/v1/devices` (204). Dashboard handler adds the two fields.
- [ ] **Step 5: RUN PASS** (new file + full backend suite). **Commit** `"Add drill_attempts, attempts endpoint, and daily streak in dashboard"`.

---

### Task 2: Drill template bank + deterministic daily drill endpoint

**Files:**
- Create: `webapp/drills.py`, `webapp/drill_templates.json`
- Modify: `webapp/routes/api_v1.py` (two GET endpoints)
- Test: `tests/test_drills_bank.py` (new)

**Interfaces (produces):**
- `webapp/drill_templates.json` — the single template source (server serves it to devices too). Shape:
```json
{"version": 1, "templates": [
  {"key": "mm_pct_change", "drill_type": "mental_math",
   "framing": "Your client's revenue moved from ${a}M to ${b}M.",
   "question": "What is the percent change?",
   "op": "pct_change", "params": {"a": [80, 960, 10], "b": [80, 960, 10]},
   "answer_format": "percent", "tolerance_pct": 2.0},
  {"key": "ms_coffee_shops", "drill_type": "market_sizing",
   "question": "Estimate the number of coffee shops in a US city of {pop} million people.",
   "params": {"pop": [1, 9, 1]}, "reference_per_unit": 700, "unit_param": "pop",
   "tolerance_factor": 2.0,
   "explanation": "~1 shop per ~1,400 residents: {pop}M people → about {answer} shops. Anchor on people-per-shop, then sanity-check against a neighborhood you know."},
  {"key": "fr_profit_tree_root", "drill_type": "framework_recall",
   "question": "In a profitability tree, profit decomposes first into…",
   "choices": ["Revenue and costs", "Price and volume", "Fixed and variable costs", "Market size and share"],
   "correct_index": 0,
   "explanation": "Profit = Revenue − Costs is the root split; price × volume sits UNDER revenue."}
]}
```
  Numeric `params` are `[lo, hi, step]` inclusive ranges. **≥30 templates: ≥10 mental_math (ops: `pct_change`, `growth_compound` (2 periods), `breakeven_units`, `margin_pct`, `markup_price`, `market_share_revenue`, `per_capita`, `weighted_avg_2`, `cagr_2yr_approx`, `payback_months`), ≥8 market_sizing, ≥12 framework_recall.** Every numeric answer is computable from the op + drawn params (that's the correctness contract).
- `generate_drill(template: dict, seed: int) -> dict` — pure/deterministic: draws params with `random.Random(seed)`, computes the answer via the op table, renders `framing`/`question`/`explanation` with `str.format`, shuffles `framework_recall` choices (tracking `correct_index`). Returns the **wire drill**: `{key, drill_type, prompt, choices?: [str], answer: {kind: "numeric"|"choice", value: float?, tolerance_pct?: float, tolerance_factor?: float, correct_index?: int}, explanation, numbers: [str]}` (`numbers` = the literal numerics that appear in the prompt — the iOS FM validator consumes this).
- `daily_drill(user_id: int, on: date | None = None) -> dict` — seed `int(hashlib.sha256(f"{user_id}:{(on or utcnow date).isoformat()}".encode()).hexdigest()[:8], 16)`; template = seeded choice weighted evenly across the three `drill_type`s (pick type by `seed % 3`, then a seeded template of that type). Deterministic all day, varies by day and by user.
- `GET /api/v1/drills/daily` → `{"drill": <wire drill>, "date": "YYYY-MM-DD"}` (auth-only GET).
- `GET /api/v1/drills/templates` → the raw JSON file + `{"version": 1}` (device offline cache for the FM engine).

- [ ] **Step 1: Failing tests** (`tests/test_drills_bank.py` — pure logic, NO DB gate except the two endpoint tests): (a) bank loads, ≥30 templates, per-type minimums met, every template's declared fields validate (op in op-table for mental_math, choices+correct_index for recall, reference for sizing); (b) determinism: `generate_drill(t, 42)` twice → identical dicts; different seeds → different params for at least one op; (c) **answer-correctness properties per op** — e.g. `pct_change`: value == (b−a)/a×100 for the drawn a,b; `breakeven_units`: fixed/(price−vc) with drawn params guaranteed price>vc by range construction; run every mental_math template at 25 seeds and recompute the expected answer independently in the test; (d) recall shuffle keeps the correct answer at the tracked index (25 seeds); (e) sizing: answer == reference_per_unit × drawn unit param; `numbers` contains every literal in the prompt; (f) `daily_drill` same user+date → identical; different user or date → differs (statistically: 10 users → ≥2 distinct keys); (g) `GET /api/v1/drills/daily` (DB-gated, cookie-minted) → 200, shape keys present, calling twice → identical drill; unauthenticated → 401; (h) `/drills/templates` → 200 with `version`. RUN → FAIL.
- [ ] **Step 2: Implement** `webapp/drills.py` — module-level `_BANK = json.loads((REPO_ROOT / "webapp/drill_templates.json").read_text())` loaded once; op table as a dict of small pure functions `{"pct_change": lambda p: (p["b"]-p["a"])/p["a"]*100, ...}`; ranges drawn with `rng.randrange(lo, hi+1, step)`. Write the 30+ templates (business-toned, fictional clients, no real-company claims). Endpoints in `api_v1.py`.
- [ ] **Step 3: RUN PASS** (file + full suite). **Commit** `"Add drill template bank and deterministic daily drill endpoints"`.

---

### Task 3: Migration 018 — availability + free-now endpoints + instant-match push

**Files:**
- Create: `db/migrations/018_availability.sql`, `webapp/repositories/availability.py`
- Modify: `webapp/routes/api_v1.py`
- Test: `tests/test_availability.py` (new)

**Interfaces (produces):**
- Table `availability(user_id int PK REFERENCES users ON DELETE CASCADE, free_until timestamptz NOT NULL, updated_at timestamptz NOT NULL DEFAULT now())`.
- `set_free(user_id: int, minutes: int) -> dict` — upsert `free_until = now() + make_interval(mins => %(m)s)`; returns `{"free_until": dt, "was_free": bool}` (`was_free` = row existed with `free_until > now()` before the upsert, read `FOR UPDATE` in the same txn — powers the fresh-toggle push gate).
- `clear_free(user_id: int) -> None`.
- `list_free(exclude_user_id: int | None = None) -> list[dict]` — `SELECT a.user_id, u.display_name AS name, a.free_until FROM availability a JOIN users u ON u.id = a.user_id WHERE a.free_until > now()` (+ exclusion), ordered by `free_until DESC`. **Lazy expiry — no sweep, no loop.**
- `PUT /api/v1/availability` body `{minutes: int}` (clamped 5–240 via `Field(ge=5, le=240)`) → `{"free_until": iso, "others": [{user_id, name, free_until}]}`; when `was_free` is false, `background.add_task(push_to_user, other.user_id, title="Free now", body=f"{name} is free for a case now", data={"kind": "free_now", "user_id": user.id, "name": name})` for each other free user (name = `display_name or email`).
- `DELETE /api/v1/availability` → 204. `GET /api/v1/availability` → `{"free_until": iso|null, "others": [...]}`.

- [ ] **Step 1: Migration** (write it in the 016 style with a 2-line comment header, apply, `\d availability`).
- [ ] **Step 2: Failing tests** (`tests/test_availability.py`, DB-gated, cookie-minted; delete the test users' availability rows in setUp/tearDown): (a) PUT → 200, `free_until` ≈ now+60m, row present; PUT again extends and `others` excludes self; (b) expiry is lazy: SQL-update the row to `now() - 1 minute` → GET shows `free_until: null` and `list_free` omits it; (c) DELETE → 204 → GET null; (d) minutes clamp: 3 → 422, 500 → 422; (e) **push**: monkeypatch `api_v1`'s imported `push_to_user` recorder (patch where it's USED, i.e. the reference in `webapp/routes/api_v1.py`, mirroring `test_push_events.py` style) — user B free, then user A toggles → exactly one push to B with `kind=free_now` + A's id; A extends (PUT again while still free) → NO new push; (f) unauthenticated → 401. RUN → FAIL.
- [ ] **Step 3: Implement** repo + endpoints per the interfaces above (single connection block for the `was_free`-read + upsert).
- [ ] **Step 4: RUN PASS** (file + full backend suite green). **Commit** `"Add free-now availability with instant-match push"`.

---

## Phase B — iOS: shared foundation + drills

### Task 4: App Group, entitlements, shared cookie store, WidgetSnapshot store

**Files:**
- Create: `ios/CaseRoom/Support/CaseRoom.entitlements`, `ios/CaseRoomWidgets/CaseRoomWidgets.entitlements` (via project.yml), `ios/CaseRoom/Shared/AppGroup.swift`, `ios/CaseRoom/Shared/SnapshotStore.swift`
- Modify: `ios/project.yml`, `ios/CaseRoom/Networking/APIClient.swift`, `ios/CaseRoom/Networking/SignalingClient.swift`, `ios/CaseRoom/State/SessionStore.swift` (logout hook)
- Test: `ios/CaseRoomTests/SnapshotStoreTests.swift`, extend `APIClientTests`

**Interfaces (produces):**
- `enum AppGroup { static let id = "group.studio.ogee.caseroom"; static var containerURL: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) }; static func makeURLSessionConfiguration() -> URLSessionConfiguration }` — the configuration uses `HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: id)` when the container resolves, else falls back to `.shared` cookie storage (unprovisioned/dev-build safety). Also `static func migrateCookiesIfNeeded(from: HTTPCookieStorage = .shared, apiHost: String)` — one-time copy of the API host's cookies into the group store (idempotent: guarded by a `UserDefaults(suiteName: id)` flag).
- `struct WidgetSnapshot: Codable, Equatable { var streakDays: Int; var drillDoneToday: Bool; var nextSessionTitle: String?; var nextSessionOther: String?; var nextSessionAt: Date?; var freeUntil: Date?; var updatedAt: Date }`
- `struct SnapshotStore { static func write(_ s: WidgetSnapshot); static func read() -> WidgetSnapshot?; static func clear() }` — JSON file `widget-snapshot.json` in the group container (nil container → no-op/nil). ISO8601 dates (plain, no fractional — the widget decodes with the same formatter).
- `APIClient.init(session:)` default becomes `URLSession(configuration: AppGroup.makeURLSessionConfiguration())`; `SignalingClient`'s WS URLSession uses the same configuration (find its session construction and switch it — the WS handshake must carry the same cookies). Explicit `session:` injection (tests) unchanged.
- Logout: `SessionStore.logout()` additionally calls `SnapshotStore.clear()` and clears API-host cookies from the group store (extend the existing `onLogout` chain — keep the APNs reset).

- [ ] **Step 1: project.yml** — add to BOTH targets:
```yaml
    entitlements:
      path: CaseRoom/Support/CaseRoom.entitlements        # (widgets: CaseRoomWidgets/CaseRoomWidgets.entitlements)
      properties:
        com.apple.security.application-groups: [group.studio.ogee.caseroom]
```
  `xcodegen generate` → confirm the two `.entitlements` files are written and referenced (`grep CODE_SIGN_ENTITLEMENTS ios/CaseRoom.xcodeproj/project.pbxproj`).
- [ ] **Step 2: Failing tests** — `SnapshotStoreTests`: write→read round-trip equality; `clear()` → read nil; store is nil-container-safe (can't force nil in sim — assert no crash + document). APIClientTests addition: the default configuration's cookie storage is group-backed OR `.shared` fallback (assert `AppGroup.makeURLSessionConfiguration().httpCookieStorage` non-nil); cookie migration is idempotent (call twice, cookies not duplicated — use a scratch `HTTPCookieStorage` instance pair). RUN → FAIL (types absent).
- [ ] **Step 3: Implement** all four interfaces; call `AppGroup.migrateCookiesIfNeeded(apiHost:)` once in `CaseRoomApp.init` before first network use; wire logout clearing.
- [ ] **Step 4: RUN PASS** — full iOS suite + **build the widget scheme too** (`xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom build` covers both — widget is an app dependency). **Commit** `"Add App Group with shared cookies and widget snapshot store"`.

---

### Task 5: Drill models, grader, ServerDrillEngine, attempt sync

**Files:**
- Create: `ios/CaseRoom/Drills/DrillModels.swift`, `ios/CaseRoom/Drills/DrillGrader.swift`, `ios/CaseRoom/Drills/ServerDrillEngine.swift`, `ios/CaseRoom/Drills/AttemptRecorder.swift`
- Modify: `ios/CaseRoom/Networking/APIClient.swift` (3 methods), `ios/CaseRoom/Networking/Models.swift` (DashboardStats)
- Test: `ios/CaseRoomTests/DrillModelsTests.swift`, `DrillGraderTests.swift`, `ServerDrillEngineTests.swift`; new fixture `Fixtures/drill_daily.json`

**Interfaces (produces):**
- `struct Drill: Codable, Equatable { let key: String; let drillType: DrillType; let prompt: String; let choices: [String]?; let answer: DrillAnswer; let explanation: String; let numbers: [String] }`, `enum DrillType: String, Codable { case marketSizing = "market_sizing", mentalMath = "mental_math", frameworkRecall = "framework_recall" }`, `struct DrillAnswer: Codable, Equatable { let kind: AnswerKind; let value: Double?; let tolerancePct: Double?; let toleranceFactor: Double?; let correctIndex: Int? }` (`enum AnswerKind: String, Codable { case numeric, choice }`).
- `enum DrillGrader { static func grade(_ drill: Drill, numericInput: Double?, choiceIndex: Int?) -> Bool }` — numeric+tolerancePct: `abs(input-value) <= value*tolerancePct/100`; numeric+toleranceFactor (sizing): `value/f <= input <= value*f`; choice: index equality.
- `protocol DrillEngine { func dailyDrill() async throws -> Drill; var sourceLabel: String { get } }` (`sourceLabel` ∈ `"server"|"on_device"` — feeds the attempt POST).
- `ServerDrillEngine(service: DrillService)` — `protocol DrillService { func dailyDrill() async throws -> Drill; func templatePack() async throws -> Data; func recordAttempt(drillType: String, source: String, drillKey: String?, correct: Bool) async throws }`, implemented by APIClient: `dailyDrill()` → `GET /api/v1/drills/daily` (unwrap `{drill, date}`), `templatePack()` → raw `Data` of `/api/v1/drills/templates`, `recordAttempt` → `POST /api/v1/drills/attempts` (204).
- `AttemptRecorder(service: DrillService)` — `func record(drill: Drill, source: String, correct: Bool) async` posts; on failure queues `{drillType, source, drillKey, correct}` into `UserDefaults(suiteName: AppGroup.id)` array key `"pendingDrillAttempts"`; `func flushPending() async` retries (called at app foreground). Never throws to the UI.
- `DashboardStats` gains `let streakDays: Int?`, `let drillDoneToday: Bool?` (optional — old fixtures/back-compat).

- [ ] **Step 1: Failing tests** — decode `drill_daily.json` fixture (copy a REAL response captured from the Task-2 endpoint via the dev server, all three drill types exercised across tests: numeric-pct, sizing-factor, choice); grader: tolerance boundary cases (exactly at tolerance passes; outside fails; factor bounds inclusive; wrong choice fails); ServerDrillEngine via StubURLProtocol returns the decoded drill; AttemptRecorder: success posts once (assert recordedRequests path+body), failure enqueues, flush drains queue on success and preserves it on repeat failure; DashboardStats decodes WITH and WITHOUT the new keys. RUN → FAIL.
- [ ] **Step 2: Implement.** **Step 3: RUN PASS** (full iOS suite). **Commit** `"Add drill models, grader, server engine, and attempt sync"`.

---

### Task 6: FoundationModelDrillEngine (iOS 26+, validated dressing) + engine selection

**Files:**
- Create: `ios/CaseRoom/Drills/LocalDrillGenerator.swift`, `ios/CaseRoom/Drills/FoundationModelDrillEngine.swift`, `ios/CaseRoom/Drills/DrillEngineProvider.swift`, `ios/CaseRoom/Drills/TemplateCache.swift`
- Test: `ios/CaseRoomTests/LocalDrillGeneratorTests.swift`, `DrillEngineProviderTests.swift`; fixture `Fixtures/drill_templates.json` (the real bank file, copied verbatim from `webapp/drill_templates.json`)

**Interfaces (produces):**
- `TemplateCache` — caches the `/api/v1/drills/templates` bytes in the group container (`drill-templates.json`); `func load() -> Data?` (cache-first), `func refresh(service: DrillService) async` (best-effort overwrite, called on app foreground).
- `struct LocalDrillGenerator { init(templatePack: Data) throws; func dailyDrill(userId: Int, date: Date) -> Drill }` — **a Swift port of `webapp/drills.py`'s interpreter**: identical seed derivation (`SHA256("\(userId):yyyy-MM-dd")` first 8 hex chars as UInt32), identical op table, identical param drawing. Use a tiny local deterministic PRNG (`SplitMix64` seeded by the value — implement inline, ~6 lines) — do NOT use `SystemRandomNumberGenerator` (non-seedable) or try to match Python's Mersenne Twister; determinism only needs to hold per-device-per-day, not across server/device (document this in the type docblock).
- `@available(iOS 26.0, *) final class FoundationModelDrillEngine: DrillEngine` — `sourceLabel == "on_device"`. `dailyDrill()`: (1) `LocalDrillGenerator.dailyDrill` from the cached pack → the deterministic drill; (2) ask FM to restyle: `@Generable struct DrillDressing { @Guide(...) var prompt: String }`, session prompt = "Rewrite this case-interview drill prompt in a fresh voice. Keep EVERY number exactly as given, keep the question's meaning, ≤2 sentences + the question. Numbers: ... Prompt: ..."; (3) **validate**: every string in `drill.numbers` must appear verbatim in the rewritten prompt, else keep the plain prompt; grade/answer/explanation NEVER change. Availability check inside: `guard case .available = SystemLanguageModel.default.availability else { throw DrillEngineError.unavailable }`.
- `enum DrillEngineProvider { static func make(service: DrillService, fmAvailable: () -> Bool = defaultFMProbe) -> DrillEngine }` — returns the FM engine when `#available(iOS 26.0, *)` AND the probe says available AND the template cache is non-nil; else `ServerDrillEngine`. The probe closure is injected for tests (`defaultFMProbe` wraps `SystemLanguageModel` behind `#available`).

- [ ] **Step 1: Failing tests** — LocalDrillGenerator against the bundled real pack: same (user, date) → identical drill twice; different date → different drill (statistically over 10 days: >1 distinct key); every mental_math op recomputed independently in the test matches (mirror the Python property tests — this catches port drift); recall shuffle tracks correct_index; prompt contains every `numbers` entry. Provider: injected `fmAvailable: {false}` → ServerDrillEngine; `{true}` on sim (iOS 26 unavailable at runtime? — the provider test injects the probe, so assert type by `sourceLabel`). Validation logic: extract the number-check into `static func dressingIsValid(_ dressed: String, numbers: [String]) -> Bool` and unit-test it (missing number → false; reformatted "1,200" vs "1200" → false, we require verbatim). RUN → FAIL.
- [ ] **Step 2: Implement.** All FM references (`import FoundationModels`, the @Generable type, the session call) live ONLY in `FoundationModelDrillEngine.swift`, whole file `@available(iOS 26.0, *)` — confirm the target still builds for iOS 17 deployment (it will: availability annotations, iOS 26 SDK).
- [ ] **Step 3: RUN PASS** (full iOS suite — FM engine itself won't run in tests; its deterministic core + validator + provider selection are what's covered; live FM generation is Thomas's device check). **Commit** `"Add on-device Foundation Models drill engine with validated dressing"`.

---

### Task 7: Drill UI — Today card + drill sheet

**Files:**
- Create: `ios/CaseRoom/State/DrillViewModel.swift`, `ios/CaseRoom/Views/DrillView.swift`
- Modify: `ios/CaseRoom/Views/TodayView.swift` (drill card), `ios/CaseRoom/State/TodayViewModel.swift` (streak fields pass-through)
- Test: `ios/CaseRoomTests/DrillViewModelTests.swift`

**Interfaces (produces):**
- `@Observable @MainActor final class DrillViewModel { init(engine: DrillEngine, recorder: AttemptRecorder); var phase: Phase (.loading/.ready(Drill)/.answered(correct: Bool)/.failed(String)); var numericInput: String; var selectedChoice: Int?; func load() async; func submit() async }` — submit grades via `DrillGrader`, records via `AttemptRecorder` (fire-and-forget), sets `.answered`, updates the snapshot (`drillDoneToday = true`, streak +1 if first today) + `WidgetCenter.shared.reloadAllTimelines()`.
- `DrillView(viewModel:)` — prompt; numeric drills: `TextField` with `.keyboardType(.decimalPad)` + unit hint; choice drills: choice buttons; submit; answered state shows correct/incorrect + the `value`/correct choice + `explanation` + streak line; "Done" dismisses. Presented as a sheet from TodayView's new **DrillCard** ("Drill of the day" · done-check or CTA · `streakDays` flame count) placed above the existing StreakCard; card reads `streakDays`/`drillDoneToday` from the dashboard load.
- `TodayViewModel` exposes `streakDays: Int` / `drillDoneToday: Bool` (from `DashboardStats`, defaulting 0/false) and **writes the WidgetSnapshot after every successful dashboard load** (from `DashboardStats` + `nextSession`) + reloads timelines.

- [ ] **Step 1: Failing tests** — VM with stubbed engine/recorder: load → `.ready`; numeric submit correct/incorrect paths; choice submit; recorder called with the engine's `sourceLabel`; engine failure → `.failed` with message; TodayViewModel: after `load()` with a dashboard stub containing the new fields, the snapshot store holds matching values (inject a snapshot-writing closure or use the real store — group container works in sim). RUN → FAIL.
- [ ] **Step 2: Implement.** Match the existing card/visual idiom in TodayView (read `StreakCard` at `TodayView.swift:105-117` and imitate; brand tokens per the myCase guide, no new colors).
- [ ] **Step 3: RUN PASS** (full iOS suite) + boot the app in the sim (`xcodebuild ... build` + `xcrun simctl install/launch booted studio.ogee.caseroom`) and confirm no crash with the dev server up. **Commit** `"Add drill of the day UI"`.

---

## Phase C — Widgets

### Task 8: Streak + Next-Session + Free-Now widgets (home + lock screen)

**Files:**
- Create: `ios/CaseRoomWidgets/CaseRoomHabitWidgets.swift` (all three widget kinds + shared TimelineProvider + views)
- Modify: `ios/CaseRoomWidgets/SessionLiveActivity.swift` (add kinds to `CaseRoomWidgetsBundle.body`), `ios/project.yml` (add `CaseRoom/Shared` + `CaseRoom/Drills/DrillModels.swift`? NO — widgets need ONLY `CaseRoom/Shared`, keep the surface minimal: add `CaseRoom/Shared` to the widget target's `sources`)
- Test: `ios/CaseRoomTests/WidgetTimelineTests.swift` (provider logic lives in shared code so the app test target can reach it: put `entries(from snapshot: WidgetSnapshot, now: Date) -> [SnapshotEntry]` in `CaseRoom/Shared/WidgetTimeline.swift`)

**Interfaces (produces):**
- `struct SnapshotEntry: TimelineEntry { let date: Date; let snapshot: WidgetSnapshot? }` + pure `WidgetTimeline.entries(from:now:)` in the SHARED folder: one entry now; if `nextSessionAt` is in the future add boundary entries at `nextSessionAt - 15m` and `nextSessionAt` (so "in 2h" → "starting soon" → "now" render without waking the app); if `freeUntil` future, a boundary entry at `freeUntil` (auto-flip to not-free). Refresh policy `.after(now + 30m)`.
- Widget kinds (all `StaticConfiguration` reading `SnapshotStore.read()`, families: streak `systemSmall + accessoryCircular`, next-session `systemSmall/systemMedium + accessoryRectangular`, free-now `systemSmall + accessoryCircular`): **StreakWidget** (kind `"CaseRoomStreak"`: flame + `streakDays`, done-check when `drillDoneToday`, `widgetURL(URL(string:"caseroom://drill")!)`); **NextSessionWidget** (kind `"CaseRoomNextSession"`: case title, other user, relative time via `Text(date, style: .relative)`, empty state "No session scheduled — propose one", `widgetURL("caseroom://sessions")`); **FreeNowWidget** (kind `"CaseRoomFreeNow"`: free/not-free state + remaining time; **interactive**: `Button(intent: ToggleFreeNowIntent())` — the intent arrives in Task 10; for THIS task ship it with `widgetURL("caseroom://freenow")` and a `// swapped to Button(intent:) in the intents task` marker so the widget is functional standalone).
- Nil snapshot (logged out / never launched) → placeholder "Open CaseRoom to sign in".

- [ ] **Step 1: Failing tests** — `WidgetTimeline.entries`: no next session → 1 entry + sane refresh; session in 2h → entries at now/-15m/at-time ordered ascending; free until +30m → boundary entry; past session date → no extra entries. RUN → FAIL.
- [ ] **Step 2: Implement** (provider in the widget file delegates to the shared pure function; views theme-follow with brand tokens; keep the Live Activity untouched).
- [ ] **Step 3: RUN PASS** + `xcodegen && xcodebuild ... build` (widget target compiles). Manual sanity NOT required here (Thomas's device pass); note in the report that widget gallery verification is deferred.
- [ ] **Step 4: Commit** `"Add streak, next-session, and free-now widgets"`.

---

## Phase D — Free-now + App Intents

### Task 9: iOS availability API + free-now UI + propose-now flow + push route

**Files:**
- Create: `ios/CaseRoom/Views/ProposeNowView.swift`, `ios/CaseRoom/State/FreeNowViewModel.swift`
- Modify: `ios/CaseRoom/Networking/APIClient.swift` (+`AvailabilityService` conformance, +`createProposal`), `Models.swift` (`AvailabilityStatus`, `FreeUser`), `Views/TodayView.swift` (free-now toggle section), `Support/PushCoordinator.swift` (+`.proposeTo(Int)` route from `kind=="free_now"`), `App/RootTabView.swift` (route handling)
- Test: `ios/CaseRoomTests/FreeNowViewModelTests.swift`, extend `PushRouteTests`, `APIClientTests`

**Interfaces (produces):**
- Models: `struct AvailabilityStatus: Codable { let freeUntil: Date?; let others: [FreeUser] }`, `struct FreeUser: Codable, Identifiable { let userId: Int; let name: String; let freeUntil: Date; var id: Int { userId } }`.
- `protocol AvailabilityService { func availability() async throws -> AvailabilityStatus; func setFree(minutes: Int) async throws -> AvailabilityStatus; func clearFree() async throws }` — APIClient: GET/PUT/DELETE `/api/v1/availability` (PUT response reshaped into `AvailabilityStatus` with own `free_until`).
- `APIClient.createProposal(toUserId: Int, caseId: Int, fromRole: String, message: String?) async throws -> Proposal` — `POST /api/proposals` (NOT /api/v1 — verified native-compatible) body `{to_user_id, case_id, from_role, message, proposed_times: [<now, plain-ISO8601>]}`.
- `FreeNowViewModel(service: AvailabilityService)` — `var isFree/freeUntil/others`, `func toggle() async` (on: `setFree(minutes: 60)` per DF-3; off: `clearFree()`), `func refresh() async`; after every mutation update `SnapshotStore` (`freeUntil`) + reload timelines. TodayView section: toggle + "N classmates free now" list, each row → `ProposeNowView(toUser:)` sheet.
- `ProposeNowView` — case picker (reuses `CasesViewModel` search list), role picker (interviewer/candidate), send → `createProposal` → confirmation. Deep-linkable.
- `PushRoute` gains `case proposeTo(Int)` (from payload `kind=="free_now"`, `user_id`); RootTabView routes it: switch to `.today` + set a `presentedProposeTo: Int?` state that presents `ProposeNowView`. (Also fix the existing collapse minimally: `.proposals` → `.sessions` tab stays as-is — out of scope beyond adding the new case.)

- [ ] **Step 1: Failing tests** — PushRoute parses `{"kind":"free_now","user_id":7}` → `.proposeTo(7)` (Int AND String `user_id`, mirroring existing tests); FreeNowViewModel toggle on/off/refresh against a stub service (assert snapshot store updated); APIClient: `createProposal` hits `/api/proposals` with snake_case body + `proposed_times` single entry (StubURLProtocol recordedRequests); availability round-trip decodes. RUN → FAIL.
- [ ] **Step 2: Implement. Step 3: RUN PASS** (full iOS suite). **Commit** `"Add free-now toggle, instant-match push route, and propose-now flow"`.

---

### Task 10: App Entities + App Intents + App Shortcuts + interactive widget button

**Files:**
- Create: `ios/CaseRoom/Intents/CaseRoomEntities.swift` (CaseEntity/SessionEntity/ProposalEntity + queries), `ios/CaseRoom/Shared/Intents/ToggleFreeNowIntent.swift` (**Shared** — compiled into both targets), `ios/CaseRoom/Intents/CaseRoomIntents.swift` (StartDrillIntent, NextSessionIntent, AppShortcuts)
- Modify: `ios/project.yml` (widget target sources += `CaseRoom/Shared`), `App/RootTabView.swift` + `App/CaseRoomApp.swift` (`.onOpenURL` for `caseroom://` + intent-posted routes), `ios/CaseRoomWidgets/CaseRoomHabitWidgets.swift` (swap FreeNowWidget to `Button(intent:)`)
- Test: `ios/CaseRoomTests/IntentsTests.swift`

**Interfaces (produces):**
- Entities (app target only): `struct CaseEntity: AppEntity` (`id: Int`, `title`, `school`, `difficulty`; `displayRepresentation` title+subtitle; `defaultQuery = CaseEntityQuery()` — `EntityQuery` whose `entities(for:)` maps ids via `APIClient.shared.caseDetail`, `suggestedEntities()` = first 5 of `cases()`), `SessionEntity` (from upcoming `sessions(scope:)`), `ProposalEntity` (pending `proposals()`). Each wraps the verified Codables — logged-out/network failure → empty arrays, never throw out of `suggestedEntities`.
- `struct StartDrillIntent: AppIntent` — `static let title: LocalizedStringResource = "Start Drill"`, `static let openAppWhenRun = true`; `perform()` posts `AppRoute.drill` (a new `@MainActor` router singleton `AppRouter.shared.pending: AppRoute?` observed by RootTabView — reuse the PushRoute plumbing by folding both into `enum AppRoute { case drill, sessions, proposeTo(Int), freeNow }`; PushRoute maps into AppRoute) → `.result()`.
- `struct NextSessionIntent: AppIntent` — title "Next Session", `openAppWhenRun = false`; `perform()` → `APIClient.shared.dashboard()`; dialog: with next: `"Next: <caseTitle> with <otherUser>, <relative time>."`, else `"Nothing scheduled. Say 'I'm free now' to find a partner."` → `.result(dialog:)`.
- `struct ToggleFreeNowIntent: AppIntent` (SHARED file, no app-only imports — talks to `APIClient` via a minimal local construction: `AvailabilityService` conformance is on APIClient which is app-target… **so give the shared file its own tiny client**: `struct AvailabilityLite { let baseURL: URL (from Bundle.main API_BASE_URL with the same fallback); let session = URLSession(configuration: AppGroup.makeURLSessionConfiguration()); func status() / setFree(minutes:) / clear() }` — 3 endpoints, snake_case decode, ~60 lines; `AppGroup` + snapshot types are already in Shared): `perform()` reads current status → toggles → updates `SnapshotStore` → `WidgetCenter.reloadTimelines(ofKind: "CaseRoomFreeNow")` → `.result(dialog: "You're free for the next hour — N classmates are free now." / "You're no longer free.")`. Works from Siri, Shortcuts, Action button, and the widget button (runs in the WIDGET process — hence Shared + group cookies from Task 4).
- `struct CaseRoomShortcuts: AppShortcutsProvider` — three `AppShortcut`s with `phrases` embedding `.applicationName`: "Start a drill in \(.applicationName)", "What's my next session in \(.applicationName)", "I'm free now in \(.applicationName)".
- `.onOpenURL` in RootTabView maps `caseroom://drill|sessions|freenow` → AppRoute (covers the Task-8 widgetURLs). Add `CFBundleURLTypes` for scheme `caseroom` via `project.yml info.properties`.

- [ ] **Step 1: Failing tests** — AppRoute mapping from PushRoute payloads + URL parsing (`caseroom://drill` → `.drill`, unknown → nil); NextSessionIntent dialog composition via an injected dashboard-fetch closure (refactor: `static func dialogText(for stats: DashboardStats) -> String`, test both branches); ToggleFreeNowIntent's toggle decision (`static func nextAction(current: AvailabilityStatus) -> ToggleAction` on/off) — pure parts tested; entity mapping `CaseEntity(from: CaseSummary)` field-correct. RUN → FAIL.
- [ ] **Step 2: Implement** (entity queries + intents; `xcodegen` after project.yml edits; verify the widget target compiles the Shared folder — WidgetKit import needed for the reload call is fine in the extension, and `WidgetCenter` is also available in-app).
- [ ] **Step 3: RUN PASS** (full iOS suite). Build both targets. Sim spot-check: `xcrun simctl openurl booted caseroom://drill` opens the drill sheet with the app installed+running (document output).
- [ ] **Step 4: Commit** `"Add App Entities, Start Drill / Next Session / Free Now intents, App Shortcuts"`.

---

## Phase E — Verification + handoff

### Task 11: Automated capstone — suites + live sim E2E

- [ ] **Backend**: `.venv/bin/python -m pytest tests/ -q` → green (expected ~340+: 313 collected pre-P4 + new drills/availability/attempts files). Record exact counts.
- [ ] **iOS**: `cd ios && xcodegen && xcodebuild -project CaseRoom.xcodeproj -scheme CaseRoom -destination 'platform=iOS Simulator,name=iPhone 17' test` (FOREGROUND) → green (155 pre-P4 + new). Record exact counts.
- [ ] **Live E2E over real HTTP** (dev server `nohup .venv/bin/python main.py serve --port 8077 > output/devserver.log 2>&1 & disown`, seeded users a/b): script `tests/e2e_p4_flow.py` (kept in repo, same style as `tests/e2e_inperson_flow.py`): login a → `GET /drills/daily` (assert deterministic on second call) → `POST /drills/attempts` → `GET /dashboard` asserts `drill_done_today true` + `streak_days ≥ 1` → login b → `PUT /availability` → login a → `PUT /availability` → assert response `others` contains b; with APNs disabled assert the push path was reached via the `was_free` gate (unit-covered) — the E2E asserts the HTTP contract: b's GET shows a; a's DELETE clears. Every step prints PASS/FAIL; exit non-zero on failure.
- [ ] **Sim fallback-drill run (the spec's done-when, simulator half)**: with the dev server up, launch the app in the iPhone 17 sim (API_BASE_URL default 127.0.0.1:8077), log in as a@yale.edu, complete the daily drill end-to-end via the ServerDrillEngine (FM unavailable in sim → provider must select the fallback), confirm the attempt row landed in Postgres (`SELECT * FROM drill_attempts ORDER BY id DESC LIMIT 1`). This may be driven manually-by-agent via simctl launch + log inspection; screenshot optional. Kill the dev server after; confirm port free.
- [ ] Commit `"P4 automated verification"` (test files).

### Task 12: PROGRESS.md handoff + Thomas-manual list

- [ ] Update `PROGRESS.md`: "P4 (habit + Siri layer) — BUILT" section with per-task evidence, the defaults taken (DF-1..5), and the **Thomas manual list**: (1) real-device FM drill on the iPhone 15 Pro (AI-hardware done-when half) — needs Apple-Intelligence enabled; (2) Siri: run all three App Shortcuts by voice (device); (3) widget gallery: add all three widgets home+lock, confirm live data + the interactive free-now button; (4) Apple portal: App Group `group.studio.ogee.caseroom` auto-registers with automatic signing — verify when signing both targets (carried: APNs .p8, push capability); (5) instant-match push end-to-end needs APNs keys + 2 devices; (6) merge `feature/ios-p4` (Thomas merges; chain is linear off feature/caseroom).
- [ ] Renumber note: Desktop drills plan (`~/Desktop/drill-question-db-plan.md`) migration moves 017 → **019** (017/018 now taken) — the orchestrator edits the Desktop docs (outside this repo).
- [ ] Commit `"Complete iOS P4: drills, widgets, intents, free-now"`.

---

## Risks & open items
- **@Generable / FoundationModels compile**: first FM code in the repo — if the pinned Xcode toolchain chokes on the macro in a `@available`-annotated file, isolate to the one file and report (don't fight it >2 attempts; the deterministic path keeps the feature alive).
- **Interactive widget auth**: the widget-process intent depends on group-shared cookies (Task 4). If `sharedCookieStorage(forGroupContainerIdentifier:)` proves empty in the sim extension process, the fallback is `openAppWhenRun = true` on ToggleFreeNowIntent (degrades gracefully — intent still works everywhere, widget button opens the app). Note it, don't spiral.
- **App Group provisioning on device** is Thomas's signing step; sim needs nothing.
- **Streak semantics** are UTC (DF-5) — a late-night ET drill lands on "tomorrow"; acceptable v1, noted for the owner.
- The `/api/v1/drills/*` contract is the seam the Desktop drills-DB track later fills with a real bank; keep response shapes generic (no template-bank leakage beyond `key`).

## Manual steps only Thomas can do
1. Real-device: FM drill (iPhone 15 Pro, Apple Intelligence on), Siri shortcuts, widget gallery + interactive button, instant-match push (2 devices + APNs .p8 — carried from P1).
2. Sign both targets with his team (App Group capability rides automatic signing).
3. Merge `feature/ios-p4`. (Also still open from the prior handoff: push `feature/caseroom`, on-device P3 call test, delete the plaintext TURN-creds txt in `mycase/`.)

## Self-review (author checklist — done)
- Spec P4 coverage: drill of the day FM+@Generable (T6) · offline zero-cost (template cache T6, attempt queue T5) · fallback server bank same UI (T2/T5, provider T6) · widgets streak+next-session home/lock (T8, snapshot T4/T7) · App Intents+Entities, three intents, Siri/Shortcuts/Action-button/interactive-widgets (T10, widget button T8→T10) · free-now toggle + instant-match push (T3/T9) · done-when: sim fallback (T11), FM-on-hardware + Siri (Thomas list, irreducibly manual).
- Placeholder scan: none — every step names real files/signatures; code shown where it's load-bearing (migrations, streak SQL, template shape, entitlements yaml).
- Type consistency: `Drill/DrillAnswer/DrillType` (T5) consumed by T6/T7; `WidgetSnapshot/SnapshotStore/AppGroup` (T4) consumed by T7/T8/T10; `AvailabilityStatus/FreeUser` (T9) match T3's wire shape; `AppRoute` (T10) supersedes-wraps `PushRoute` (T9 adds `.proposeTo` before the fold — T10 folds BOTH, tasks ordered so T9's tests are updated in T10's step 1 if signatures shift).
- Recon fidelity: dashboard shape, push kinds, `_MUTATING`, cookie-mint test idiom, `info.properties`, widget-bundle structure all quoted from the 2026-07-15 recon.

---
## Errata (found during execution — corrected in code, kept here so the plan text doesn't get re-trusted)
- **Task 5 grading formula (Critical, fixed in 7da3773):** the plan's `abs(input-value) <= value*tolerancePct/100` is wrong for negative answers (live `mm_pct_change` draws produce them ~half the time — RHS goes negative, everything grades wrong). Correct: `abs(input-value) <= abs(value)*tolerancePct/100`; factor path normalizes to `[min(value/f, value*f), max(...)]`. Task 6's Swift-port property tests must use the corrected semantics.
- **Task 2 `ms_coffee_shops` example anchor (fixed in 7484a5d):** the plan's illustrative `reference_per_unit: 700` was ~3× real-world density; bank ships 275.
- **Task 3 `list_free` (fixed in af71975):** plan's `u.display_name AS name` can emit null names; shipped `COALESCE(u.display_name, u.email)` so the iOS `FreeUser.name: String` decode is safe.
