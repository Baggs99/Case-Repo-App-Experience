-- ============================================================================
-- 025 — Guest interviewer identity (roadmap §B2, spec §6.2)
-- ----------------------------------------------------------------------------
-- Apply with:  psql -d <db> -v ON_ERROR_STOP=1 -f db/migrations/025_guest_users.sql
-- Idempotent:  ADD COLUMN IF NOT EXISTS; DROP NOT NULL is a no-op when already
--              nullable; DROP CONSTRAINT IF EXISTS + re-ADD.
--
-- A guest is a real users row (is_guest=TRUE) with NULL email/password so every
-- FK (practice_sessions.interviewer_id/candidate_id, feedback, recordings)
-- keeps working. The email-domain CHECK is relaxed for guests only; non-guest
-- rows still require a school-domain email (NOT NULL + suffix). Upgrade
-- (B2 §upgrade) flips is_guest→FALSE and stamps a real email/password.
-- ============================================================================

ALTER TABLE users ADD COLUMN IF NOT EXISTS is_guest BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE users ALTER COLUMN email DROP NOT NULL;
ALTER TABLE users ALTER COLUMN password_hash DROP NOT NULL;

-- Guest rows bypass the school-domain gate; non-guests must still carry a
-- non-null school-domain email. (email ILIKE NULL is unknown, which a CHECK
-- would treat as "not violated" — hence the explicit email IS NOT NULL arm.)
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_email_allowed;
ALTER TABLE users ADD CONSTRAINT users_email_allowed CHECK (
    is_guest
    OR (
        email IS NOT NULL AND (
            email ILIKE '%@yale.edu'
            OR email ILIKE '%@umich.edu'
            OR lower(email::text) = 'acannata@chicagobooth.edu'
        )
    )
);
