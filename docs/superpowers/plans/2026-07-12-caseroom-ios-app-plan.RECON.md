# iOS P1 — Recon-locked facts & plan corrections

> Companion to `2026-07-12-caseroom-ios-app-plan.md`. Verified against the repo
> on branch `feature/ios-app` (2026-07-14). Where this file and the plan
> disagree, **this file wins** — the plan used placeholder names in a few spots.
> Every implementer dispatch references this file for exact names.

## Locked backend interfaces (do not re-derive)

- **Settings** (`webapp/settings.py`): frozen `@dataclass Settings`, snake_case
  fields, `load_settings()` reads `os.environ.get(...)`. Add APNS_* the same way.
- **API auth dep**: `from webapp.auth.dependencies import require_auth_api`
  (`(request) -> User`, raises `HTTPException(401)`; reads `request.state.user`).
  HTML equivalent is `require_auth` (redirects) — do not use for JSON.
- **Credentials**: `webapp/auth/users.py:178`
  `authenticate(email, password) -> Optional[User]` (already extracted; reuse).
- **Sessions** (`webapp/auth/sessions.py`): `create_session(user_id, *, user_agent=None, ip_address=None) -> Session`;
  `destroy_session(session_id)`; `destroy_all_sessions_for_user(user_id)`.
  Cookie name `case_repo_session`; flags HttpOnly, SameSite=lax,
  secure=`WEBAPP_SECURE_COOKIES`, path=/, max_age=2_592_000.
  Use `attach_session_cookie(response, session)` / `clear_session_cookie(response)` —
  do not hand-roll `set_cookie`.
- **DB idiom** (sync, psycopg3): `with get_pool().connection() as conn: with conn.cursor(row_factory=dict_row) as cur: cur.execute(sql, params)`.
- **practice_sessions** cols: participants `interviewer_id`, `candidate_id`;
  `scheduled_at timestamptz`; `state` in
  ('scheduled','lobby','live','debrief','finalized','aborted'). `users` PK = `id`.
  → Migration 013 `REFERENCES users(id)` is correct as written.
- **Router mount** (`webapp/main.py:~129`): `app.include_router(module.router)`,
  no prefix arg; routers carry full paths. Proposals router =
  `APIRouter(tags=["proposals"])`. Mount `api_v1.router` the same way.
- **CSRF**: `webapp/csrf.py require_same_origin(request)` — **returns (allows)
  when the `Origin` header is absent**, 403s only on a mismatching/`null`
  Origin. Native URLSession sends no Origin ⇒ passes. Add
  `Depends(require_same_origin)` to new `/api/v1` mutating routes for browser
  defense-in-depth; native is unaffected.

## Corrections to the plan (placeholder → real)

- **C1 — Task 7 case fields.** `search_cases(filters, *, limit=100) -> (list[dict], total)`.
  Real dict keys: `id, case_title, source_school, source_year, industry,
  case_type, difficulty, difficulty_score, firm, page_count, pdf_path`,
  plus `industry_display`. There is **no** `title`, `school`, or `usefulness_pct`
  in this output, and **no** `preview_urls`. The `/api/v1/cases` contract uses
  these real keys verbatim (iOS `CaseSummary`/`CaseDetail` must match). If a
  usefulness % or preview URLs are wanted, source them explicitly in Task 7
  (find the real provider) or omit from the v1 contract — do not invent keys.
  `SearchFilters(q, difficulty['Easy'|'Medium'|'Hard'], industry, case_type, school, include_duplicates=False)`.
- **C2 — Task 8 dashboard** has no single provider. Compose:
  `public_stats(user_id) -> {sessions_finalized, streak_weeks}`
  (`webapp/repositories/practice_sessions.py:193`) + soonest of
  `list_upcoming_for_user(user_id)` for `next_session`. Proposals inbox =
  `proposals_repo.inbox(user_id)`. Sessions: upcoming =
  `list_upcoming_for_user`, recent = `dashboard_repo.history(user_id)` (last 50).
- **C3 — accept already JSON.** `POST /api/proposals/{id}/accept` returns
  `{"accepted": true, "session_id": int, "session_url": str, "ics_url": str}`;
  decline returns `{"declined": true}`. No HTMX fragment — Task 8's negotiation
  worry is moot. Note: accept does **not** return `scheduled_at`; the iOS client
  already knows the accepted time (the proposal time it chose) → use that for the
  calendar event (Task 12).

- **C5 — User contract has no `name`.** The `User` dataclass (`webapp/auth/`)
  is `{id, email, email_verified_at, created_at, last_login_at}` — there is **no
  `name`**. But `users.display_name TEXT` exists (migration 011, defaulted to the
  email-prefix), and the whole codebase renders a person via
  `COALESCE(display_name, split_part(email::text,'@',1))`. So the locked iOS
  `User` contract (login + `/api/v1/me`, Task 6 → iOS Task 10) is
  **`{id: int, email: str, name: str}`** where `name` = that COALESCE. The auth
  endpoint must fetch it (a small `SELECT ... FROM users WHERE id=%s`; the User
  object doesn't carry display_name).

## Design decisions layered on the plan

- **D1 — ATS.** Sim hits `http://127.0.0.1:8077` (cleartext). Add
  `NSAppTransportSecurity → NSAllowsLocalNetworking = YES` via project.yml's
  Info.plist `properties` (nested dict, not an `INFOPLIST_KEY_*` scalar) in
  Task 9, or the first real request throws an ATS error.
- **D2 — Push authorization = FULL, not provisional.** Plan Task 13 said
  *provisional*; provisional pushes are delivered **silently** to Notification
  Center (no banner/sound) until the user promotes the app — which silently
  kills the knock/starting-soon liquidity that is P1's #1 goal. Instead:
  request **full** authorization (alert+sound+badge) in context right after
  first login, and set `"interruption-level": "time-sensitive"` in the aps dict
  for the **knock** (and starting-soon) pushes so they break through Focus/DND.
  Requires the **Time Sensitive Notifications** capability on the App ID +
  entitlement. (Owner-vetoable before Task 13; default stands until then.)

## Environment

- **E1** iOS simulator runtime was absent; iOS 26.5 runtime now INSTALLED
  (`com.apple.CoreSimulator.SimRuntime.iOS-26-5`). iOS Tasks 9–15 unblocked.
- **E2** RESOLVED: plan hardcodes `iPhone 16` (stale). Use
  `-destination 'platform=iOS Simulator,name=iPhone 17'` — the iOS 26.5 runtime
  auto-created iPhone 17 / 17 Pro / 17e / Air devices. Update Task 9's build/test
  commands to `iPhone 17`.

## Manual (Thomas — Apple Developer portal; not blocking Tasks 1–14)

1. App ID `studio.ogee.caseroom` + **Push Notifications** capability
   (+ **Time Sensitive Notifications** if keeping D2).
2. APNs Auth Key (.p8); record Key ID + Team ID.
3. Into `.env` (gitignored): `APNS_KEY_PATH`, `APNS_KEY_ID`, `APNS_TEAM_ID`,
   `APNS_BUNDLE_ID=studio.ogee.caseroom`, `APNS_USE_SANDBOX=1`. `.p8` never committed.
