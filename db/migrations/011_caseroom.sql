-- ============================================================================
-- 011 — CaseRoom: 1:1 case-interview practice sessions
-- ----------------------------------------------------------------------------
-- Apply with:   python main.py apply-sql-migration db/migrations/011_caseroom.sql
--               (or psql -d <db> -v ON_ERROR_STOP=1 -f db/migrations/011_caseroom.sql)
-- Idempotent:   safe to re-run (IF NOT EXISTS throughout; backfill is guarded).
--
-- Table/column mapping rationale lives in INTEGRATION.md §3 — notably:
-- spec `sessions` → `practice_sessions` (auth sessions own that name) and
-- spec `exhibits` → `case_exhibits` (matches the case_* table convention).
-- TEXT + CHECK for enums, per the difficulty / vote_type / kind precedent.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- users.display_name
-- ----------------------------------------------------------------------------
-- Shown in rooms, proposals, and the in-call knock UI. Nullable: the app
-- falls back to the email local-part, which the backfill also seeds.
-- ----------------------------------------------------------------------------
ALTER TABLE users ADD COLUMN IF NOT EXISTS display_name TEXT;

UPDATE users
   SET display_name = split_part(email::text, '@', 1)
 WHERE display_name IS NULL;


-- ----------------------------------------------------------------------------
-- rooms
-- ----------------------------------------------------------------------------
-- One permanent room per user, auto-created on first CaseRoom visit.
-- The slug is public and non-secret (/room/{slug}); access control lives on
-- sessions, not rooms.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rooms (
    id             SERIAL       PRIMARY KEY,
    owner_user_id  INTEGER      NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    slug           TEXT         NOT NULL UNIQUE,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);


-- ----------------------------------------------------------------------------
-- rubric_templates
-- ----------------------------------------------------------------------------
-- case_id NULL = generic template usable with any case. items_json is a list
-- of {id, label, dimension, max_points}; dimension ∈ structure/quant/insight/
-- communication/synthesis (validated in app code, not here — the shape may
-- grow and JSONB CHECKs are brittle).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rubric_templates (
    id          SERIAL       PRIMARY KEY,
    case_id     INTEGER      REFERENCES cases(id) ON DELETE CASCADE,
    name        TEXT         NOT NULL,
    items_json  JSONB        NOT NULL,
    created_by  INTEGER      NOT NULL REFERENCES users(id),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rubric_templates_case ON rubric_templates (case_id);


-- ----------------------------------------------------------------------------
-- case_exhibits
-- ----------------------------------------------------------------------------
-- Server-rendered (PyMuPDF → WebP) pages of a case, encrypted at rest with
-- AES-256-GCM (tag appended to ciphertext). The key/IV never leave the server
-- except: keys to the session interviewer at call start, and a single key to
-- the candidate at reveal time. Blobs are served encrypted for preload.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS case_exhibits (
    id             SERIAL       PRIMARY KEY,
    case_id        INTEGER      NOT NULL REFERENCES cases(id) ON DELETE CASCADE,
    idx            SMALLINT     NOT NULL CHECK (idx >= 1),          -- Exhibit 1..N
    source_pages   TEXT         NOT NULL,                           -- "4" or "4-5", informational
    enc_blob_path  TEXT         NOT NULL,                           -- storage key, private prefix
    enc_key        BYTEA        NOT NULL,                           -- 32 bytes
    enc_iv         BYTEA        NOT NULL,                           -- 12 bytes
    width          INTEGER      NOT NULL,
    height         INTEGER      NOT NULL,
    bytes          INTEGER      NOT NULL,
    created_by     INTEGER      NOT NULL REFERENCES users(id),
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT case_exhibits_unique_idx UNIQUE (case_id, idx)
);


-- ----------------------------------------------------------------------------
-- practice_sessions
-- ----------------------------------------------------------------------------
-- The 1:1 interview session. State machine (§4.5 of the spec):
--   scheduled → lobby → live → debrief → finalized     (terminal)
--   any pre-debrief state → aborted                    (terminal)
-- All transitions are server-validated: correct actor, legal edge, and both
-- consent booleans required to enter 'live' (spec INV-10).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS practice_sessions (
    id                   SERIAL       PRIMARY KEY,
    room_id              INTEGER      NOT NULL REFERENCES rooms(id),
    interviewer_id       INTEGER      NOT NULL REFERENCES users(id),
    candidate_id         INTEGER      NOT NULL REFERENCES users(id),
    case_id              INTEGER      NOT NULL REFERENCES cases(id),
    rubric_template_id   INTEGER      NOT NULL REFERENCES rubric_templates(id),
    state                TEXT         NOT NULL DEFAULT 'scheduled'
        CHECK (state IN ('scheduled','lobby','live','debrief','finalized','aborted')),
    consent_interviewer  BOOLEAN      NOT NULL DEFAULT FALSE,
    consent_candidate    BOOLEAN      NOT NULL DEFAULT FALSE,
    scheduled_at         TIMESTAMPTZ,
    started_at           TIMESTAMPTZ,
    ended_at             TIMESTAMPTZ,
    created_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT practice_sessions_distinct_roles CHECK (interviewer_id <> candidate_id)
);

CREATE INDEX IF NOT EXISTS idx_practice_sessions_candidate
    ON practice_sessions (candidate_id, state, ended_at);
CREATE INDEX IF NOT EXISTS idx_practice_sessions_interviewer
    ON practice_sessions (interviewer_id, state, ended_at);


-- ----------------------------------------------------------------------------
-- reveals
-- ----------------------------------------------------------------------------
-- Server-side system of record for exhibit reveals; the DataChannel key
-- message is only the fast path. The candidate key endpoint serves a key
-- IFF a row exists here.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS reveals (
    id           SERIAL       PRIMARY KEY,
    session_id   INTEGER      NOT NULL REFERENCES practice_sessions(id) ON DELETE CASCADE,
    exhibit_id   INTEGER      NOT NULL REFERENCES case_exhibits(id),
    revealed_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    t_offset_ms  INTEGER      NOT NULL CHECK (t_offset_ms >= 0),   -- ms since started_at
    CONSTRAINT reveals_once_per_exhibit UNIQUE (session_id, exhibit_id)
);


-- ----------------------------------------------------------------------------
-- feedback
-- ----------------------------------------------------------------------------
-- One row per session, created when the interviewer first saves a rubric
-- draft. grade + finalized_at are set at finalize (grade scale 0–5, see
-- INTEGRATION.md A5). Visible to the candidate only post-finalize.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS feedback (
    id            SERIAL       PRIMARY KEY,
    session_id    INTEGER      NOT NULL UNIQUE REFERENCES practice_sessions(id) ON DELETE CASCADE,
    rubric_json   JSONB        NOT NULL,
    grade         NUMERIC(3,1) CHECK (grade IS NULL OR (grade >= 0 AND grade <= 5)),
    notes_md      TEXT,
    finalized_at  TIMESTAMPTZ
);


-- ----------------------------------------------------------------------------
-- queue_want / queue_give
-- ----------------------------------------------------------------------------
-- Cases a user wants to receive vs. is prepped to give. Drives the
-- intersection lists on room visits and proposal validation.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS queue_want (
    user_id   INTEGER      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    case_id   INTEGER      NOT NULL REFERENCES cases(id) ON DELETE CASCADE,
    added_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, case_id)
);

CREATE TABLE IF NOT EXISTS queue_give (
    user_id   INTEGER      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    case_id   INTEGER      NOT NULL REFERENCES cases(id) ON DELETE CASCADE,
    added_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, case_id)
);


-- ----------------------------------------------------------------------------
-- burned
-- ----------------------------------------------------------------------------
-- Written at finalize: the candidate has now seen this case's content and is
-- excluded from receiving it again (browse recommendations, intersections,
-- proposal validation all consult this).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS burned (
    user_id     INTEGER      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    case_id     INTEGER      NOT NULL REFERENCES cases(id) ON DELETE CASCADE,
    session_id  INTEGER      NOT NULL REFERENCES practice_sessions(id),
    burned_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, case_id)
);


-- ----------------------------------------------------------------------------
-- proposals
-- ----------------------------------------------------------------------------
-- "Let's do this case" between two users. from_role is the role the PROPOSER
-- will take. Accept creates the practice_session and links it here.
-- Expiry: pending proposals older than 7 days are swept to 'expired' on
-- inbox page load (no cron dependency).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS proposals (
    id                   SERIAL       PRIMARY KEY,
    from_user_id         INTEGER      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    to_user_id           INTEGER      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    case_id              INTEGER      NOT NULL REFERENCES cases(id) ON DELETE CASCADE,
    from_role            TEXT         NOT NULL CHECK (from_role IN ('interviewer','candidate')),
    message              TEXT         CHECK (message IS NULL OR char_length(message) <= 500),
    proposed_times_json  JSONB,
    state                TEXT         NOT NULL DEFAULT 'pending'
        CHECK (state IN ('pending','accepted','declined','expired')),
    session_id           INTEGER      REFERENCES practice_sessions(id),
    created_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    responded_at         TIMESTAMPTZ,
    CONSTRAINT proposals_distinct_users CHECK (from_user_id <> to_user_id)
);

CREATE INDEX IF NOT EXISTS idx_proposals_inbox
    ON proposals (to_user_id, state, created_at);


-- ----------------------------------------------------------------------------
-- recordings
-- ----------------------------------------------------------------------------
-- Per-participant local mic recordings, chunk-uploaded during the call
-- (60 s timeslice) and finalized at debrief. Storage only — no processing
-- in v1. path is a storage key under the private recordings/ prefix.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS recordings (
    id          SERIAL       PRIMARY KEY,
    session_id  INTEGER      NOT NULL REFERENCES practice_sessions(id) ON DELETE CASCADE,
    user_id     INTEGER      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role        TEXT         NOT NULL CHECK (role IN ('interviewer','candidate')),
    path        TEXT         NOT NULL,
    mime        TEXT         NOT NULL,                    -- audio/webm or audio/mp4 (Safari)
    bytes       BIGINT       NOT NULL DEFAULT 0,
    chunks      INTEGER      NOT NULL DEFAULT 0,
    completed   BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT recordings_one_per_participant UNIQUE (session_id, user_id)
);
