# INTEGRATION.md — CaseRoom × Case-Repo-App-Experience

How the CaseRoom spec (`docs/caseroom-spec.md`) maps onto this repo's actual
architecture. The spec was written blind against an assumed PHP/MySQL/Hostinger
stack; this document is the binding adaptation record (spec Phase 1, T1.1).
Where this file and the spec disagree, **this file wins** — each divergence is
logged as a deviation below.

Updated: 2026-07-11 · Branch: `feature/caseroom`

---

## 1. Stack inventory (what actually exists)

| Concern | Reality |
|---|---|
| Language / framework | Python 3.13 · FastAPI + Jinja2 templates, vanilla JS, some HTMX |
| Database | PostgreSQL (15+ required — `UNIQUE NULLS NOT DISTINCT` in schema.sql), psycopg 3 pool via `webapp/db.py` |
| Auth | Complete in `webapp/auth/`: signup w/ school-domain allowlist (yale.edu, umich.edu, one Booth guest), email verification, password reset, argon2id hashes, **server-side sessions** (cookie `case_repo_session`, HttpOnly, SameSite=Lax, 30-day) |
| Auth helpers | `Depends(require_auth)` (pages, redirects to login), `Depends(require_auth_api)` (JSON 401), `require_verified_user`, `require_admin` (404 for non-admins) — `webapp/auth/dependencies.py` |
| SQL convention | All SQL in `webapp/repositories/*.py`, parameterized psycopg, `dict_row`; routes are orchestration only |
| Routing convention | One `APIRouter` per domain in `webapp/routes/`, pydantic request bodies, `/api/...` for JSON, bare paths for pages |
| Templates | `webapp/templates/*.html`, `base.html` parent, `current_user` injected by `webapp/templating.py` |
| Config | Env vars via `.env` (gitignored ✓) loaded in `webapp/main.py`; typed access through `webapp/settings.py` `Settings` dataclass |
| Storage | `pipeline/storage/` abstraction: local / S3 / R2. Case PDFs in R2 (or local dir in dev). Per-page preview JPEGs, optionally on a **public** CDN base URL with opaque slugs |
| Mail | Resend (`webapp/auth/email_sender.py`); dev mode writes to `output/emails/` |
| Migrations | Plain SQL in `db/migrations/NNN_*.sql`, all idempotent; `db/schema.sql` is the current base (includes 002–007, 009, 010; **not** 008). Runner: `python main.py apply-sql-migration <path>` or `psql -f` |
| Case data | 467 cases imported by the PyMuPDF pipeline: `case_title`, `source_school`, `source_year`, `industry`, `case_type`, `difficulty` (Easy/Medium/Hard) + `difficulty_score` (0–10), `firm`, `interviewer_led`, `page_count`, `pdf_path`, votes (usefulness %), access audit log |
| Tests | stdlib `unittest` in `tests/`, heavy use of mocks, no pytest dependency |
| Deploy | **Unknown from repo** (no Dockerfile/Procfile; gunicorn in requirements). Prod host, deploy flow, and whether `main` auto-deploys need answers from the repo owner. All CaseRoom work stays on `feature/caseroom` regardless |

## 2. Architecture adaptation (supersedes spec §1)

**One app, not two hosts.** CaseRoom lands entirely inside the existing FastAPI
app. The spec's separate media plane collapses:

- **Signaling** = a FastAPI WebSocket route (`/ws/session/{id}`), authenticated
  by the same session cookie on the WS handshake. The spec's HMAC token bridge
  (§4.1) and standalone Node `ws` service (§4.2's host) are **dropped** — same
  process means same auth, no shared secret, no cross-host trust.
  The §4.2 message protocol itself (hello/knock/admit/sdp/ice/bye/heartbeat,
  2-peer + role enforcement, metadata-only logging) is kept verbatim.
- **Constraint inherited by deploy:** the signaling peer map is in-process
  memory ⇒ the app must run as a **single worker process**
  (`uvicorn webapp.main:app` or `gunicorn -k uvicorn.workers.UvicornWorker -w 1`).
  Multi-worker deploys would split the two peers across processes. Fine at
  club scale; revisit only if load demands it (then: dedicated signaling
  worker or a pub/sub backplane).
- **TURN** is the only remaining non-app infrastructure and is **deferred**
  (assumption A2): the join-config endpoint returns `ICE_SERVERS_JSON` from
  env — STUN-only in dev. Decide managed TURN (Cloudflare, fits their existing
  Cloudflare use) vs. self-hosted coturn before real launch.
- **Exhibit rendering** happens **server-side with PyMuPDF** (already a core
  dependency) + Pillow WebP encode, then AES-256-GCM encryption. The spec's
  client-side pdf.js rendering existed only to avoid server binaries on shared
  hosting; that constraint is gone, so pdf.js is not vendored at all. The
  interviewer's in-call full-PDF view reuses the existing inline PDF route
  (`/api/cases/{id}/open-pdf`) in an embed.
- **.ics invites** go through the existing Resend path as attachments.
- **Recordings** go through the existing storage abstraction under a
  **private** prefix (`recordings/`), never the public preview bucket/base URL.

## 3. Table & column mappings

New tables are created by `db/migrations/011_caseroom.sql`. Repo-owned tables
are reused, never restructured.

| Spec (§3) | Here | Notes |
|---|---|---|
| `users` | reuse `users` | 011 adds nullable `display_name` (backfilled from email local-part; UI fallback = local-part). `id SERIAL`, `email CITEXT` |
| `schools` + `school_id` hooks | **omitted** | Deviation DV-1 below |
| `cases` | reuse `cases` | `title→case_title`, `source→source_school + source_year`, `sector→industry`, `difficulty 1–5 → difficulty (Easy/Medium/Hard) + difficulty_score (0–10)`. No `status`/`created_by` — library is operator-published (see DV-2). Browse excludes `is_duplicate_case` |
| `exhibits` | `case_exhibits` | Matches repo's `case_*` prefix convention; + `created_by`, `created_at` |
| `sessions` | `practice_sessions` | **Renamed** — `sessions` already means auth sessions here |
| `reveals` | `reveals` | FK → `practice_sessions`, `case_exhibits` |
| `feedback` | `feedback` | `grade NUMERIC(3,1) CHECK 0–5` (assumption A8) |
| `queue_want` / `queue_give` | same | unchanged |
| `burned` | `burned` | unchanged |
| `proposals` | `proposals` | unchanged shape |
| `recordings` | `recordings` | `bytes BIGINT` |
| `rubric_templates` | `rubric_templates` | `items_json JSONB` |

Postgres idiom throughout: `SERIAL` PKs, `TIMESTAMPTZ`, `JSONB`, `TEXT` +
`CHECK` constraints instead of MySQL `ENUM` (matches `difficulty`,
`vote_type`, `kind` precedent), `BYTEA` for key/IV.

## 4. Deviations from the spec (logged per spec §0 / rule 5)

- **DV-1 — no `schools` table, no `school_id` columns.** The spec wanted
  nullable `school_id` as a future-lock hook. Here, school identity is already
  fully derivable from the email-domain allowlist (`@yale.edu` / `@umich.edu`),
  so the hook adds schema for no capability. If formal school entities are
  ever needed, one additive migration does it then.
- **DV-2 — no user PDF-upload authoring in v1.** Spec Phase 5 assumed an empty
  system needing user-uploaded cases. The library already has 467 cases with
  page previews. Authoring v1 = *mark exhibit pages on an existing case*
  (page-picker over existing previews → server renders selected pages at high
  res → encrypts). New-case upload is out of scope (decision recorded in chat,
  2026-07-11).
- **DV-3 — HMAC join-token replaced by cookie-authenticated WS** (see §2).
  `POST /api/sessions/{id}/join-token` becomes `GET /api/practice/{id}/join-config`
  returning `{ws_path, ice_servers}` only.
- **DV-4 — reveal fallback trigger.** Spec §4.4(5) referenced a signaling
  "reveal notification" that §4.2's protocol doesn't define. Fix: while the
  `ctrl` DataChannel is not open, the candidate polls
  `GET /api/practice/{id}/reveals` every 5 s and reconciles (same reconcile
  path as reconnect).
- **DV-5 — content secrecy scope (INV-6).** Every authed user can already
  browse/download every case PDF, and proposals display case titles. Absolute
  pre-session secrecy is therefore impossible; it is enforced **within the
  call flow** (encrypted preload, key-on-reveal, no plaintext pre-reveal), and
  pre-reading remains honor-system — which is exactly what `burned` models.
  No *new* leak paths may be added (exhibit blobs/keys and recordings stay
  role-gated per INV-3).
- **DV-6 — "highest-rated" recommendation (§4.8 rule 1)** maps to the existing
  usefulness % from `case_votes` (spec's schema had no rating source).
- **DV-7 — difficulty ladder (§4.8 rule 2)** walks Easy → Medium → Hard
  (repo's categorical difficulty), tie-broken by `difficulty_score`.
- **DV-8 — CSRF.** Repo idiom is SameSite=Lax cookies, no tokens. CaseRoom's
  state-changing endpoints add an Origin-check dependency
  (`webapp/csrf.py::require_same_origin`): if an `Origin` header is present it
  must match the request host; absent Origin (curl, same-origin GET) passes.
  Documented rationale in the module docstring.
- **DV-9 — new Python dependency `cryptography`** for AES-256-GCM exhibit
  encryption (stdlib has no AES; this is the standard, boring choice).
  Justified in the commit adding it.
- **DV-10 — spec phases 2/3 shrink.** Auth (T2.1) exists; Node signal service,
  its `node --test` suite, and the VPS runbook (T3.1–T3.4) are replaced by the
  in-app WS route + `unittest` coverage. coturn config ships later only if the
  self-hosted TURN option is chosen.
- **DV-11 — API status codes.** Spec P2's done-when says wrong-actor and
  illegal transitions both return 403. Implemented with more precise
  semantics: **404** for non-participants (session existence undisclosed —
  same philosophy as `require_admin`'s 404), **403** for a participant acting
  outside their role, **409** for illegal state edges and unmet consent gates.
- **DV-12 — exhibit authoring adaptations (Phase 5).** (a) The repo's Storage
  abstraction is read-only, so encrypted exhibit blobs use plain file I/O
  under gitignored `EXHIBITS_DIR` (default `output/exhibits/`); prod
  placement is part of O1. (b) Community authoring: any **verified** user may
  author a library case's exhibit set (`created_by` recorded, admins can
  re-author); no draft/publish gate — exhibits are optional and sessions are
  never blocked on them.
- **DV-13 — exhibit sets freeze once revealed (found in Phase 6).**
  `reveals.exhibit_id` references `case_exhibits`, and the reveal timeline is
  part of the permanent session record (T6.4 debrief view, Phase 7 feedback).
  DV-12b replace-authoring would delete those referenced rows — so replacing
  a case's exhibit set returns **409** once any reveal references it.
  Iterating on a much-practiced case's exhibits later would need a schema
  evolution (snapshot `idx` into reveals + cascade) — an owner call, not
  needed at v1.

## 5. Assumptions (recorded per operating rules; flag to overturn)

- **A1** Session's room = **interviewer's** room; admit power follows the
  interviewer *role* (spec mixed "owner" and "interviewer").
- **A2** TURN deferred; `ICE_SERVERS_JSON` env, STUN-only dev (see §2).
- **A3** Rubric template on proposal-accept = case's own template if one
  exists, else the seeded generic; interviewer may swap before `live`.
- **A4** Stale-session sweep on page load (no cron): pre-debrief sessions
  idle > 6 h → `aborted`.
- **A5** Grades normalized to 0–5.0.
- **A6** `POST /api/proposals` (and session creation) reject a case already
  burned for the would-be candidate.
- **A7** Admit/consent ordering: interviewer's Admit click first calls
  `POST /state → live` (server validates both consents), and only on 200
  sends `admit` over the WS.
- **A8** "Streak" (public room stat) = consecutive calendar weeks with ≥ 1
  finalized session.
- **A9** Recording-upload failure does not block the call; the recording row
  simply stays `completed=0` and the debrief view shows it as unavailable.

## 6. Environment / config additions

Read via `webapp/settings.py` (extend `Settings` in Phase 2). All optional
with safe defaults except where noted:

```
ICE_SERVERS_JSON      # JSON array for RTCPeerConnection.iceServers
                      # default: [{"urls":["stun:stun.l.google.com:19302"]}]
MAX_EXHIBIT_MB=2      # rendered exhibit image ceiling (INV-5)
MAX_REC_CHUNK_MB=8    # one recording chunk (INV-5)
MAX_REC_TOTAL_MB=150  # per-participant per-session recording cap (INV-5)
RECORDINGS_PREFIX=recordings/   # private storage prefix — never the public preview base
EXHIBITS_PREFIX=exhibits/       # encrypted blobs prefix — same rule
```

Secrets stay in `.env` (gitignored, verified). No new shared secrets are
needed until/unless self-hosted coturn is chosen (then `TURN_STATIC_SECRET`).

## 7. Local dev environment (macOS, this machine)

```
brew install postgresql@17 && brew services start postgresql@17
createdb caserepo_dev
psql -d caserepo_dev -f db/schema.sql
for f in db/migrations/0*.sql; do psql -d caserepo_dev -v ON_ERROR_STOP=1 -f "$f"; done   # all idempotent
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
echo 'DATABASE_URL=postgresql://localhost/caserepo_dev' > .env
python main.py serve
```

Dev has no R2 credentials and no real case PDFs; storage falls back to local
paths, and later phases seed dummy cases/PDFs for flows that need bytes.

## 8. Open items for the repo owner

- **O1** Where does prod run, what's the deploy flow, does `main` auto-deploy?
  (Also gates the single-worker signaling constraint, §2.)
- **O2** TURN choice before launch: Cloudflare's TURN service (fits existing
  Cloudflare footprint, no server) vs. coturn on a ~€4/mo VPS.
- **O3** Final recording-consent wording (spec D3 — some US states require
  all-party consent).
- **O4** Casebook copyright / distribution posture (spec D4) — unchanged by
  this build.
