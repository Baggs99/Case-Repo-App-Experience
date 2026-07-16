-- db/migrations/018_availability.sql
-- P4 "free now": one row per user marking a free-until window. Read lazily
-- (every query filters free_until > now()); no sweep — expiry is a filter.
CREATE TABLE IF NOT EXISTS availability (
    user_id    int         PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    free_until timestamptz NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);
