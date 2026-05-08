-- Useful / Not useful votes per user per case (recruiting prep feedback).

CREATE TABLE IF NOT EXISTS case_votes (
    id          SERIAL       PRIMARY KEY,
    case_id     INTEGER      NOT NULL REFERENCES cases(id) ON DELETE CASCADE,
    user_id     INTEGER      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    vote_type   TEXT         NOT NULL CHECK (vote_type IN ('useful', 'not_useful')),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT case_votes_unique_user_case UNIQUE (case_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_case_votes_case_id ON case_votes(case_id);
CREATE INDEX IF NOT EXISTS idx_case_votes_user_id ON case_votes(user_id);

DROP TRIGGER IF EXISTS trg_case_votes_updated_at ON case_votes;
CREATE TRIGGER trg_case_votes_updated_at
    BEFORE UPDATE ON case_votes
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();
