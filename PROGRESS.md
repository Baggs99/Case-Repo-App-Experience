# PROGRESS
Updated: 2026-07-11T21:45:00-04:00 · Branch: feature/caseroom

## Now
Phase 1 (discovery, foundations, schema) complete — next is Phase 2:
rooms + practice-session CRUD + state machine + consent gating +
join-config endpoint (see docs/caseroom-spec.md §6 P2 as amended by
INTEGRATION.md DV-3/DV-10).

## Done
- Repo access: accepted collaborator invite, cloned, write access confirmed
  — evidence: `gh repo view` → viewerPermission WRITE
- T1.1 INTEGRATION.md at repo root: stack inventory, table mappings,
  deviations DV-1..DV-10, assumptions A1..A9, open items O1..O4
- Spec copied into repo — docs/caseroom-spec.md
- T1.2 config: `.gitignore` already covers `.env` / `.env.*` / `.venv`
  (verified before first commit, INV-4); new env keys documented in
  INTEGRATION.md §6 — no new shared secrets needed (HMAC bridge dropped, DV-3)
- T1.3 db/migrations/011_caseroom.sql (Postgres): rooms, rubric_templates,
  case_exhibits, practice_sessions, reveals, feedback, queue_want,
  queue_give, burned, proposals, recordings + users.display_name backfill
  — evidence: applied twice to caserepo_dev, second pass all
  "already exists, skipping" NOTICEs, zero errors; `\dt` shows 18 tables
- Local dev DB: postgresql@17 via brew (running as service), caserepo_dev
  = schema.sql + migrations 002–011 — evidence: per-file OK log
- T1.4 helpers: webapp/exhibit_crypto.py (AES-256-GCM, WebCrypto-compatible
  tag layout), webapp/csrf.py (Origin guard, DV-8), webapp/upload_limits.py
  (recording-chunk INV-5 checks) + cryptography>=42 in requirements.txt
  — evidence: 25/25 unit tests OK (`python -m unittest` v-run),
  compileall clean, full venv install from requirements.txt exit 0

## Blocked / decisions needed
- O1 prod host / deploy flow / main auto-deploy? — recommended default:
  keep everything on feature/caseroom; owner merges (already the rule)
- O2 TURN provider before launch — recommended default: Cloudflare TURN
  (fits existing Cloudflare footprint); dev proceeds STUN-only either way
- O3 final consent copy (spec D3) — placeholder text ships meanwhile

## Environment warning — iCloud eviction (read before next session)
~/Documents is iCloud-synced with Optimize Mac Storage: macOS evicted repo
file contents ("dataless" flag) within the hour, which made every git
command hang on blocked content reads (.git pack files included). Worktree
re-hydrated via `brctl download`; .git stayed wedged, so Phase 1 was pushed
from a fresh clone and a healthy .git was swapped in (original preserved as
.git.icloud-wedged). Permanent fix is Thomas's call: move projects out of
iCloud-synced paths, disable Optimize Mac Storage, or Finder → "Keep
Downloaded" on the project folder. Until then, expect this to recur.

## Assumptions
- A1..A9 in INTEGRATION.md §5 (room = interviewer's; TURN deferred;
  rubric default = case's else generic; 6 h stale-session sweep; grades
  0–5; burned-case proposals rejected; state-before-admit ordering;
  streak = consecutive weeks; recording failure never blocks the call)
- Dev-only: local Postgres 17; no R2 creds locally — storage falls back
  to local paths; later phases seed dummy cases/PDFs where bytes matter
