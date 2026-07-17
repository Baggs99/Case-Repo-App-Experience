# Phase B5 Report — Identity, Profile, Onboarding

**Status:** DONE
**Branch:** `bgap/b5-identity` · **Head SHA:** `4be7f9f`
**Worktree:** `/Users/thomaskgould/dev/bgap-b5` · **DB used:** `caserepo_bgap_b5`
**Suite:** baseline 360 passed / 0 failed → final **420 passed / 0 failed** (+60 net-new B5 tests; `test_auth_email_domains.py` was replaced, net 0).

Implements the B5 brief §6 and the RESOLVED owner decisions OD-B5-1 (build Google OAuth + LinkedIn OAuth + email/passcode OTP) and OD-B5-2 (registry-gated school-email sign-up). Deviations recorded as DV-B5-1 and DV-B5-2 (see the plan header). Plan: `docs/superpowers/plans/2026-07-17-bgap-b5-plan.md`. Ledger: `.superpowers/sdd/progress.md`. Per-task + whole-branch review diffs: `.superpowers/sdd/diffs/`.

---

## Tasks (each: fresh Opus implementer → diff → fresh Opus task-reviewer, all APPROVE)

| Task | Scope | Commit range | Review |
|---|---|---|---|
| 1 | Migrations 022/023/024 + schema test | `451913d..83f7da6` | APPROVE |
| 2 | Storage `write()` on ABC + Local + R2 | `c322094..f5c0e15` | APPROVE |
| 3 | Schools repo + registry-backed `validate_email` | `a0f25f9..fe1f03c` | APPROVE |
| 4 | Profile repository | `7b815bc..b5d8bfa` | APPROVE |
| 5 | Notification-settings repo + push choke point | `23b1b0e..5df69bb` | APPROVE |
| 6 | Profile / photo / settings routes | `b9686ad..50e8be3` (+ fix `0a21dbe`) | APPROVE (upload-size fix applied) |
| 7 | Email+passcode OTP | `58bd77f..1dfe849` | APPROVE |
| 8 | School-email sign-up gate | `eea26d4..7031f58` | APPROVE |
| 9 | OAuth core (OIDC) + user-linking helpers | `a588ba2..203bc01` | APPROVE |
| 10 | Google + LinkedIn OAuth browser routes | `643805f..8657cf3` (+ fix `0a19216`) | APPROVE (email_verified + secure-cookie fixes applied) |
| Final | Whole-branch review over `b0552de..HEAD` | fix `4be7f9f` | APPROVE (6 minors hardened, re-reviewed clean) |

Plan review: round 1 REQUEST_CHANGES (1 CRITICAL — OAuth account-linking must gate on `email_verified`; 2 IMPORTANT), fixed, round 2 APPROVE. Final whole-branch review: 0 CRITICAL / 0 IMPORTANT / 11 MINOR → 6 in-scope minors fixed in `4be7f9f`, re-reviewed clean; the rest are recorded under DEFERRED below.

---

## New endpoints

All `/api/v1` routes: auth = `require_auth_api` (401 JSON) unless noted; mutating routes carry `require_same_origin`. All verified by passing integration tests (TestClient).

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/api/v1/profile` | required | `{id,email,display_name,bio,linkedin_url,school,photo_url}`; school read-only |
| PUT | `/api/v1/profile` | required + same-origin | display_name ≤100, bio ≤2000, linkedin_url ≤300 + http(s) scheme (422 on violation) |
| POST | `/api/v1/profile/photo` | required + same-origin | multipart; whitelist jpeg/png/webp; 5 MB cap (pre-read `file.size` + bounded read); magic-byte sniff; key `avatars/{user.id}.{ext}` (IDOR-safe); writes via storage layer off the event loop |
| GET | `/api/v1/settings/notifications` | required | 5 bools |
| PUT | `/api/v1/settings/notifications` | required + same-origin | subset upsert → 5 bools |
| POST | `/api/v1/auth/otp/request` | same-origin (unauth) | **always 202 `{"status":"ok"}`** (no enumeration); code issued only for existing user or registry domain |
| POST | `/api/v1/auth/otp/verify` | same-origin (unauth) | 200 `{"user":{...}}` + session cookie, or 401; provisions a school user for a new registry email |
| POST | `/api/v1/signup/request` | same-origin (unauth) | **always 202 `{"status":"ok"}`**; registered domain → sign-up link via existing verification infra; else silent no-op |
| GET | `/auth/google` | browser | 302 to Google authorize (state+PKCE cookie); **503** when creds or `WEBAPP_SESSION_SECRET` absent |
| GET | `/auth/google/callback` | browser | RS256 id_token verify → session cookie → 302 `/`; error → `/login?oauth_error=...` |
| GET | `/auth/linkedin` | browser | mirror of google |
| GET | `/auth/linkedin/callback` | browser | mirror of google |

Registered additively in `webapp/main.py` (three `include_router` lines: `profile`, `onboarding`, `auth_oauth`).

## New migrations (022/023/024 — idempotent, applied and re-applied cleanly)

- **022** `db/migrations/022_identity_profile.sql`: `users` gains `bio`, `photo_key`, `linkedin_url`, `google_sub` (unique index), `linkedin_sub` (unique index), `school_id INTEGER` (FK added in 023); drops the hardcoded `users_email_allowed` CHECK; creates `login_otp_codes(id, email CITEXT, code_hash, expires_at, attempts, consumed_at, created_at)`.
- **023** `db/migrations/023_schools_registry.sql`: creates `schools(id, name, domain UNIQUE, created_at)`, seeds `yale.edu` / `umich.edu` / `chicagobooth.edu`, adds the `users_school_id_fkey` FK (guarded `DO` block — DV-B5-2 ordering), backfills `users.school_id` by email domain (NULL-only).
- **024** `db/migrations/024_notification_settings.sql`: `notification_settings(user_id PK/FK, proposals, session_reminders, feedback, free_now, community BOOL NOT NULL DEFAULT TRUE)`.

## Push notification category mapping (B6 depends on this — MANDATED report deliverable)

The choke point is `push_to_user(user_id, *, title, body, data=None, interruption_level=None, category: str | None = None)` in `webapp/push/events.py`. When `category` is set and disabled for the user it returns without sending; `category=None` (all existing callers) is never filtered; a settings-lookup DB error **fails open** (sends anyway). Categories = the 5 `notification_settings` columns:

| category | meaning | consulted by (wiring status) |
|---|---|---|
| `proposals` | proposal invites / counters | B1/B3 (wire when their senders pass the category) |
| `session_reminders` | starting-soon / session lifecycle (`webapp/push/starting_soon.py`) | B1/B7 |
| `feedback` | feedback finalized / recap | B3 |
| `free_now` | free-now instant match (`api_v1.py` toggle) | not yet passed a category |
| `community` | connection requests, group invites | **B6 — the one category honored end-to-end within this wave** |

Within B5 the table + endpoints are fully functional; the choke point honors any category passed. Existing senders were intentionally left untouched (editing B1's `starting_soon.py` / shared `api_v1.py` push calls is out of B5's named scope), so B6 should pass `category="community"` and other phases wire their categories.

## Interfaces delivered (later phases build against these — exact signatures)

Schools / school binding (B6 leaderboards/groups):
- `webapp/repositories/schools.py`: `get_school_by_domain(domain) -> Optional[dict]` (`{id,name,domain}`); `get_school_by_id(school_id) -> Optional[dict]`; `domain_is_registered(domain) -> bool`.
- `users.school_id` column (FK → schools), backfilled for existing users.
- `webapp/auth/users.py`: `validate_email(email) -> str` (registry-backed); `domain_of(email) -> str`; `school_id_for_email(email) -> Optional[int]`.

Profile (B6 profiles/forum cards):
- `users.photo_key` / `bio` / `linkedin_url` columns.
- `webapp/repositories/profile.py`: `get_profile(user_id) -> Optional[dict]`; `update_profile(user_id, *, display_name, bio, linkedin_url) -> dict`; `set_photo_key(user_id, photo_key) -> None`.
- `pipeline.storage.Storage.write(key, data: bytes, *, content_type: str) -> None` (Local + R2).

Notifications (B6 community pushes):
- `webapp/repositories/notification_settings.py`: `CATEGORIES`; `get_settings(user_id) -> dict`; `update_settings(user_id, **flags) -> dict`; `notifications_allowed(user_id, category) -> bool` (fail-open on unknown category).
- `push_to_user(..., category=None)` choke point (above).

Identity / auth (session cookies identical to password login — no downstream changes needed):
- `webapp/auth/users.py`: `create_school_user(email, *, display_name=None) -> User` (unusable random password + `school_id` stamped); `get_or_create_school_user(email, *, display_name=None) -> User`; `get_user_by_oauth_sub(provider, sub) -> Optional[User]`; `link_oauth_sub(user_id, provider, sub) -> None`; `import_oauth_name(user_id, name) -> None`.
- `webapp/auth/otp.py`: `request_otp(email) -> bool`; `verify_otp(email, code) -> Optional[int]`.
- `webapp/auth/oauth.py`: `provider_config(provider) -> Optional[ProviderConfig]`; `make_pkce()`; `authorize_url(...)`; async `exchange_code(...)`; async `fetch_jwks(...)`; `verify_id_token(provider, id_token, jwks, *, client_id, nonce=None) -> dict`; `identity_from_claims(claims) -> OAuthIdentity`; `OAuthError`.

## Security posture (§2, verified at review)

- Parameterized SQL only across all new code; the single f-string column name (OAuth-sub) comes from the fixed `_OAUTH_SUB_COLUMNS` whitelist, values always `%s`.
- No user enumeration: `otp/request` and `signup/request` return identical `202 {"status":"ok"}` on every path; `otp/verify` returns identical 401 for bad-code and no-row.
- OTP codes SHA-256 hashed at rest, constant-time compared, 10-min expiry, ≤3 attempts (checked before compare), newest-code-only, `FOR UPDATE` locked.
- OAuth `email_verified` gate precedes both link-by-email and create paths; `_coerce_bool` neutralizes the string-`"false"` provider quirk (would otherwise defeat the gate); OAuth state cookie fails closed (no `WEBAPP_SESSION_SECRET` → 503, HMAC-signed, httponly, samesite=lax, secure in prod, 10-min TTL).
- Photo key derived from the authenticated `user.id` (IDOR-safe, tested); content-type whitelist + magic-byte sniff + 5 MB cap enforced server-side with a bounded read.
- Existing seeded users a/b/c@yale.edu keep working with unchanged passwords (`authenticate`/`password_hash` untouched; migration 023 only backfills `school_id`).
- No secrets committed (`.env` gitignored and untracked; test credentials are obvious fakes like `test-client-id`); nothing hard-requires live OAuth creds (endpoints 503 in dev; all token exchange + JWKS mocked in tests).

---

## THOMAS MANUAL — enabling live OAuth (and prod email/storage)

Nothing below is required for tests or dev; the endpoints 503 cleanly until set. Put all secrets in the gitignored `.env` (never commit).

**Google (Google Cloud Console):**
1. APIs & Services → Credentials → **Create OAuth client ID** → Application type **Web application**.
2. Authorized redirect URIs: `https://<your-domain>/auth/google/callback` (add `http://localhost:8000/auth/google/callback` for local testing).
3. OAuth consent screen → scopes: `openid`, `email`, `profile`.
4. Env vars: `GOOGLE_CLIENT_ID=...`, `GOOGLE_CLIENT_SECRET=...`.

**LinkedIn (LinkedIn Developer Portal):**
1. Create app → **Products** → request **"Sign In with LinkedIn using OpenID Connect"**.
2. **Auth** tab → Authorized redirect URLs: `https://<your-domain>/auth/linkedin/callback`.
3. Env vars: `LINKEDIN_CLIENT_ID=...`, `LINKEDIN_CLIENT_SECRET=...`.
4. **Before going live:** verify LinkedIn's current OIDC discovery (issuer `https://www.linkedin.com/oauth`, JWKS `https://www.linkedin.com/oauth/openid/jwks`, token endpoint `https://www.linkedin.com/oauth/v2/accessToken`, and that PKCE is accepted) against `https://www.linkedin.com/oauth/.well-known/openid-configuration`, and confirm the `email_verified` claim (our `_coerce_bool` already handles the string form).

**Required for BOTH providers:**
- `WEBAPP_SESSION_SECRET=<long random string>` — the OAuth state-cookie signing key. **Without it the OAuth routes 503 even if client creds are set** (fail-closed by design). Generate e.g. `python -c "import secrets;print(secrets.token_urlsafe(48))"`.
- `WEBAPP_SECURE_COOKIES=true` in production (HTTPS) so session + state cookies are marked Secure.

**Real transactional email (OTP + sign-up links, existing Resend infra):**
- `EMAIL_BACKEND=resend`, `RESEND_API_KEY=re_...`, `EMAIL_FROM='myCase <noreply@yourdomain>'`. In dev the console backend writes emails to `output/emails/`.

**Avatar storage in prod:**
- `STORAGE_BACKEND=r2` plus `R2_BUCKET_NAME`, `R2_ENDPOINT`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` (same R2 layer that serves case PDFs). Dev uses local disk under `output/cases/avatars/`.

---

## DEFERRED / recommended follow-ups (all MINOR; none block merge)

- **Rate-limiting** on `/api/v1/auth/otp/request` and `/api/v1/signup/request` (email-bombing). Brute force is already mitigated (newest-code-only + 3-attempt cap); the timing side-channel only reveals "is a registered school domain," which is public. Recommend a per-email/IP throttle.
- **`login_otp_codes` reaping** — rows are never purged; add a periodic delete of expired/consumed rows (natural home: the existing 60-s background loop, which is B1's territory — coordinate).
- **Orphaned avatar object** when a user re-uploads with a different extension (`avatars/{id}.png` lingers when `photo_key` moves to `.jpg`). Storage cruft only.
- **`signup/request` provisions an unverified `users` row** before the link is clicked (forced by reusing the existing verification infra, whose token needs a `user_id`). Rows carry an unusable random password and `email_verified_at IS NULL`; the real owner can still claim the address. Differs from the OTP path, which defers row creation to verify.
- **Notification categories** other than `community` are not yet consulted by live senders (wired by B1/B3/B7 — see the mapping table).
- **Cosmetic:** `signup.html` / `base.html` still describe Chicago Booth as "invite-only," now inaccurate under the registry model (any `@chicagobooth.edu` is admitted). Templates are outside B5's code scope — flag for a copy pass.

## ESCALATIONS

None. No Fable/deep consults were used or required.

## Notes for the orchestrator before merging

- Expected merge conflicts: `webapp/main.py` (three additive `include_router` lines near the end of `create_app`) and possibly `webapp/auth/users.py` (additive functions). All B5 edits to shared files are additive.
- New env vars introduced (all optional, documented above): `WEBAPP_SESSION_SECRET`, `GOOGLE_CLIENT_ID/SECRET`, `LINKEDIN_CLIENT_ID/SECRET`. Fold these into `.env.example` / deployment secrets when convenient.
- Integration DB rebuild will pick up migrations 022/023/024; they are idempotent and do not touch other phases' assigned numbers.
- B6 consumes: `schools` + `users.school_id`, `users.photo_key/bio/linkedin_url` + profile repo, and the notification choke point (`push_to_user(..., category="community")`).
