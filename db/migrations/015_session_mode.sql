-- db/migrations/015_session_mode.sql
-- Distinguish remote (WebRTC media) from in-person (no media, P2 QR flow).
ALTER TABLE practice_sessions
  ADD COLUMN IF NOT EXISTS mode text NOT NULL DEFAULT 'remote'
  CHECK (mode IN ('remote','in_person'));
