-- Opaque slug per case for publicly hosted JPEG previews (R2 / custom domain).
-- App URLs: {R2_PUBLIC_BASE_URL}/previews/{slug}/page-001.jpg (slug = preview_public_slug).
-- Uses gen_random_uuid() (PostgreSQL 13+) — no pgcrypto dependency.

ALTER TABLE cases
  ADD COLUMN IF NOT EXISTS preview_public_slug VARCHAR(40) UNIQUE;

UPDATE cases
  SET preview_public_slug = REPLACE(gen_random_uuid()::text, '-', '')
  WHERE preview_public_slug IS NULL;

ALTER TABLE cases
  ALTER COLUMN preview_public_slug SET DEFAULT REPLACE(gen_random_uuid()::text, '-', '');

ALTER TABLE cases
  ALTER COLUMN preview_public_slug SET NOT NULL;
