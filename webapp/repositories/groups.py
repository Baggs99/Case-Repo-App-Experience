"""
Purpose: Community groups for B6 — create (creator=admin), join by invite code,
         leave, transfer admin, and membership/role queries.
Inputs:  group name, invite code, user ids; reads/writes groups + group_members
         + school_leaders; reads users.school_id.
Outputs: INSERT/UPDATE/DELETE on group tables; dict rows for the API layer.
Run:     from webapp.repositories import groups; groups.create_group("C-14", uid)
"""

from __future__ import annotations

import psycopg
from psycopg.rows import dict_row

from webapp.db import get_pool
from webapp.repositories.pairing_tokens import _gen_short_code

_MEMBER = ("gm.user_id,"
           " COALESCE(u.display_name, split_part(u.email::text, '@', 1)) AS display_name,"
           " u.photo_key, gm.role")


def create_group(name: str, creator_id: int) -> dict:
    """Create a group, stamp the creator school_id, mint a unique invite code,
    and make the creator the admin. Returns the group + role."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute("SELECT school_id FROM users WHERE id = %s;", (creator_id,))
            row = cur.fetchone()
            school_id = row["school_id"] if row else None
            group_id = None
            for _ in range(5):  # collision-retry, mirrors pairing_tokens.mint_token
                code = _gen_short_code(6)
                try:
                    cur.execute(
                        "INSERT INTO groups (name, school_id, invite_code, created_by)"
                        " VALUES (%(n)s, %(s)s, %(c)s, %(u)s) RETURNING id;",
                        {"n": name, "s": school_id, "c": code, "u": creator_id})
                    group_id = cur.fetchone()["id"]
                    break
                except psycopg.errors.UniqueViolation:
                    conn.rollback()
            if group_id is None:
                raise RuntimeError("could not mint a unique invite code")
            cur.execute(
                "INSERT INTO group_members (group_id, user_id, role)"
                " VALUES (%s, %s, 'admin');", (group_id, creator_id))
            return {"id": group_id, "name": name, "school_id": school_id,
                    "invite_code": code, "role": "admin"}


def join_by_code(invite_code: str, user_id: int) -> dict | None:
    """Join the group with this code. None if the code is unknown."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT id, name, school_id, invite_code FROM groups"
                " WHERE invite_code = %s;", (invite_code,))
            g = cur.fetchone()
            if g is None:
                return None
            cur.execute(
                "INSERT INTO group_members (group_id, user_id, role)"
                " VALUES (%s, %s, 'member') ON CONFLICT (group_id, user_id) DO NOTHING;",
                (g["id"], user_id))
            already = cur.rowcount == 0
            # Read the role on THIS cursor — a fresh pooled connection could not
            # see the uncommitted INSERT (READ COMMITTED) and would return None.
            cur.execute("SELECT role FROM group_members WHERE group_id=%s AND user_id=%s;",
                        (g["id"], user_id))
            role = cur.fetchone()["role"]
            return {"id": g["id"], "name": g["name"], "school_id": g["school_id"],
                    "invite_code": g["invite_code"], "role": role,
                    "already_member": already}


def leave_group(group_id: int, user_id: int) -> str:
    """Leave a group. Returns 'deleted' when the last member leaves (group row
    removed), else 'left'. Raises PermissionError when a sole admin tries to
    leave while other members remain (must transfer_admin first)."""
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute("SELECT role FROM group_members WHERE group_id=%s AND user_id=%s;",
                        (group_id, user_id))
            me = cur.fetchone()
            if me is None:
                return "left"  # not a member; idempotent
            cur.execute("SELECT COUNT(*) AS n FROM group_members WHERE group_id=%s;",
                        (group_id,))
            total = cur.fetchone()["n"]
            if total == 1:
                cur.execute("DELETE FROM groups WHERE id=%s;", (group_id,))  # cascades members
                return "deleted"
            if me["role"] == "admin":
                cur.execute("SELECT COUNT(*) AS n FROM group_members"
                            " WHERE group_id=%s AND role='admin';", (group_id,))
                if cur.fetchone()["n"] == 1:
                    raise PermissionError("transfer admin before leaving")
            cur.execute("DELETE FROM group_members WHERE group_id=%s AND user_id=%s;",
                        (group_id, user_id))
            return "left"


def transfer_admin(group_id: int, from_user_id: int, to_user_id: int) -> bool:
    """Demote from_user to member and promote to_user to admin. Caller checks
    from_user is an admin. False when to_user is not a member. Transferring to
    self is a no-op (keeps the caller admin) — never leaves the group adminless."""
    if from_user_id == to_user_id:
        return True
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute("UPDATE group_members SET role='admin'"
                        " WHERE group_id=%s AND user_id=%s;", (group_id, to_user_id))
            if cur.rowcount == 0:
                return False
            cur.execute("UPDATE group_members SET role='member'"
                        " WHERE group_id=%s AND user_id=%s;", (group_id, from_user_id))
            return True


def list_my_groups(user_id: int) -> list[dict]:
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT g.id, g.name, g.school_id, g.invite_code, gm.role"
                " FROM group_members gm JOIN groups g ON g.id = gm.group_id"
                " WHERE gm.user_id = %s ORDER BY g.created_at DESC;", (user_id,))
            return cur.fetchall()


def get_group(group_id: int) -> dict | None:
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                "SELECT id, name, school_id, invite_code, created_by, created_at"
                " FROM groups WHERE id = %s;", (group_id,))
            return cur.fetchone()


def list_members(group_id: int) -> list[dict]:
    with get_pool().connection() as conn:
        with conn.cursor(row_factory=dict_row) as cur:
            cur.execute(
                f"SELECT {_MEMBER} FROM group_members gm JOIN users u ON u.id = gm.user_id"
                f" WHERE gm.group_id = %s ORDER BY gm.role, display_name;", (group_id,))
            return cur.fetchall()


def member_role(group_id: int, user_id: int) -> str | None:
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT role FROM group_members WHERE group_id=%s AND user_id=%s;",
                        (group_id, user_id))
            row = cur.fetchone()
            return row[0] if row else None


def is_member(group_id: int, user_id: int) -> bool:
    return member_role(group_id, user_id) is not None


def is_admin(group_id: int, user_id: int) -> bool:
    return member_role(group_id, user_id) == "admin"


def admin_ids(group_id: int) -> list[int]:
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT user_id FROM group_members"
                        " WHERE group_id=%s AND role='admin';", (group_id,))
            return [r[0] for r in cur.fetchall()]


def is_school_leader(user_id: int, school_id: int) -> bool:
    with get_pool().connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT 1 FROM school_leaders WHERE user_id=%s AND school_id=%s;",
                        (user_id, school_id))
            return cur.fetchone() is not None
