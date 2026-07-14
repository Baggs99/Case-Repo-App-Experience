-- db/migrations/016_live_activity_tokens.sql
-- Per-session ActivityKit Live Activity push tokens (P3 T9). One activity
-- per user per session; re-registering (e.g. app relaunch) replaces the token.
CREATE TABLE IF NOT EXISTS live_activity_tokens (
    id          serial      PRIMARY KEY,
    session_id  int         NOT NULL REFERENCES practice_sessions(id),
    user_id     int         NOT NULL REFERENCES users(id),
    push_token  text        NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (session_id, user_id)
);
