-- Allow Michigan Ross (@umich.edu) addresses alongside Yale and the Booth guest.

ALTER TABLE users DROP CONSTRAINT IF EXISTS users_email_allowed;

ALTER TABLE users ADD CONSTRAINT users_email_allowed CHECK (
    email ILIKE '%@yale.edu'
    OR email ILIKE '%@umich.edu'
    OR lower(email::text) = 'acannata@chicagobooth.edu'
);
