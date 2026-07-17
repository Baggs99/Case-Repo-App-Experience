-- ============================================================================
-- 025 — Guest interviewer identity (roadmap §B2, spec §6.2)
-- ----------------------------------------------------------------------------
-- Apply with:  psql -d <db> -v ON_ERROR_STOP=1 -f db/migrations/025_guest_users.sql
-- Idempotent:  ADD COLUMN IF NOT EXISTS; DROP NOT NULL is a no-op when already
--              nullable; DROP CONSTRAINT IF EXISTS + re-ADD.
--
-- A guest is a real users row (is_guest=TRUE) with NULL email/password so every
-- FK (practice_sessions.interviewer_id/candidate_id, feedback, recordings)
-- keeps working. Upgrade (B2 §upgrade) flips is_guest→FALSE and stamps a real
-- email/password.
--
-- MERGE NOTE (B2×B5): B5's migration 022 dropped the hardcoded email-domain
-- CHECK — domain policy lives in the application against the schools registry
-- (a CHECK cannot query it, and hardcoding domains defeats the expandable
-- registry). The only shape rule the schema still owns: non-guests must have
-- an email; guests may not have NULL-shaped privileges beyond that.
-- ============================================================================

ALTER TABLE users ADD COLUMN IF NOT EXISTS is_guest BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE users ALTER COLUMN email DROP NOT NULL;
ALTER TABLE users ALTER COLUMN password_hash DROP NOT NULL;

ALTER TABLE users DROP CONSTRAINT IF EXISTS users_email_allowed;
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_guest_email_shape;
ALTER TABLE users ADD CONSTRAINT users_guest_email_shape CHECK (
    is_guest OR email IS NOT NULL
);
