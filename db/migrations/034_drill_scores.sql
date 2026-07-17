-- db/migrations/034_drill_scores.sql
-- B8: gauntlet scoring substrate. drill_attempts gains a run score, per-slot
-- duration, and the date-seeded gauntlet set membership key. All NULL for the
-- pre-existing P4 per-user attempts (untouched); populated for gauntlet slots.
ALTER TABLE drill_attempts ADD COLUMN IF NOT EXISTS score       REAL;
ALTER TABLE drill_attempts ADD COLUMN IF NOT EXISTS duration_ms INTEGER;
ALTER TABLE drill_attempts ADD COLUMN IF NOT EXISTS set_key     TEXT;
