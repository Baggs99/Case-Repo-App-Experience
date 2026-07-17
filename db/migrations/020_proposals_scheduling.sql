-- ============================================================================
-- 020 — Scheduling core: the proposal primitive (roadmap §B1, spec §5.2/A3)
-- ----------------------------------------------------------------------------
-- Apply with:  psql -d <db> -v ON_ERROR_STOP=1 -f db/migrations/020_proposals_scheduling.sql
-- Idempotent:  safe to re-run (DROP NOT NULL is a no-op if already nullable;
--              ADD COLUMN IF NOT EXISTS; DROP CONSTRAINT IF EXISTS + re-ADD).
--
-- case_id NULL = "interviewer decides" (case chosen later in negotiation, B3).
-- to_user_id NULL = open "send a link" proposal, claimed by claim_token.
-- counter_* = one-round "Suggest new time" (spec §5.2); state 'countered'.
-- ============================================================================

ALTER TABLE proposals ALTER COLUMN case_id DROP NOT NULL;
ALTER TABLE proposals ALTER COLUMN to_user_id DROP NOT NULL;

ALTER TABLE proposals ADD COLUMN IF NOT EXISTS claim_token TEXT;
ALTER TABLE proposals ADD COLUMN IF NOT EXISTS counter_times_json JSONB;
ALTER TABLE proposals ADD COLUMN IF NOT EXISTS counter_by INTEGER REFERENCES users(id);
ALTER TABLE proposals ADD COLUMN IF NOT EXISTS countered_at TIMESTAMPTZ;

-- UNIQUE-when-present: many NULLs allowed, each real token unique.
CREATE UNIQUE INDEX IF NOT EXISTS idx_proposals_claim_token
    ON proposals (claim_token) WHERE claim_token IS NOT NULL;

-- State CHECK gains 'countered'. Drop the auto-named inline CHECK, re-add named.
ALTER TABLE proposals DROP CONSTRAINT IF EXISTS proposals_state_check;
ALTER TABLE proposals ADD CONSTRAINT proposals_state_check
    CHECK (state IN ('pending', 'accepted', 'declined', 'expired', 'countered'));
