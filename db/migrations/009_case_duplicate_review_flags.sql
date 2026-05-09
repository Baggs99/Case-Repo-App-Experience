-- Duplicate review flags (operator-controlled; never set automatically by the app).
-- Run after reviewing output/duplicate_review_candidates.csv and applying
-- output/duplicate_review_approved.csv via scripts/apply-duplicate-review-approved.py

ALTER TABLE cases
    ADD COLUMN IF NOT EXISTS is_duplicate_case BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE cases
    ADD COLUMN IF NOT EXISTS unique_case_count_eligible BOOLEAN NOT NULL DEFAULT true;

COMMENT ON COLUMN cases.is_duplicate_case IS
    'When true, row is hidden from public deduped search and excluded before title-based canonical ranking.';

COMMENT ON COLUMN cases.unique_case_count_eligible IS
    'When false, row is excluded from unique-case counts; canonical rows usually stay true.';
