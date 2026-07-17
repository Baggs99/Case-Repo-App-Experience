-- 023_schools_registry.sql
-- Purpose: schools registry (domain -> school). Seed the three launch schools,
--          wire users.school_id FK, and backfill existing users by email domain.
-- Idempotent: CREATE TABLE IF NOT EXISTS, ON CONFLICT DO NOTHING, guarded FK.

CREATE TABLE IF NOT EXISTS schools (
    id         SERIAL       PRIMARY KEY,
    name       TEXT         NOT NULL,
    domain     TEXT         NOT NULL UNIQUE,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

INSERT INTO schools (name, domain) VALUES
    ('Yale School of Management', 'yale.edu'),
    ('University of Michigan (Ross)', 'umich.edu'),
    ('University of Chicago (Booth)', 'chicagobooth.edu')
ON CONFLICT (domain) DO NOTHING;

-- Add the FK now that schools exists (guarded so re-runs are no-ops).
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'users_school_id_fkey'
    ) THEN
        ALTER TABLE users
            ADD CONSTRAINT users_school_id_fkey
            FOREIGN KEY (school_id) REFERENCES schools (id);
    END IF;
END $$;

-- Backfill: match each user's email domain to a school. Only touches NULLs,
-- so re-running never clobbers a manually-set school_id.
UPDATE users u
   SET school_id = s.id
  FROM schools s
 WHERE u.school_id IS NULL
   AND split_part(lower(u.email::text), '@', 2) = s.domain;
