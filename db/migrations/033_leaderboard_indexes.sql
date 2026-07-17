-- 033: Indexes supporting B6 leaderboard/standing scans. B6.
-- practice_sessions already has (candidate_id, state, ended_at) and the
-- interviewer variant (011); drill_attempts has (user_id, completed_at) (017);
-- group_members(user_id) and connections(friend_id) are added by 031/030.
-- Feedback is scanned by finalized rows joined to sessions per candidate.
CREATE INDEX IF NOT EXISTS idx_feedback_finalized
    ON feedback (finalized_at) WHERE finalized_at IS NOT NULL;
