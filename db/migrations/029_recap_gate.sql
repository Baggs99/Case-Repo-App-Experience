-- 029_recap_gate.sql — B3 feedback recap gate + case rating.
-- viewed_at/closed_at track the recap read+close; case_rating is the required
-- 1-5 close-out rating (same scale as the debrief, design delta §0.5);
-- feedback_thumbs is the optional interviewer-quality mark (auth interviewers).
-- Idempotent: ADD COLUMN IF NOT EXISTS.

ALTER TABLE feedback ADD COLUMN IF NOT EXISTS viewed_at   TIMESTAMPTZ;
ALTER TABLE feedback ADD COLUMN IF NOT EXISTS closed_at   TIMESTAMPTZ;
ALTER TABLE feedback ADD COLUMN IF NOT EXISTS case_rating SMALLINT
    CHECK (case_rating IS NULL OR (case_rating BETWEEN 1 AND 5));
ALTER TABLE feedback ADD COLUMN IF NOT EXISTS feedback_thumbs BOOLEAN;

-- Powers candidate_gate (oldest open recap) and the recap list.
CREATE INDEX IF NOT EXISTS idx_feedback_open_recap
    ON feedback(session_id)
    WHERE finalized_at IS NOT NULL AND closed_at IS NULL;
