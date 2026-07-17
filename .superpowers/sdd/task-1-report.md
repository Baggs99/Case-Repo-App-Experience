# Task 1 Report — Migrations 020 & 021 (schema)

**Status:** DONE
**Branch:** bgap/b1-scheduling
**Commit SHA:** 6a72e75

## Files created
- `db/migrations/020_proposals_scheduling.sql` — proposals nullable case_id/to_user_id, claim_token, counter_* cols, partial unique claim_token index, `'countered'` state.
- `db/migrations/021_missed_and_pairing_shortcode.sql` — practice_sessions `'missed'` state, pairing_tokens nullable case_id + short_code, partial unique short_code index.

SQL is verbatim from the plan (Task 1 Steps 1-2); no alterations.

## Step 3 — Apply + idempotency re-run

Command:
```
psql -d caserepo_bgap_b1 -v ON_ERROR_STOP=1 -f db/migrations/020_proposals_scheduling.sql
psql -d caserepo_bgap_b1 -v ON_ERROR_STOP=1 -f db/migrations/021_missed_and_pairing_shortcode.sql
# then re-run both (idempotency)
```

Run 1: all `ALTER TABLE` / `CREATE INDEX`, no ERROR.
Run 2 (idempotency): no ERROR lines. Emitted only:
```
NOTICE:  column "claim_token" of relation "proposals" already exists, skipping
NOTICE:  column "counter_times_json" of relation "proposals" already exists, skipping
NOTICE:  column "counter_by" of relation "proposals" already exists, skipping
NOTICE:  column "countered_at" of relation "proposals" already exists, skipping
NOTICE:  relation "idx_proposals_claim_token" already exists, skipping
NOTICE:  column "short_code" of relation "pairing_tokens" already exists, skipping
NOTICE:  relation "idx_pairing_tokens_short_code" already exists, skipping
```
plus `ALTER TABLE` / `CREATE INDEX` lines. DROP NOT NULL and DROP CONSTRAINT IF EXISTS + re-ADD are no-op-clean on re-run. Idempotency confirmed.

## Step 4 — Schema-shape assertions

| Assertion | Result |
|---|---|
| proposals.case_id nullable | `YES` |
| proposals.to_user_id nullable | `YES` |
| proposals_state_check includes 'countered' | YES — `CHECK ((state = ANY (ARRAY['pending','accepted','declined','expired','countered'])))` |
| practice_sessions_state_check includes 'missed' | YES — `CHECK ((state = ANY (ARRAY['scheduled','lobby','live','debrief','finalized','aborted','missed'])))` |
| proposals new columns present | claim_token (text), counter_times_json (jsonb), counter_by (integer, FK users), countered_at (timestamptz) |
| pairing_tokens.case_id nullable | `YES` |
| pairing_tokens.short_code present | YES (text) |
| idx_proposals_claim_token (partial unique) | present — `UNIQUE btree (claim_token) WHERE claim_token IS NOT NULL` |
| idx_pairing_tokens_short_code (partial unique) | present — `UNIQUE btree (short_code) WHERE short_code IS NOT NULL` |

## Step 5 — Commit
```
git add db/migrations/020_proposals_scheduling.sql db/migrations/021_missed_and_pairing_shortcode.sql
git commit -m "Add migrations 020/021: proposal scheduling cols, missed state, pairing short-code"
```
Result: `[bgap/b1-scheduling 6a72e75]` — 2 files changed, 49 insertions. `git status --short` clean afterward (nothing else staged/committed).

## Concerns
None. All Step 3-4 checks passed on first attempt; no other files touched; db/schema.sql and docs untouched per Global Constraints.
