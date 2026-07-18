# FE-F10 — Guest interviewer web console-lite — Phase Report

**Status: DONE** · Branch `fe/f10-guestweb` · cut at `ae46fed` · Head `316c5c9` ·
Date 2026-07-18 · Worktree `/Users/thomaskgould/dev/fe-f10` · DB `caserepo_fe_f10`

Delivered canvas 8a as vanilla server-rendered pages in `webapp/`: the
zero-chrome link-gate, the guest console-lite (clock, serif read-aloud, one
exhibit release, finalize driving the real session lifecycle), and the
post-session "keep it on a record?" → B2 account upgrade → "On the record."
No frameworks, no build step, no new migration. Every state-changing path
reuses B2's guest-aware, `require_same_origin`-guarded endpoints; every console
route is behind `require_session_participant`.

## Suite counts

| | Passed |
|---|---|
| Baseline (655 required bootstrap; seeded `caserepo_fe_f10`) | 655 |
| After F10 | **673** |

+18 net (all in `tests/test_f10_guest_web.py`). Command:
`.venv/bin/python -m pytest tests/ -q` → `673 passed`. iOS baseline not run
(not this phase's; parallel F9 owns iOS).

## Tasks (all reviewed by fresh Opus reviewers, fix loops closed)

| Task | Deliverable | Commit range | Review |
|---|---|---|---|
| Plan | plan + Opus plan-review (1 Critical lifecycle + I2/I3 + minors → revised) | fd35421..5aa48ae | revised, re-sound |
| 1 | Link-gate: `GET/POST /g/claim/{token}` + `get_open_by_claim_token` + `guest_gate.html` | 5aa48ae..2b9d0b3 | BOTH PASS |
| 2 | Console-lite: `GET /g/session/{id}` + lifecycle JS + `guest_console.html` | 2b9d0b3..77bf016 | BOTH PASS |
| 3 | Keep/upgrade/saved: `.../keep` `.../saved` + templates; folded M1/M2/M3 | 77bf016..7029c63 | BOTH PASS |
| — | Copy-honesty fixes (`/saved` gates on isGuest; keep kicker not "FEEDBACK SENT" for aborted/missed) | 7029c63..968e585 | task-review minors |
| — | Curl evidence (pages/flows/CSRF/IDOR/lifecycle) | 968e585..76ab0d5 | — |
| — | Whole-branch adversarial security review → test hardening (cross-origin 403, existing-guest re-claim 403) | 76ab0d5..HEAD | no Crit/Imp; 2 test locks added |

Ledger + diff packages + curl evidence under `.superpowers/sdd/f10/`.

## What was verified, and how

**pytest (18, hermetic, phase DB, per-test cleanup)** — link-gate render + 404
neutral gone-copy; unauth POST mints guest + 303 + Set-Cookie; scheduled-token
POST → 404 with NO orphan guest row; **cross-origin POST → 403 before any mint**;
**existing-guest re-claim → 403, nothing minted**; console render (with and
without exhibits — the dev case has none, exhibit row guarded); **IDOR: guest of
session A → 403 on session B**; real non-participant → 404; candidate-seat → 303
to authed call page; **full lifecycle** (guest consent→lobby, candidate consent,
guest live, reveal 200, debrief, finalize `grade=4.0`→`finalized`) then console
GET → 303 to `/keep`; keep pre-finalize → 303; keep post-finalize guest → upgrade
ask; upgrade with fresh yale email flips `is_guest=FALSE` → `/saved` "On the
record."; upgrade bad domain → 400; non-guest claimer → "Saved to your record.";
`?guest=1` → honest "Kept for now."; finalize response `grade == 4.0` (guards
DV-F10-3).

**curl vs the dev server (:8110)** — `.superpowers/sdd/f10/curl-evidence.txt`:
gate 200 + 8a markup; bogus token 404; cross-origin POST 403; same-origin unauth
POST 303 + `Set-Cookie: case_repo_session=…; HttpOnly; SameSite=lax` +
`Location: /g/session/347`; console 200 (`GUEST CONSOLE`/`READ ALOUD`/`End`);
lifecycle consent→lobby→consent→live→debrief→finalize all 200, `grade` in body
`4.0`; keep 200 (`FEEDBACK SENT — ALICE DEV HAS IT`/`Keep this session on a
record?`); upgrade 200 `{upgraded:true}`; saved 200 "On the record."; **real
foreign-session IDOR: guest2 → session 347 = 403**; upgraded/real non-participant
= 404; `?guest=1` = "Kept for now." Curl-created rows cleaned from the phase DB
afterward; server killed (port 8110 free).

**Security (whole-branch adversarial Opus review, security lens): no
Critical/Important exploitable defects.** CSRF (`require_same_origin` on the one
new POST; every fetch hits an already-guarded endpoint; no state-changing GET),
IDOR (`require_session_participant` everywhere; `role_of` exact-int match),
guest data exposure (boot dicts carry only participant-visible fields — zero
grades/diagnostics/recs/PII; public gate exposes only from_name+case_title,
identical neutral 404 for unknown/claimed/scheduled/wrong-role tokens; 192-bit
token), orphan-guest reap on every POST failure path, parameterized SQL, XSS
(autoescape + `|tojson` + `textContent`), role (gate SQL pins
`from_role='candidate'` → claimer is always interviewer; finalize/reveals
re-check interviewer), upgrade unchanged (B2's `require_guest`+same-origin).

## New endpoints (all in `webapp/routes/guest_web.py`; router additive in `main.py`)

| Method | Path | Auth / CSRF | Notes |
|---|---|---|---|
| GET | `/g/claim/{claim_token}` | public (token = capability) | Link-gate. 200 preview / 404 neutral. Exposes only from_name + case_title. |
| POST | `/g/claim/{claim_token}` | `require_same_origin` + `require_auth_or_mint_guest` | Claims via B2 `claim_proposal`; 303 → `/g/session/{id}`; reaps guest on any failure. |
| GET | `/g/session/{session_id}` | `require_session_participant` | Console-lite. interviewer seat only (candidate → 303 `/session/{id}`); finalized/aborted/missed → 303 `/keep`. |
| GET | `/g/session/{session_id}/keep` | `require_session_participant` | 8a gIsPost; guest → upgrade ask, real → "Saved to your record."; not-over → 303 back. |
| GET | `/g/session/{session_id}/saved` | `require_session_participant` | 8a gIsMade "On the record." / `?guest=1` honest "Kept for now." / still-guest bare = "Kept for now." |

No new upgrade route — the keep page posts to B2's existing
`POST /api/v1/auth/upgrade`. State transitions/reveals/finalize reuse the
existing `/api/practice/{id}/*` endpoints.

## Other files touched (additive)

- `webapp/repositories/proposals.py` — new read-only `get_open_by_claim_token`
  (parameterized; filters to instant + case-set + candidate-role + pending +
  unclaimed; empty-array `proposed_times_json` treated as "now", matching
  `sweep_expired`).
- `webapp/templating.py` — `render()` gains an optional `status_code` kwarg
  (default 200; every existing caller unchanged) so the gate can return 404/409.
- `webapp/main.py` — one import + one `include_router` line.
- New: `webapp/templates/guest_{gate,console,keep,saved}.html`,
  `webapp/static/js/caseroom/guest_console.js`.

## New migration

None. B2 (migration 025) shipped the guest schema; F10 needed no schema change.

## Deviations (documented, owner-relevant)

- **DV-F10-1 — read-aloud/guidance have no backing column.** Cases store content
  only as the PDF (`pdf_path`) + encrypted exhibits; there is no read-aloud/
  script/guidance text column. The console's READ ALOUD block renders case
  framing (title/type) + "read from the case pack" and links the case-pack PDF
  (B2 grants a guest access to ONLY its own session's case via
  `require_case_access`). The canvas persona read-aloud + "GUIDANCE — NOT READ
  ALOUD" hint text are preview data, dropped for live per the front-end §2 rule.
- **DV-F10-2 — upgrade requires a whitelisted school-domain email** (B2's
  `upgrade_guest` → `InvalidEmailDomain` 400). Canvas 8a says "school optional
  for interviewers," but B2 did not implement that and reports override briefs.
  F10 surfaces B2's 400 message inline rather than promising school-optional.
  **Owner call if guest interviewers should be allowed non-school emails at
  upgrade — that is a B-side change, not F10's to make.**
- **DV-F10-3 — guest finalize records ONE explicit 1–5 overall score.** Canvas
  8a's lite console has no 12-dim rubric (that is 8b's authed console); an empty
  rubric would compute grade 0.0 AND burn the case, silently failing the
  candidate. The End action captures one overall 1–5 (`FinalizeBody.grade`,
  `ge=0,le=5`) — never a silent 0.0. **Owner call if a guest-run session should
  score the candidate at all, or only send prose.** Currently it scores + burns
  like any finalized session (B2: "guests can interview / finalize works").

## Residual Minors (non-exploitable, from the adversarial review — not blocking)

- **Implied recording consent:** the console posts the interviewer's
  `consent:true` on "Continue as guest" with no explicit checkbox. Nothing
  records unilaterally (the candidate's own separate consent is still required
  by INV-10). Flag for product/legal if an explicit affirmation is wanted.
- **Redirect header copy:** the claim 303 copies all injected-Response headers
  (only a bodyless `content-length` in practice) — harmless, mirrors the
  existing `pair/claim` pattern.
- **`boot.caseType`** shows the real `cases.case_type` when set; the seeded dev
  case has none → falls back to "CASE" (cosmetic).

## DEFERRED

- Login variant of the guest gate (Design §6 "not yet designed"): "Log in" links
  to `/login?next=/g/claim/{token}`; a logged-in claimer is handled (real claim,
  "Saved to your record." — no upgrade ask), but the bespoke logged-in gate
  screen is out of scope per Decisions §6.
- QR / 6-char short-code web pairing gate (Design §6 "not yet designed") — F10
  scopes to the proposal claim-link path canvas 8a depicts.

## ESCALATIONS

None (no Fable consults). The two owner-gated product points (DV-F10-2 upgrade
school-domain requirement, DV-F10-3 whether/how a guest-run session scores the
candidate) ride this report to the orchestrator/Thomas.
