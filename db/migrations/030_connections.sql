-- 030: Community connections (mutual friend requests). B6.
-- The row (user_id, friend_id) represents "user_id requested friend_id".
-- state 'pending' -> 'accepted' on the target's accept. PK forbids duplicate
-- directed rows; the reciprocal direction is auto-accepted in the repo layer.
CREATE TABLE IF NOT EXISTS connections (
    user_id      INTEGER     NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    friend_id    INTEGER     NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    state        TEXT        NOT NULL DEFAULT 'pending'
                             CHECK (state IN ('pending', 'accepted')),
    requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    responded_at TIMESTAMPTZ,
    PRIMARY KEY (user_id, friend_id),
    CONSTRAINT connections_distinct CHECK (user_id <> friend_id)
);

-- List-my-connections scans both directions; index the reverse lookup.
CREATE INDEX IF NOT EXISTS idx_connections_friend ON connections (friend_id);
