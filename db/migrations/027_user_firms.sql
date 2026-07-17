-- ============================================================================
-- 027 — per-user firm tracking + post-deadline prompt state (roadmap §B7)
-- ----------------------------------------------------------------------------
-- Apply with:  psql -d <db> -v ON_ERROR_STOP=1 -f db/migrations/027_user_firms.sql
-- Idempotent:  CREATE TABLE IF NOT EXISTS.
--
-- status flow: 'tracking' (default) → Offer='offer' / No offer='rejected' /
-- Waiting='interviewed'(+snooze_until). "Didn't interview" DELETEs the row
-- (DV-B7-1: drops off the line). 'admitted' is a recordable status kept for
-- B6 (data only — nothing in B7 gates on it). snooze_until (DV-B7-2) both
-- re-asks Waiting in a week and throttles the auto deadline-prompt to weekly.
-- ============================================================================

CREATE TABLE IF NOT EXISTS user_firms (
    user_id             INTEGER     NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    firm_id             INTEGER     NOT NULL REFERENCES firms(id) ON DELETE CASCADE,
    added_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status              TEXT        NOT NULL DEFAULT 'tracking'
        CHECK (status IN ('tracking', 'interviewed', 'offer', 'rejected', 'admitted')),
    result_recorded_at  TIMESTAMPTZ,
    snooze_until        TIMESTAMPTZ,
    PRIMARY KEY (user_id, firm_id)
);
