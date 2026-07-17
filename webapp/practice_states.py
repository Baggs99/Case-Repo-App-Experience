"""
Practice-session state machine (docs/caseroom-spec.md §4.5, INTEGRATION.md A1).

Pure validation — no DB, no FastAPI — so every edge is unit-testable. The
repository applies the transition inside a row lock after this validates.

    negotiating → lobby → live → debrief → finalized   (also: scheduled → lobby)
    negotiating|scheduled|lobby|live → aborted

'negotiating' (B3) is the pre-lobby state for case-less sessions (case chosen
after pairing); the negotiating → lobby edge is deliberately NOT here — it's
driven only by stamp_negotiated_case, which sets the case atomically. Likewise
'finalized' is NOT reachable through the generic state endpoint: finalize has
its own endpoint (Phase 7) because it computes the grade, writes feedback and
burned rows, and releases content in one transaction.
"""

from __future__ import annotations

STATES = ("negotiating", "scheduled", "lobby", "live", "debrief", "finalized", "aborted", "missed")

# (current, target) -> role allowed to drive the edge ('any' = either participant)
# ('negotiating','lobby') is deliberately absent — that edge is driven only by
# stamp_negotiated_case, which sets the case atomically; the generic /state
# endpoint must not move a case-less session to lobby.
_EDGES: dict[tuple[str, str], str] = {
    ("negotiating", "aborted"): "any",   # bail out of negotiation
    ("scheduled", "lobby"): "any",
    ("lobby", "live"): "interviewer",   # A7: state change first, WS admit second
    ("live", "debrief"): "any",
    ("scheduled", "aborted"): "any",
    ("lobby", "aborted"): "any",
    ("live", "aborted"): "any",
}


class TransitionError(Exception):
    # NOT a frozen dataclass: Python's re-raise machinery (e.g. contextlib
    # __exit__) assigns exc.__traceback__, which frozen __setattr__ rejects —
    # turning every 403/409 into a FrozenInstanceError 500.
    def __init__(self, status_code: int, detail: str):
        super().__init__(status_code, detail)
        self.status_code = status_code  # 403 wrong actor · 409 illegal edge / consent gate
        self.detail = detail


def validate_transition(
    current: str,
    target: str,
    actor_role: str,                 # 'interviewer' | 'candidate'
    consent_interviewer: bool,
    consent_candidate: bool,
) -> None:
    """Raise TransitionError unless actor_role may move current → target."""
    if target not in STATES:
        raise TransitionError(409, f"Unknown state {target!r}")

    allowed_role = _EDGES.get((current, target))
    if allowed_role is None:
        raise TransitionError(409, f"Illegal transition {current} → {target}")

    if allowed_role != "any" and actor_role != allowed_role:
        raise TransitionError(403, f"Only the {allowed_role} may do this")

    # INV-10: no going live until both participants consented to recording.
    if target == "live" and not (consent_interviewer and consent_candidate):
        raise TransitionError(409, "Both participants must consent before going live")
