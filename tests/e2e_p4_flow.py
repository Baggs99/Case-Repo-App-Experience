"""
Purpose: P4 capstone live E2E over real HTTP against a running `main.py serve` —
         proves the daily-drill determinism -> attempt -> streak/dashboard loop,
         the free-now availability reciprocity across users a/b, and the offline
         drill-templates pack, then cleans up user a's own drill rows for today.
Inputs:  a running `.venv/bin/python main.py serve --port 8077` at 127.0.0.1:8077;
         dev seed (a@yale.edu / b@yale.edu, password caseroom-dev-1); .env DATABASE_URL.
Outputs: prints each step PASS/FAIL to stdout; deletes user a's drill_attempts rows
         for today (parameterized SQL); exits non-zero on any assertion failure.
Run:     .venv/bin/python main.py serve --port 8077 &   # one shell
         .venv/bin/python tests/e2e_p4_flow.py          # another shell
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import psycopg
import requests

BASE = "http://127.0.0.1:8077"
COOKIE_NAME = "case_repo_session"
PASSWORD = "caseroom-dev-1"

#: The wire-drill shape the iOS Drill model consumes (webapp/drills.generate_drill).
DRILL_KEYS = {"key", "drill_type", "prompt", "answer", "explanation", "numbers"}
#: Dashboard keys that predate P4 — must still be present alongside the new ones.
DASH_PREEXISTING = ("sessions_finalized", "streak_weeks", "next_session")


def ok(label: str, cond: bool, detail: str = "") -> None:
    status = "PASS" if cond else "FAIL"
    print(f"[{status}] {label} {detail}")
    if not cond:
        raise AssertionError(label)


def login(email: str) -> requests.Session:
    s = requests.Session()
    r = s.post(f"{BASE}/api/v1/auth/login", json={"email": email, "password": PASSWORD})
    ok(f"login {email}", r.status_code == 200, f"-> {r.status_code}")
    ok(f"login {email} sets cookie", COOKIE_NAME in s.cookies, "")
    return s


def me_id(s: requests.Session) -> int:
    r = s.get(f"{BASE}/api/v1/me")
    ok("GET /me", r.status_code == 200, f"-> {r.status_code}")
    return r.json()["id"]


def _db_url() -> str:
    """DATABASE_URL from the environment, or from the repo-root .env (the same
    zero-dependency KEY=VALUE file main.py reads at startup)."""
    if os.environ.get("DATABASE_URL"):
        return os.environ["DATABASE_URL"]
    env_path = Path(__file__).resolve().parents[1] / ".env"
    for line in env_path.read_text().splitlines():
        line = line.strip()
        if line.startswith("DATABASE_URL="):
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    raise RuntimeError("DATABASE_URL not set in env or .env")


def cleanup_today_attempts(user_id: int) -> int:
    """Delete only user_id's drill_attempts rows for the current UTC day so the
    shared dev DB stays clean. Parameterized; scoped to user + today."""
    with psycopg.connect(_db_url()) as conn:
        with conn.cursor() as cur:
            cur.execute(
                "DELETE FROM drill_attempts WHERE user_id = %(u)s"
                " AND (completed_at AT TIME ZONE 'UTC')::date"
                "     = (now() AT TIME ZONE 'UTC')::date;",
                {"u": user_id},
            )
            deleted = cur.rowcount
        conn.commit()
    return deleted


def main() -> None:
    a = login("a@yale.edu")
    a_id = me_id(a)
    b: requests.Session | None = None
    b_id: int | None = None
    try:
        # --- Daily drill: deterministic within the day, correct wire shape ---
        r1 = a.get(f"{BASE}/api/v1/drills/daily")
        ok("GET /drills/daily (1)", r1.status_code == 200, f"-> {r1.status_code}")
        r2 = a.get(f"{BASE}/api/v1/drills/daily")
        ok("GET /drills/daily (2)", r2.status_code == 200, f"-> {r2.status_code}")
        d1, d2 = r1.json(), r2.json()
        ok("daily drill identical on 2nd call (deterministic)", d1 == d2,
           f"-> date={d1.get('date')}")
        drill = d1["drill"]
        ok("daily drill has expected shape keys", DRILL_KEYS.issubset(drill.keys()),
           f"-> {sorted(drill.keys())}")

        # --- Record a server-sourced attempt for that exact drill ---
        r = a.post(f"{BASE}/api/v1/drills/attempts", json={
            "drill_type": drill["drill_type"],
            "source": "server",
            "drill_key": drill["key"],
            "correct": True,
        })
        ok("POST /drills/attempts (server, correct)", r.status_code == 204,
           f"-> {r.status_code} type={drill['drill_type']} key={drill['key']}")

        # --- Dashboard reflects the drill: done-today + a streak, old keys intact ---
        r = a.get(f"{BASE}/api/v1/dashboard")
        ok("GET /dashboard", r.status_code == 200, f"-> {r.status_code}")
        dash = r.json()
        ok("dashboard drill_done_today == true", dash.get("drill_done_today") is True,
           f"-> {dash.get('drill_done_today')}")
        ok("dashboard streak_days >= 1", isinstance(dash.get("streak_days"), int)
           and dash["streak_days"] >= 1, f"-> {dash.get('streak_days')}")
        for k in DASH_PREEXISTING:
            ok(f"dashboard pre-existing key present: {k}", k in dash, "")

        # --- Free-now availability: b free, then a free sees b, b sees a ---
        b = login("b@yale.edu")
        b_id = me_id(b)
        r = b.put(f"{BASE}/api/v1/availability", json={"minutes": 60})
        ok("b PUT /availability {60}", r.status_code == 200, f"-> {r.status_code}")

        # (login a) a toggles free — a fresh toggle, so its response lists others
        r = a.put(f"{BASE}/api/v1/availability", json={"minutes": 30})
        ok("a PUT /availability {30}", r.status_code == 200, f"-> {r.status_code}")
        others = r.json().get("others", [])
        ok("a's PUT response others contains b",
           any(o.get("user_id") == b_id for o in others),
           f"-> others user_ids={[o.get('user_id') for o in others]}")

        r = b.get(f"{BASE}/api/v1/availability")
        ok("b GET /availability", r.status_code == 200, f"-> {r.status_code}")
        b_others = r.json().get("others", [])
        ok("b's GET others contains a",
           any(o.get("user_id") == a_id for o in b_others),
           f"-> others user_ids={[o.get('user_id') for o in b_others]}")

        # --- a clears availability -> b no longer sees a ---
        r = a.delete(f"{BASE}/api/v1/availability")
        ok("a DELETE /availability -> 204", r.status_code == 204, f"-> {r.status_code}")
        r = b.get(f"{BASE}/api/v1/availability")
        b_after = r.json().get("others", [])
        ok("after a DELETE, b's others no longer lists a",
           all(o.get("user_id") != a_id for o in b_after),
           f"-> others user_ids={[o.get('user_id') for o in b_after]}")

        # --- Offline drill-templates pack ---
        r = a.get(f"{BASE}/api/v1/drills/templates")
        ok("GET /drills/templates", r.status_code == 200, f"-> {r.status_code}")
        tpl = r.json()
        ok("templates payload has version", "version" in tpl,
           f"-> version={tpl.get('version')}")
        ok("templates count == 32", len(tpl.get("templates", [])) == 32,
           f"-> {len(tpl.get('templates', []))}")

        print("\nALL STEPS PASSED")
    finally:
        # Keep the shared dev DB clean regardless of outcome.
        if b is not None:
            try:
                b.delete(f"{BASE}/api/v1/availability")
            except requests.RequestException:
                pass
        try:
            deleted = cleanup_today_attempts(a_id)
            print(f"[cleanup] deleted {deleted} drill_attempts row(s) for user "
                  f"{a_id} (today)")
        except Exception as exc:  # cleanup must never mask the test verdict
            print(f"[cleanup] WARNING: could not delete drill_attempts: {exc}")


if __name__ == "__main__":
    try:
        main()
    except AssertionError:
        sys.exit(1)
