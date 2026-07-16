-- db/migrations/017_drill_attempts.sql
-- P4 habit layer: one row per completed solo drill (on-device FM or server
-- bank). Powers the daily streak; superseded-in-place by the drills-DB track.
CREATE TABLE IF NOT EXISTS drill_attempts (
    id          serial      PRIMARY KEY,
    user_id     int         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    drill_type  text        NOT NULL CHECK (drill_type IN ('market_sizing','mental_math','framework_recall')),
    source      text        NOT NULL CHECK (source IN ('on_device','server')),
    drill_key   text,
    correct     boolean     NOT NULL,
    completed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_drill_attempts_user_day
    ON drill_attempts (user_id, completed_at);
