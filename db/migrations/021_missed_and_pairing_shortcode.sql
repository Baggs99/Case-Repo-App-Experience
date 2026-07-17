-- ============================================================================
-- 021 — 'missed' session state + pairing short-codes (roadmap §B1, spec §8/A3)
-- ----------------------------------------------------------------------------
-- Apply with:  psql -d <db> -v ON_ERROR_STOP=1 -f db/migrations/021_missed_and_pairing_shortcode.sql
-- Idempotent:  DROP CONSTRAINT IF EXISTS + re-ADD; DROP NOT NULL no-op; ADD
--              COLUMN IF NOT EXISTS; CREATE UNIQUE INDEX IF NOT EXISTS.
--
-- 'missed' = accepted session never joined by start+60min (A3), distinct from
-- 'aborted' (the 6-h stale backstop). pairing_tokens.case_id NULL = case chosen
-- in negotiation (B3); short_code = 6-char manual pairing fallback (spec §8).
-- ============================================================================

ALTER TABLE practice_sessions DROP CONSTRAINT IF EXISTS practice_sessions_state_check;
ALTER TABLE practice_sessions ADD CONSTRAINT practice_sessions_state_check
    CHECK (state IN ('scheduled', 'lobby', 'live', 'debrief', 'finalized', 'aborted', 'missed'));

ALTER TABLE pairing_tokens ALTER COLUMN case_id DROP NOT NULL;
ALTER TABLE pairing_tokens ADD COLUMN IF NOT EXISTS short_code TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_pairing_tokens_short_code
    ON pairing_tokens (short_code) WHERE short_code IS NOT NULL;
