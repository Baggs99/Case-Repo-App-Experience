-- Fix kind CHECK so open_tab inserts succeed on databases where migration 004
-- did not apply or used a mismatched constraint name.
--
-- Apply on production:  psql "$DATABASE_URL" -f db/migrations/005_case_access_kind_constraint_fix.sql

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT c.conname
        FROM pg_constraint c
        JOIN pg_class t ON c.conrelid = t.oid
        JOIN pg_namespace n ON t.relnamespace = n.oid
        WHERE n.nspname = 'public'
          AND t.relname = 'case_access_events'
          AND c.contype = 'c'
          AND pg_get_constraintdef(c.oid) ILIKE '%kind%'
    LOOP
        EXECUTE format('ALTER TABLE case_access_events DROP CONSTRAINT %I', r.conname);
    END LOOP;
END $$;

ALTER TABLE case_access_events ADD CONSTRAINT case_access_events_kind_check
    CHECK (kind IN ('view', 'download', 'open_tab'));
