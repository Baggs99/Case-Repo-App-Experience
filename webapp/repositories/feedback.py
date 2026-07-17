"""
Feedback repository — rubric drafts, grade computation, and the finalize
transaction (CaseRoom spec Phase 7, §4.5).

The draft lives in feedback.rubric_json from the interviewer's first save.
Finalize is ONE transaction: it validates debrief + interviewer under a row
lock, stamps grade/finalized_at, inserts the burned row, removes the case
from the candidate's want-queue, and flips the session to 'finalized' —
deliberately outside the generic /state endpoint (see practice_states).
"""

from __future__ import annotations

from decimal import Decimal, ROUND_HALF_UP
from typing import Optional

from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from webapp.db import get_pool
from webapp.practice_states import TransitionError


def get_template_items(template_id: int) -> list[dict]:
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT items_json FROM rubric_templates WHERE id = %s;",
                        (template_id,))
            row = cur.fetchone()
            return row[0] if row else []


def validate_draft(draft: dict, template_items: list[dict]) -> None:
    """Draft shape: {"items": {item_id: {"points": n, "note": str}},
    "notes_md": str}. Raises TransitionError(400) on unknown ids or
    out-of-range points, so a buggy client can't corrupt the record."""
    by_id = {item["id"]: item for item in template_items}
    items = draft.get("items", {})
    if not isinstance(items, dict):
        raise TransitionError(400, "items must be an object keyed by item id")
    for item_id, entry in items.items():
        tmpl = by_id.get(item_id)
        if tmpl is None:
            raise TransitionError(400, f"Unknown rubric item {item_id!r}")
        points = entry.get("points", 0)
        if not isinstance(points, (int, float)) or isinstance(points, bool):
            raise TransitionError(400, f"points for {item_id!r} must be a number")
        if not 0 <= points <= tmpl["max_points"]:
            raise TransitionError(
                400, f"points for {item_id!r} must be 0–{tmpl['max_points']}")
        note = entry.get("note", "")
        if not isinstance(note, str) or len(note) > 2000:
            raise TransitionError(400, f"note for {item_id!r} must be a short string")
    notes = draft.get("notes_md", "")
    if not isinstance(notes, str) or len(notes) > 20000:
        raise TransitionError(400, "notes_md must be a string")


def compute_grade(draft: dict, template_items: list[dict]) -> float:
    """A5: grade = 5 × Σpoints / Σmax_points over the template, rounded to
    one decimal. Unscored items count as 0."""
    total_max = sum(item["max_points"] for item in template_items)
    if total_max == 0:
        return 0.0
    items = draft.get("items", {})
    total = sum(items.get(item["id"], {}).get("points", 0)
                for item in template_items)
    grade = Decimal(5 * total) / Decimal(total_max)
    return float(grade.quantize(Decimal("0.1"), rounding=ROUND_HALF_UP))


def get_feedback(session_id: int) -> Optional[dict]:
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute("SELECT * FROM feedback WHERE session_id = %s;",
                        (session_id,))
            return cur.fetchone()


def save_draft(session_id: int, draft: dict) -> dict:
    """Upsert the rubric draft (interviewer autosave). Caller validates the
    draft and the session state; the WHERE finalized_at IS NULL backstop
    means a racing finalize can never be overwritten."""
    rubric = {"items": draft.get("items", {})}
    notes = draft.get("notes_md", "")
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "INSERT INTO feedback (session_id, rubric_json, notes_md)"
                " VALUES (%s, %s, %s)"
                " ON CONFLICT (session_id) DO UPDATE"
                " SET rubric_json = EXCLUDED.rubric_json,"
                "     notes_md = EXCLUDED.notes_md"
                " WHERE feedback.finalized_at IS NULL"
                " RETURNING *;",
                (session_id, Jsonb(rubric), notes),
            )
            row = cur.fetchone()
            if row is None:
                raise TransitionError(409, "Feedback is finalized and read-only")
            return row


def finalize(session_id: int, actor_id: int,
             grade_override: Optional[float]) -> dict:
    """The Phase 7 transaction. Returns the finalized feedback row."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT ps.*, rt.items_json FROM practice_sessions ps"
                " JOIN rubric_templates rt ON rt.id = ps.rubric_template_id"
                " WHERE ps.id = %s FOR UPDATE OF ps;",
                (session_id,),
            )
            session = cur.fetchone()
            if session is None:
                raise TransitionError(404, "No such session")
            if actor_id != session["interviewer_id"]:
                raise TransitionError(403, "Only the interviewer may finalize")
            if session["state"] != "debrief":
                raise TransitionError(
                    409, f"Finalize requires debrief (session is {session['state']})")

            cur.execute("SELECT * FROM feedback WHERE session_id = %s FOR UPDATE;",
                        (session_id,))
            feedback = cur.fetchone()
            if feedback is None:
                cur.execute(
                    "INSERT INTO feedback (session_id, rubric_json, notes_md)"
                    " VALUES (%s, %s, '') RETURNING *;",
                    (session_id, Jsonb({"items": {}})),
                )
                feedback = cur.fetchone()

            template_items = session["items_json"]
            if grade_override is not None:
                grade = round(float(grade_override), 1)
            else:
                grade = compute_grade(feedback["rubric_json"], template_items)

            cur.execute(
                "UPDATE feedback SET grade = %s, finalized_at = NOW()"
                " WHERE session_id = %s RETURNING *;",
                (grade, session_id),
            )
            feedback = cur.fetchone()

            cur.execute(
                "INSERT INTO burned (user_id, case_id, session_id)"
                " VALUES (%s, %s, %s) ON CONFLICT (user_id, case_id) DO NOTHING;",
                (session["candidate_id"], session["case_id"], session_id),
            )
            cur.execute(
                "DELETE FROM queue_want WHERE user_id = %s AND case_id = %s;",
                (session["candidate_id"], session["case_id"]),
            )
            cur.execute(
                "UPDATE practice_sessions"
                " SET state = 'finalized', state_changed_at = NOW()"
                " WHERE id = %s;",
                (session_id,),
            )
            return feedback


def is_burned(user_id: int, case_id: int) -> bool:
    """A6: has this user already received this case in a finalized session?"""
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT 1 FROM burned WHERE user_id = %s AND case_id = %s;",
                (user_id, case_id),
            )
            return cur.fetchone() is not None


class RecapGateError(TransitionError):
    """Candidate has an unread (finalized-but-unclosed) recap and cannot start
    or accept a new case as candidate (spec §6.4). Subclasses TransitionError
    (status 409) so generic handlers still 409; candidate-entry routes catch it
    explicitly to emit {"blocked_by_recap": session_id}."""

    def __init__(self, session_id: int):
        super().__init__(409, "Finish your last recap before starting a new case")
        self.blocked_by_recap = session_id


def candidate_gate(user_id: int) -> Optional[int]:
    """The oldest session_id whose feedback is finalized but not yet closed and
    where user_id sat as candidate — i.e. the recap that blocks a new candidate
    seat. None when nothing blocks (never finalized ⇒ no gate)."""
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT ps.id FROM feedback f"
                " JOIN practice_sessions ps ON ps.id = f.session_id"
                " WHERE ps.candidate_id = %s"
                "   AND f.finalized_at IS NOT NULL AND f.closed_at IS NULL"
                " ORDER BY f.finalized_at ASC LIMIT 1;",
                (user_id,),
            )
            row = cur.fetchone()
            return row[0] if row else None


def assert_candidate_gate_clear(user_id: int) -> None:
    """Raise RecapGateError if user_id has an open recap (candidate-seat gate)."""
    blocked = candidate_gate(user_id)
    if blocked is not None:
        raise RecapGateError(blocked)


def list_unread_recaps(user_id: int) -> list[dict]:
    """Finalized-but-unclosed recaps where user_id was candidate, oldest-first
    (the order they clear). case_title may be NULL only for legacy rows."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT ps.id AS session_id, ps.case_id, c.case_title,"
                "       f.grade, f.finalized_at, f.viewed_at,"
                "       COALESCE(ui.display_name,"
                "                split_part(ui.email::text, '@', 1)) AS interviewer_name"
                " FROM feedback f"
                " JOIN practice_sessions ps ON ps.id = f.session_id"
                " JOIN users ui ON ui.id = ps.interviewer_id"
                " LEFT JOIN cases c ON c.id = ps.case_id"
                " WHERE ps.candidate_id = %s"
                "   AND f.finalized_at IS NOT NULL AND f.closed_at IS NULL"
                " ORDER BY f.finalized_at ASC;",
                (user_id,),
            )
            return cur.fetchall()


def mark_recap_viewed(session_id: int) -> None:
    """Stamp viewed_at once (first view wins) for a finalized recap."""
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE feedback SET viewed_at = COALESCE(viewed_at, NOW())"
                " WHERE session_id = %s AND finalized_at IS NOT NULL;",
                (session_id,),
            )


def close_recap(session_id: int, *, case_rating: int,
                feedback_thumbs: Optional[bool], record_thumbs: bool) -> dict:
    """Close-out: stamp closed_at + the required 1-5 case_rating (and viewed_at
    if unset). feedback_thumbs is stored only when record_thumbs (interviewer is
    a real, non-guest user); otherwise NULL. First close only — a re-close 409s
    (the gate is already cleared; recaps stay re-readable via GET feedback)."""
    if not (1 <= case_rating <= 5):
        raise TransitionError(400, "case_rating must be 1-5")
    thumbs = feedback_thumbs if record_thumbs else None
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute("SELECT finalized_at, closed_at FROM feedback"
                        " WHERE session_id = %s FOR UPDATE;", (session_id,))
            row = cur.fetchone()
            if row is None or row["finalized_at"] is None:
                raise TransitionError(409, "No finalized recap to close")
            if row["closed_at"] is not None:
                raise TransitionError(409, "Recap already closed")
            cur.execute(
                "UPDATE feedback SET closed_at = NOW(),"
                "   viewed_at = COALESCE(viewed_at, NOW()),"
                "   case_rating = %s, feedback_thumbs = %s"
                " WHERE session_id = %s RETURNING *;",
                (case_rating, thumbs, session_id),
            )
            return cur.fetchone()
