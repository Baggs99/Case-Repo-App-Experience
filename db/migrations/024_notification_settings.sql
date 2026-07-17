-- 024_notification_settings.sql
-- Purpose: per-user notification category toggles. The push fan-out choke point
--          consults this before sending. Missing row == all categories enabled.
-- Idempotent: CREATE TABLE IF NOT EXISTS.

CREATE TABLE IF NOT EXISTS notification_settings (
    user_id           INTEGER PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    proposals         BOOLEAN NOT NULL DEFAULT TRUE,
    session_reminders BOOLEAN NOT NULL DEFAULT TRUE,
    feedback          BOOLEAN NOT NULL DEFAULT TRUE,
    free_now          BOOLEAN NOT NULL DEFAULT TRUE,
    community         BOOLEAN NOT NULL DEFAULT TRUE
);
