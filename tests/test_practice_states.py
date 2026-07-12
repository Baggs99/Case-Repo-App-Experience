"""
Unit tests for webapp.practice_states — every edge of the session state
machine, both actors, with and without consent.
"""

from __future__ import annotations

import unittest

from webapp.practice_states import TransitionError, validate_transition


def _err(current, target, role, ci=False, cc=False):
    try:
        validate_transition(current, target, role, ci, cc)
    except TransitionError as exc:
        return exc
    return None


class TestLegalEdges(unittest.TestCase):
    def test_scheduled_to_lobby_either_role(self):
        for role in ("interviewer", "candidate"):
            self.assertIsNone(_err("scheduled", "lobby", role))

    def test_lobby_to_live_interviewer_with_consents(self):
        validate_transition("lobby", "live", "interviewer", True, True)

    def test_live_to_debrief_either_role(self):
        for role in ("interviewer", "candidate"):
            self.assertIsNone(_err("live", "debrief", role, True, True))

    def test_abort_from_pre_debrief_states(self):
        for state in ("scheduled", "lobby", "live"):
            for role in ("interviewer", "candidate"):
                self.assertIsNone(_err(state, "aborted", role, True, True))


class TestWrongActor(unittest.TestCase):
    def test_candidate_cannot_go_live(self):
        exc = _err("lobby", "live", "candidate", True, True)
        self.assertEqual(exc.status_code, 403)


class TestConsentGate(unittest.TestCase):
    def test_live_blocked_without_any_consent(self):
        exc = _err("lobby", "live", "interviewer", False, False)
        self.assertEqual(exc.status_code, 409)

    def test_live_blocked_with_one_consent(self):
        for ci, cc in ((True, False), (False, True)):
            exc = _err("lobby", "live", "interviewer", ci, cc)
            self.assertEqual(exc.status_code, 409)


class TestIllegalEdges(unittest.TestCase):
    def test_no_skipping_forward(self):
        for current, target in (
            ("scheduled", "live"), ("scheduled", "debrief"),
            ("lobby", "debrief"), ("live", "finalized"),
        ):
            exc = _err(current, target, "interviewer", True, True)
            self.assertEqual(exc.status_code, 409, f"{current}->{target}")

    def test_no_going_backward(self):
        for current, target in (
            ("lobby", "scheduled"), ("live", "lobby"), ("debrief", "live"),
        ):
            exc = _err(current, target, "interviewer", True, True)
            self.assertEqual(exc.status_code, 409, f"{current}->{target}")

    def test_finalize_not_reachable_via_state_endpoint(self):
        # Finalize has its own endpoint (Phase 7) — the generic transition
        # must reject it from every state.
        for current in ("scheduled", "lobby", "live", "debrief"):
            exc = _err(current, "finalized", "interviewer", True, True)
            self.assertEqual(exc.status_code, 409, current)

    def test_terminal_states_immutable(self):
        for current in ("finalized", "aborted"):
            for target in ("scheduled", "lobby", "live", "debrief", "aborted"):
                if current == target:
                    continue
                exc = _err(current, target, "interviewer", True, True)
                self.assertEqual(exc.status_code, 409, f"{current}->{target}")

    def test_debrief_cannot_abort(self):
        # Post-call the session is a record; abort is pre-debrief only (§4.5).
        exc = _err("debrief", "aborted", "interviewer", True, True)
        self.assertEqual(exc.status_code, 409)

    def test_unknown_target_rejected(self):
        exc = _err("lobby", "paused", "interviewer", True, True)
        self.assertEqual(exc.status_code, 409)


class TestExceptionMechanics(unittest.TestCase):
    def test_survives_contextmanager_reraise(self):
        # Regression: contextlib.__exit__ assigns exc.__traceback__ on
        # re-raise; a frozen-dataclass exception rejects that assignment and
        # 500s every rejection path that crosses a DB context manager.
        from contextlib import contextmanager

        @contextmanager
        def db_like():
            yield

        with self.assertRaises(TransitionError) as ctx:
            with db_like():
                validate_transition("lobby", "live", "interviewer", False, False)
        self.assertEqual(ctx.exception.status_code, 409)


if __name__ == "__main__":
    unittest.main()
