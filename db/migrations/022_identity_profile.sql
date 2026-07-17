-- 022_identity_profile.sql
-- Purpose: Identity/profile columns on users, drop the hardcoded email-domain
--          CHECK (validation moves to the registry-backed server layer), and add
--          the login_otp_codes table for email+passcode OTP (hashed at rest).
-- Idempotent: re-runnable via IF NOT EXISTS / DROP ... IF EXISTS guards.

ALTER TABLE users ADD COLUMN IF NOT EXISTS bio           TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS photo_key     TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS linkedin_url  TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS google_sub    TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS linkedin_sub  TEXT;
-- FK to schools added in migration 023 (schools does not exist yet here).
ALTER TABLE users ADD COLUMN IF NOT EXISTS school_id     INTEGER;

-- Unique indexes allow many NULLs but forbid two accounts sharing one OAuth sub.
CREATE UNIQUE INDEX IF NOT EXISTS users_google_sub_key   ON users (google_sub);
CREATE UNIQUE INDEX IF NOT EXISTS users_linkedin_sub_key ON users (linkedin_sub);

-- The registry (schools table) is now the source of truth for allowed domains,
-- enforced server-side. Drop the hardcoded CHECK so new schools need no DDL.
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_email_allowed;

-- Email+passcode OTP: 6-digit code, SHA-256 hashed at rest (like email
-- verification tokens), 10-min expiry, <=3 verify attempts. Keyed by email so
-- no orphan user rows are created before the code is proven.
CREATE TABLE IF NOT EXISTS login_otp_codes (
    id          SERIAL       PRIMARY KEY,
    email       CITEXT       NOT NULL,
    code_hash   TEXT         NOT NULL,
    expires_at  TIMESTAMPTZ  NOT NULL,
    attempts    INTEGER      NOT NULL DEFAULT 0,
    consumed_at TIMESTAMPTZ,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS login_otp_codes_email_idx ON login_otp_codes (email);
