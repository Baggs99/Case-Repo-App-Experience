# Task 2 diff package (BASE 682acec .. HEAD)

## git log
afdd389 Add user_firms tracking table (migration 027) and repo

## diff --stat
 db/migrations/027_user_firms.sql  |  23 +++++++
 tests/test_b7_user_firms.py       | 108 +++++++++++++++++++++++++++++++
 webapp/repositories/user_firms.py | 133 ++++++++++++++++++++++++++++++++++++++
 3 files changed, 264 insertions(+)

## full diff
diff --git a/db/migrations/027_user_firms.sql b/db/migrations/027_user_firms.sql
new file mode 100644
index 0000000..d40d6a2
--- /dev/null
+++ b/db/migrations/027_user_firms.sql
@@ -0,0 +1,23 @@
+-- ============================================================================
+-- 027 — per-user firm tracking + post-deadline prompt state (roadmap §B7)
+-- ----------------------------------------------------------------------------
+-- Apply with:  psql -d <db> -v ON_ERROR_STOP=1 -f db/migrations/027_user_firms.sql
+-- Idempotent:  CREATE TABLE IF NOT EXISTS.
+--
+-- status flow: 'tracking' (default) → Offer='offer' / No offer='rejected' /
+-- Waiting='interviewed'(+snooze_until). "Didn't interview" DELETEs the row
+-- (DV-B7-1: drops off the line). 'admitted' is a recordable status kept for
+-- B6 (data only — nothing in B7 gates on it). snooze_until (DV-B7-2) both
+-- re-asks Waiting in a week and throttles the auto deadline-prompt to weekly.
+-- ============================================================================
+
+CREATE TABLE IF NOT EXISTS user_firms (
+    user_id             INTEGER     NOT NULL REFERENCES users(id) ON DELETE CASCADE,
+    firm_id             INTEGER     NOT NULL REFERENCES firms(id) ON DELETE CASCADE,
+    added_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
+    status              TEXT        NOT NULL DEFAULT 'tracking'
+        CHECK (status IN ('tracking', 'interviewed', 'offer', 'rejected', 'admitted')),
+    result_recorded_at  TIMESTAMPTZ,
+    snooze_until        TIMESTAMPTZ,
+    PRIMARY KEY (user_id, firm_id)
+);
diff --git a/tests/test_b7_user_firms.py b/tests/test_b7_user_firms.py
new file mode 100644
index 0000000..a78c8e4
--- /dev/null
+++ b/tests/test_b7_user_firms.py
@@ -0,0 +1,108 @@
+"""B7 Task 2: per-user firm tracking repo. Needs seeded dev Postgres."""
+
+from __future__ import annotations
+
+import datetime
+import unittest
+
+from tests.test_ws_integration import _DB_URL, _HTTPX, _READY
+
+
+@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
+@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
+class TestUserFirmsRepo(unittest.TestCase):
+    @classmethod
+    def setUpClass(cls):
+        # Enter the app lifespan so the shared connection pool is initialized
+        # (repo functions go through webapp.db.get_pool()). Must precede any
+        # pool-backed call (firms_repo.list_firms below). Matches test_b7_firms.
+        from fastapi.testclient import TestClient
+        from webapp.main import app
+
+        cls._ctx = TestClient(app)
+        cls._ctx.__enter__()
+
+        import psycopg
+        from webapp.repositories import firms as firms_repo
+        with psycopg.connect(_DB_URL) as conn:
+            with conn.cursor() as cur:
+                cur.execute("SELECT id FROM users WHERE email = 'a@yale.edu';")
+                cls.uid = cur.fetchone()[0]
+        cls.mck = next(f for f in firms_repo.list_firms() if f["slug"] == "mckinsey")["id"]
+        cls.rb = next(f for f in firms_repo.list_firms() if f["slug"] == "roland-berger")["id"]
+
+    @classmethod
+    def tearDownClass(cls):
+        cls._ctx.__exit__(None, None, None)
+
+    def tearDown(self):
+        import psycopg
+        with psycopg.connect(_DB_URL) as conn:
+            with conn.cursor() as cur:
+                cur.execute("DELETE FROM user_firms WHERE user_id = %s;", (self.uid,))
+
+    def test_track_is_idempotent_and_listable(self):
+        from webapp.repositories import user_firms as uf
+        row = uf.track(self.uid, self.mck)
+        self.assertEqual(row["status"], "tracking")
+        uf.track(self.uid, self.mck)  # second track = no-op
+        tracked = uf.list_tracked(self.uid)
+        self.assertEqual(len(tracked), 1)
+        self.assertEqual(tracked[0]["slug"], "mckinsey")
+        self.assertTrue(uf.is_tracked(self.uid, self.mck))
+
+    def test_untrack_removes(self):
+        from webapp.repositories import user_firms as uf
+        uf.track(self.uid, self.mck)
+        self.assertEqual(uf.untrack(self.uid, self.mck), 1)
+        self.assertFalse(uf.is_tracked(self.uid, self.mck))
+        self.assertEqual(uf.untrack(self.uid, self.mck), 0)
+
+    def test_record_result_offer_and_rejected(self):
+        from webapp.repositories import user_firms as uf
+        uf.track(self.uid, self.mck)
+        row = uf.record_result(self.uid, self.mck, "offer")
+        self.assertEqual(row["status"], "offer")
+        self.assertIsNotNone(row["result_recorded_at"])
+        self.assertIsNone(row["snooze_until"])
+        row2 = uf.record_result(self.uid, self.mck, "rejected")
+        self.assertEqual(row2["status"], "rejected")
+
+    def test_record_result_untracked_returns_none(self):
+        from webapp.repositories import user_firms as uf
+        self.assertIsNone(uf.record_result(self.uid, self.mck, "offer"))
+
+    def test_mark_waiting_sets_snooze(self):
+        from webapp.repositories import user_firms as uf
+        uf.track(self.uid, self.mck)
+        row = uf.mark_waiting(self.uid, self.mck, days=7)
+        self.assertEqual(row["status"], "interviewed")
+        self.assertIsNotNone(row["snooze_until"])
+
+    def test_firms_needing_prompt_finds_passed_untouched(self):
+        from webapp.repositories import user_firms as uf
+        uf.track(self.uid, self.rb)          # Roland Berger deadline = 2026-07-02
+        rows = uf.firms_needing_prompt(datetime.date(2026, 7, 17))
+        mine = [r for r in rows if r["user_id"] == self.uid and r["firm_id"] == self.rb]
+        self.assertEqual(len(mine), 1)
+        self.assertIn("Roland", mine[0]["firm_name"])
+
+    def test_snoozed_firm_not_prompted(self):
+        from webapp.repositories import user_firms as uf
+        uf.track(self.uid, self.rb)
+        uf.mark_prompted(self.uid, self.rb,
+                         snooze_until=datetime.datetime.now(datetime.timezone.utc)
+                         + datetime.timedelta(days=7))
+        rows = uf.firms_needing_prompt(datetime.date(2026, 7, 17))
+        self.assertFalse([r for r in rows if r["firm_id"] == self.rb])
+
+    def test_non_tracking_status_not_prompted(self):
+        from webapp.repositories import user_firms as uf
+        uf.track(self.uid, self.rb)
+        uf.record_result(self.uid, self.rb, "offer")  # status='offer' → done
+        rows = uf.firms_needing_prompt(datetime.date(2026, 7, 17))
+        self.assertFalse([r for r in rows if r["firm_id"] == self.rb])
+
+
+if __name__ == "__main__":
+    unittest.main()
diff --git a/webapp/repositories/user_firms.py b/webapp/repositories/user_firms.py
new file mode 100644
index 0000000..d8629cf
--- /dev/null
+++ b/webapp/repositories/user_firms.py
@@ -0,0 +1,133 @@
+"""
+Purpose: Per-user firm tracking + post-deadline prompt state (migration 027)
+  for the B7 timeline.
+Inputs:  user_id, firm_id, status/snooze values; user_firms + firms tables.
+Outputs: dict rows; UPDATE/DELETE side effects on user_firms.
+Run:     from webapp.repositories import user_firms; user_firms.track(uid, fid)
+"""
+
+from __future__ import annotations
+
+import datetime
+
+from psycopg.rows import dict_row
+
+from webapp.db import get_pool
+
+_ROW = "user_id, firm_id, status, added_at, result_recorded_at, snooze_until"
+
+
+def track(user_id: int, firm_id: int) -> dict:
+    """Start tracking a firm. Idempotent — a second track is a no-op that
+    returns the existing row (a recorded result is never silently reset)."""
+    with get_pool().connection() as conn:
+        with conn.cursor(row_factory=dict_row) as cur:
+            cur.execute(
+                f"INSERT INTO user_firms (user_id, firm_id) VALUES (%(u)s, %(f)s)"
+                f" ON CONFLICT (user_id, firm_id) DO NOTHING RETURNING {_ROW};",
+                {"u": user_id, "f": firm_id})
+            row = cur.fetchone()
+            if row is None:                      # already tracked
+                cur.execute(
+                    f"SELECT {_ROW} FROM user_firms"
+                    f" WHERE user_id = %(u)s AND firm_id = %(f)s;",
+                    {"u": user_id, "f": firm_id})
+                row = cur.fetchone()
+            return row
+
+
+def untrack(user_id: int, firm_id: int) -> int:
+    with get_pool().connection() as conn:
+        with conn.cursor() as cur:
+            cur.execute(
+                "DELETE FROM user_firms WHERE user_id = %(u)s AND firm_id = %(f)s;",
+                {"u": user_id, "f": firm_id})
+            return cur.rowcount
+
+
+def is_tracked(user_id: int, firm_id: int) -> bool:
+    with get_pool().connection() as conn:
+        with conn.cursor() as cur:
+            cur.execute(
+                "SELECT 1 FROM user_firms WHERE user_id = %(u)s AND firm_id = %(f)s;",
+                {"u": user_id, "f": firm_id})
+            return cur.fetchone() is not None
+
+
+def get(user_id: int, firm_id: int) -> dict | None:
+    with get_pool().connection() as conn:
+        with conn.cursor(row_factory=dict_row) as cur:
+            cur.execute(
+                f"SELECT {_ROW} FROM user_firms"
+                f" WHERE user_id = %(u)s AND firm_id = %(f)s;",
+                {"u": user_id, "f": firm_id})
+            return cur.fetchone()
+
+
+def list_tracked(user_id: int) -> list[dict]:
+    """Tracked firms with their firm name/slug, soonest deadline computed by
+    the caller. Ordered by added_at for a stable list."""
+    with get_pool().connection() as conn:
+        with conn.cursor(row_factory=dict_row) as cur:
+            cur.execute(
+                "SELECT uf.firm_id, f.name, f.slug, uf.status, uf.added_at,"
+                "       uf.snooze_until, uf.result_recorded_at"
+                " FROM user_firms uf JOIN firms f ON f.id = uf.firm_id"
+                " WHERE uf.user_id = %(u)s ORDER BY uf.added_at;",
+                {"u": user_id})
+            return cur.fetchall()
+
+
+def record_result(user_id: int, firm_id: int, status: str) -> dict | None:
+    """Offer='offer' / No offer='rejected' — stamps result_recorded_at, clears
+    any snooze. Returns None if the user doesn't track the firm (IDOR guard)."""
+    if status not in ("offer", "rejected"):
+        raise ValueError(f"record_result status must be offer|rejected, got {status!r}")
+    with get_pool().connection() as conn:
+        with conn.cursor(row_factory=dict_row) as cur:
+            cur.execute(
+                f"UPDATE user_firms SET status = %(s)s, result_recorded_at = NOW(),"
+                f" snooze_until = NULL"
+                f" WHERE user_id = %(u)s AND firm_id = %(f)s RETURNING {_ROW};",
+                {"u": user_id, "f": firm_id, "s": status})
+            return cur.fetchone()
+
+
+def mark_waiting(user_id: int, firm_id: int, days: int = 7) -> dict | None:
+    """Waiting → interviewed + re-ask in `days`. Returns None if untracked."""
+    with get_pool().connection() as conn:
+        with conn.cursor(row_factory=dict_row) as cur:
+            cur.execute(
+                f"UPDATE user_firms SET status = 'interviewed',"
+                f" snooze_until = NOW() + make_interval(days => %(d)s)"
+                f" WHERE user_id = %(u)s AND firm_id = %(f)s RETURNING {_ROW};",
+                {"u": user_id, "f": firm_id, "d": days})
+            return cur.fetchone()
+
+
+def firms_needing_prompt(as_of: datetime.date) -> list[dict]:
+    """Still-tracking firms whose deadline has passed and that aren't snoozed —
+    the deadline-passed push targets. NOW() (not as_of) gates the snooze so a
+    real-time snooze window is honored."""
+    with get_pool().connection() as conn:
+        with conn.cursor(row_factory=dict_row) as cur:
+            cur.execute(
+                "SELECT DISTINCT uf.user_id, uf.firm_id, f.name AS firm_name"
+                " FROM user_firms uf JOIN firms f ON f.id = uf.firm_id"
+                " WHERE uf.status = 'tracking'"
+                "   AND (uf.snooze_until IS NULL OR uf.snooze_until < NOW())"
+                "   AND EXISTS (SELECT 1 FROM firm_deadlines d"
+                "               WHERE d.firm_id = uf.firm_id"
+                "                 AND d.deadline_date < %(as_of)s);",
+                {"as_of": as_of})
+            return cur.fetchall()
+
+
+def mark_prompted(user_id: int, firm_id: int, snooze_until) -> None:
+    """Throttle the auto prompt: set snooze_until (typically NOW()+7d)."""
+    with get_pool().connection() as conn:
+        with conn.cursor() as cur:
+            cur.execute(
+                "UPDATE user_firms SET snooze_until = %(s)s"
+                " WHERE user_id = %(u)s AND firm_id = %(f)s;",
+                {"u": user_id, "f": firm_id, "s": snooze_until})
