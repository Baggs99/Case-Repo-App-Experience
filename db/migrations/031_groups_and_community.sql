-- 031: Community groups + memberships, school-leader role, and the
-- schools.campus_city column the school-vs-school board renders. B6.

CREATE TABLE IF NOT EXISTS groups (
    id          SERIAL      PRIMARY KEY,
    name        TEXT        NOT NULL,
    school_id   INTEGER     REFERENCES schools(id),
    invite_code TEXT,
    created_by  INTEGER     NOT NULL REFERENCES users(id),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- 6-char invite code (B1 short-code alphabet); partial unique like pairing_tokens.
CREATE UNIQUE INDEX IF NOT EXISTS idx_groups_invite_code
    ON groups (invite_code) WHERE invite_code IS NOT NULL;

CREATE TABLE IF NOT EXISTS group_members (
    group_id  INTEGER     NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    user_id   INTEGER     NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role      TEXT        NOT NULL DEFAULT 'member'
                          CHECK (role IN ('admin', 'member')),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (group_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_group_members_user ON group_members (user_id);

-- School-leader role: admin-assigned (seedable), no self-serve path yet.
CREATE TABLE IF NOT EXISTS school_leaders (
    school_id INTEGER NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    user_id   INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    PRIMARY KEY (school_id, user_id)
);

-- Campus city for the school-vs-school board (avg member percentile + city).
ALTER TABLE schools ADD COLUMN IF NOT EXISTS campus_city TEXT;
UPDATE schools SET campus_city = 'New Haven' WHERE domain = 'yale.edu'         AND campus_city IS NULL;
UPDATE schools SET campus_city = 'Ann Arbor' WHERE domain = 'umich.edu'        AND campus_city IS NULL;
UPDATE schools SET campus_city = 'Chicago'   WHERE domain = 'chicagobooth.edu' AND campus_city IS NULL;
