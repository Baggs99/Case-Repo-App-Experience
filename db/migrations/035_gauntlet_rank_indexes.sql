-- db/migrations/035_gauntlet_rank_indexes.sql
-- B8: indexes for the gauntlet rank/percentile queries. The daily board groups
-- today's submitters by (set_key, user_id) summing score; the per-user trend and
-- one-per-day guard filter (user_id, set_key). Both partial on gauntlet rows only.
CREATE INDEX IF NOT EXISTS idx_drill_attempts_setkey
    ON drill_attempts (set_key, user_id) WHERE set_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_drill_attempts_user_setkey
    ON drill_attempts (user_id, set_key) WHERE set_key IS NOT NULL;
