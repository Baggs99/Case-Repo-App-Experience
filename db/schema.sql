-- ============================================================================
-- Case Repo — Postgres schema
-- ----------------------------------------------------------------------------
-- Apply with:   psql -U postgres -d caserepo -f db/schema.sql
-- Idempotent:   safe to re-run (uses IF NOT EXISTS / DROP-and-recreate where
--               appropriate). Drops nothing that holds user data.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Extensions
-- ----------------------------------------------------------------------------
-- Loaded up front because tables below reference types (CITEXT) and
-- index ops (gin_trgm_ops) that they provide.
-- ----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS pg_trgm;


-- ----------------------------------------------------------------------------
-- cases
-- ----------------------------------------------------------------------------
-- Mirrors the search-relevant columns of output/case_catalog.csv.
-- Wide / debug columns (difficulty_quant, detection_method, audit fields,
-- etc.) are intentionally excluded — keep this table lean and add columns
-- only when the website actually displays them.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cases (
    id                SERIAL       PRIMARY KEY,

    case_title        TEXT         NOT NULL,
    normalized_title  TEXT         NOT NULL,
    source_school     TEXT         NOT NULL,
    source_year       INTEGER,

    industry          TEXT,
    case_type         TEXT,
    difficulty        TEXT         CHECK (difficulty IN ('Easy', 'Medium', 'Hard')),
    difficulty_score  NUMERIC(3,1) CHECK (difficulty_score BETWEEN 0 AND 10),

    firm              TEXT,
    interviewer_led   BOOLEAN,
    page_count        INTEGER,

    pdf_path          TEXT         NOT NULL,

    -- Operator-controlled duplicate review (see db/migrations/009_case_duplicate_review_flags.sql).
    is_duplicate_case          BOOLEAN NOT NULL DEFAULT false,
    unique_case_count_eligible BOOLEAN NOT NULL DEFAULT true,

    created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    -- Prevent the same case appearing twice from a re-sync of the catalog.
    -- NULLS NOT DISTINCT (Postgres 15+) is critical here: many cases —
    -- especially RocketBlocks — have NULL source_year, and the default
    -- UNIQUE behaviour treats every NULL as distinct, which would let
    -- duplicates sneak in on every re-publish.
    CONSTRAINT cases_unique_per_school_year UNIQUE NULLS NOT DISTINCT (source_school, source_year, normalized_title)
);

CREATE INDEX IF NOT EXISTS idx_cases_difficulty    ON cases (difficulty);
CREATE INDEX IF NOT EXISTS idx_cases_industry      ON cases (industry);
CREATE INDEX IF NOT EXISTS idx_cases_case_type     ON cases (case_type);
CREATE INDEX IF NOT EXISTS idx_cases_source_school ON cases (source_school);

-- Trigram index on case_title to support `WHERE case_title ILIKE '%retail%'`
-- without scanning every row. Requires the pg_trgm extension (loaded above).
CREATE INDEX IF NOT EXISTS idx_cases_title_trgm ON cases USING GIN (case_title gin_trgm_ops);


-- ----------------------------------------------------------------------------
-- users
-- ----------------------------------------------------------------------------
-- Minimal shape needed for school-email auth (@yale.edu, @umich.edu + Booth guest).
-- email_verified_at is NULL until the user clicks the verification link.
-- password_hash holds an argon2id (or bcrypt) hash — NEVER plain text.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id                  SERIAL       PRIMARY KEY,
    email               CITEXT       NOT NULL UNIQUE,   -- case-insensitive
    password_hash       TEXT         NOT NULL,
    email_verified_at   TIMESTAMPTZ,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    last_login_at       TIMESTAMPTZ,

    -- Defense in depth: allowed school domains plus one invited Booth account.
    CONSTRAINT users_email_allowed CHECK (
        email ILIKE '%@yale.edu'
        OR email ILIKE '%@umich.edu'
        OR lower(email::text) = 'acannata@chicagobooth.edu'
    )
);

-- CITEXT (loaded at the top of this file) makes the email column
-- case-insensitive for both equality and uniqueness. Without it,
-- "Dan@Yale.edu" and "dan@yale.edu" would be treated as two different users.


-- ----------------------------------------------------------------------------
-- email_verification_tokens
-- ----------------------------------------------------------------------------
-- One row per pending or consumed verification link.
-- Stores only the SHA-256 hash of the token, never the token itself —
-- so even a database leak doesn't let an attacker hijack pending sign-ups.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS email_verification_tokens (
    id           SERIAL       PRIMARY KEY,
    user_id      INTEGER      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash   TEXT         NOT NULL UNIQUE,
    expires_at   TIMESTAMPTZ  NOT NULL,
    consumed_at  TIMESTAMPTZ,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_evt_user_id    ON email_verification_tokens (user_id);
CREATE INDEX IF NOT EXISTS idx_evt_expires_at ON email_verification_tokens (expires_at);


-- ----------------------------------------------------------------------------
-- password_reset_tokens
-- ----------------------------------------------------------------------------
-- Same shape as email_verification_tokens but kept distinct because the
-- two flows have different lifetimes (resets expire faster — 1 hour vs.
-- 24 — since they're a higher-impact action) and may diverge further.
-- ON DELETE CASCADE means deleting a user wipes their pending resets.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS password_reset_tokens (
    id           SERIAL       PRIMARY KEY,
    user_id      INTEGER      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash   TEXT         NOT NULL UNIQUE,
    expires_at   TIMESTAMPTZ  NOT NULL,
    consumed_at  TIMESTAMPTZ,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_prt_user_id    ON password_reset_tokens (user_id);
CREATE INDEX IF NOT EXISTS idx_prt_expires_at ON password_reset_tokens (expires_at);


-- ----------------------------------------------------------------------------
-- sessions
-- ----------------------------------------------------------------------------
-- Server-side session records. The browser only ever sees the (random)
-- session_id cookie; everything else lives here. Rotating or deleting a
-- row instantly logs the user out of that device.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sessions (
    id           TEXT         PRIMARY KEY,             -- random 32+ byte token (hex/base64)
    user_id      INTEGER      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    expires_at   TIMESTAMPTZ  NOT NULL,
    user_agent   TEXT,
    ip_address   INET
);

CREATE INDEX IF NOT EXISTS idx_sessions_user_id    ON sessions (user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_expires_at ON sessions (expires_at);


-- ----------------------------------------------------------------------------
-- case_access_events
-- ----------------------------------------------------------------------------
-- One row per audited PDF action: download, open in new tab (open_tab), or
-- legacy view. PNG page previews are not logged here.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS case_access_events (
    id          SERIAL       PRIMARY KEY,
    user_id     INTEGER      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    case_id     INTEGER      NOT NULL REFERENCES cases(id) ON DELETE CASCADE,
    kind        TEXT         NOT NULL CHECK (kind IN ('view', 'download', 'open_tab')),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_case_access_user_created
    ON case_access_events (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_case_access_case
    ON case_access_events (case_id);


-- ----------------------------------------------------------------------------
-- case_votes
-- ----------------------------------------------------------------------------
-- One row per user per case: useful vs not_useful for recruiting-prep feedback.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS case_votes (
    id          SERIAL       PRIMARY KEY,
    case_id     INTEGER      NOT NULL REFERENCES cases(id) ON DELETE CASCADE,
    user_id     INTEGER      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    vote_type   TEXT         NOT NULL CHECK (vote_type IN ('useful', 'not_useful')),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT case_votes_unique_user_case UNIQUE (case_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_case_votes_case_id ON case_votes(case_id);
CREATE INDEX IF NOT EXISTS idx_case_votes_user_id ON case_votes(user_id);


-- ----------------------------------------------------------------------------
-- updated_at trigger for cases
-- ----------------------------------------------------------------------------
-- Keeps cases.updated_at fresh automatically on every UPDATE.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_cases_updated_at ON cases;
CREATE TRIGGER trg_cases_updated_at
    BEFORE UPDATE ON cases
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_case_votes_updated_at ON case_votes;
CREATE TRIGGER trg_case_votes_updated_at
    BEFORE UPDATE ON case_votes
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();
