-- Relax users email constraint: Yale @yale.edu OR sole Booth guest acannata@chicagobooth.edu
-- Run once against existing databases (Render Postgres, local prod-like DB).
--
--   psql "$DATABASE_URL" -f db/migrations/002_users_email_allow_booth_guest.sql

ALTER TABLE users DROP CONSTRAINT IF EXISTS users_email_yale_only;
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_email_allowed;

ALTER TABLE users ADD CONSTRAINT users_email_allowed CHECK (
    email ILIKE '%@yale.edu'
    OR lower(email::text) = 'acannata@chicagobooth.edu'
);
