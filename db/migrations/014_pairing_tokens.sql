-- db/migrations/014_pairing_tokens.sql
-- Ad-hoc in-person pairing: an interviewer mints a one-time token bound to a
-- chosen case; the scanner (candidate) claims it, which CREATES the session.
CREATE TABLE IF NOT EXISTS pairing_tokens (
    id                  bigserial   PRIMARY KEY,
    token               text        NOT NULL UNIQUE,      -- URL-safe random, in the QR
    interviewer_id      integer     NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    case_id             integer     NOT NULL REFERENCES cases(id) ON DELETE CASCADE,
    created_at          timestamptz NOT NULL DEFAULT now(),
    expires_at          timestamptz NOT NULL,             -- short TTL (e.g. now()+10 min)
    claimed_session_id  integer     REFERENCES practice_sessions(id)  -- NULL until claimed (single-use)
);
CREATE INDEX IF NOT EXISTS idx_pairing_tokens_token ON pairing_tokens(token);
