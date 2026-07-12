-- ============================================================================
-- 012 — practice_sessions.state_changed_at
-- ----------------------------------------------------------------------------
-- Apply with:   python main.py apply-sql-migration db/migrations/012_practice_state_changed_at.sql
-- Idempotent:   safe to re-run.
--
-- Every state transition stamps this column. Needed so the stale-session
-- sweep (INTEGRATION.md A4) can abort sessions stuck in lobby/live for > 6 h
-- without misjudging sessions that were merely *created* long ago —
-- created_at says nothing about when a session entered its current state.
-- ============================================================================

ALTER TABLE practice_sessions
    ADD COLUMN IF NOT EXISTS state_changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
