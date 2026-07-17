-- 028_negotiation_and_swap.sql — B3 case negotiation + role swap.
-- Adds the pre-lobby 'negotiating' session state (case chosen after pairing),
-- makes case_id/rubric_template_id nullable for negotiating sessions, links a
-- swapped session to its origin, and adds the negotiation + swap-invite tables.
-- Idempotent: re-runnable (IF NOT EXISTS / DROP CONSTRAINT IF EXISTS + re-ADD).

ALTER TABLE practice_sessions ALTER COLUMN case_id DROP NOT NULL;
ALTER TABLE practice_sessions ALTER COLUMN rubric_template_id DROP NOT NULL;

ALTER TABLE practice_sessions DROP CONSTRAINT IF EXISTS practice_sessions_state_check;
ALTER TABLE practice_sessions ADD CONSTRAINT practice_sessions_state_check
    CHECK (state = ANY (ARRAY[
        'negotiating', 'scheduled', 'lobby', 'live',
        'debrief', 'finalized', 'aborted', 'missed'
    ]));

ALTER TABLE practice_sessions
    ADD COLUMN IF NOT EXISTS swapped_from_session_id INTEGER
        REFERENCES practice_sessions(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS case_negotiations (
    id               SERIAL PRIMARY KEY,
    session_id       INTEGER NOT NULL REFERENCES practice_sessions(id) ON DELETE CASCADE,
    proposed_case_id INTEGER NOT NULL REFERENCES cases(id),
    by_user_id       INTEGER NOT NULL REFERENCES users(id),
    round            INTEGER NOT NULL,
    state            TEXT NOT NULL DEFAULT 'pending'
                        CHECK (state = ANY (ARRAY['pending', 'accepted', 'declined'])),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_case_negotiations_session
    ON case_negotiations(session_id, round);

CREATE TABLE IF NOT EXISTS swap_invites (
    id              SERIAL PRIMARY KEY,
    from_session_id INTEGER NOT NULL REFERENCES practice_sessions(id) ON DELETE CASCADE,
    initiator_id    INTEGER NOT NULL REFERENCES users(id),
    invitee_id      INTEGER NOT NULL REFERENCES users(id),
    state           TEXT NOT NULL DEFAULT 'pending'
                        CHECK (state = ANY (ARRAY['pending', 'accepted', 'declined', 'expired'])),
    new_session_id  INTEGER REFERENCES practice_sessions(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    responded_at    TIMESTAMPTZ
);
-- At most one live (pending) swap invite per origin session.
CREATE UNIQUE INDEX IF NOT EXISTS uq_swap_invites_pending
    ON swap_invites(from_session_id) WHERE state = 'pending';
