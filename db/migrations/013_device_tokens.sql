-- db/migrations/013_device_tokens.sql
-- iOS push: one row per (user, device token). Token is the APNs hex token.
CREATE TABLE IF NOT EXISTS device_tokens (
    id            bigserial PRIMARY KEY,
    user_id       bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token         text   NOT NULL UNIQUE,
    platform      text   NOT NULL DEFAULT 'ios',
    created_at    timestamptz NOT NULL DEFAULT now(),
    last_seen_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON device_tokens(user_id);

ALTER TABLE practice_sessions
    ADD COLUMN IF NOT EXISTS starting_soon_pushed_at timestamptz;
