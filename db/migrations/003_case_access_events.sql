-- Log per-user case PDF views and downloads (admin analytics).
-- Apply once on existing databases:
--   psql "$DATABASE_URL" -f db/migrations/003_case_access_events.sql

CREATE TABLE IF NOT EXISTS case_access_events (
    id          SERIAL       PRIMARY KEY,
    user_id     INTEGER      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    case_id     INTEGER      NOT NULL REFERENCES cases(id) ON DELETE CASCADE,
    kind        TEXT         NOT NULL CHECK (kind IN ('view', 'download')),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_case_access_user_created
    ON case_access_events (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_case_access_case
    ON case_access_events (case_id);
