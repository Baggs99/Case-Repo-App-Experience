# Task 6 diff package (BASE 40d9597 .. HEAD)

## git log
53f5e82 Extend /api/v1/dashboard with diagnostic + timeline summary (additive)

## diff --stat
 tests/test_b7_timeline_api.py | 44 +++++++++++++++++++++++++++++++++++++++++++
 webapp/routes/api_v1.py       |  6 ++++++
 2 files changed, 50 insertions(+)

## full diff
diff --git a/tests/test_b7_timeline_api.py b/tests/test_b7_timeline_api.py
index b81f69a..9ea3912 100644
--- a/tests/test_b7_timeline_api.py
+++ b/tests/test_b7_timeline_api.py
@@ -143,14 +143,58 @@ class TestTimelineApi(unittest.TestCase):
         # Alice's row is untouched.
         tl = self.alice.get("/api/v1/timeline").json()
         self.assertEqual(tl["firms"][0]["status"], "tracking")
 
     def test_untrack_is_per_user(self):
         self.alice.post("/api/v1/timeline/firms", json={"firm_id": self.rb})
         # Bob deleting the same firm_id only touches his own (absent) row.
         self.assertEqual(
             self.bob.delete(f"/api/v1/timeline/firms/{self.rb}").status_code, 204)
         self.assertEqual(len(self.alice.get("/api/v1/timeline").json()["firms"]), 1)
 
 
+@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
+@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
+class TestDashboardTimelineKeys(unittest.TestCase):
+    @classmethod
+    def setUpClass(cls):
+        from fastapi.testclient import TestClient
+        from webapp.main import app
+        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session
+        from webapp.repositories import firms as firms_repo
+        cls._ctx = TestClient(app)
+        cls.alice = cls._ctx.__enter__()
+        import psycopg
+        with psycopg.connect(_DB_URL) as conn:
+            with conn.cursor() as cur:
+                cur.execute("SELECT id FROM users WHERE email = 'a@yale.edu';")
+                cls.aid = cur.fetchone()[0]
+        s = create_session(cls.aid, user_agent="b7-dash", ip_address=None)
+        cls.alice.cookies.set(SESSION_COOKIE_NAME, s.id)
+        cls.mck = next(f for f in firms_repo.list_firms() if f["slug"] == "mckinsey")["id"]
+
+    @classmethod
+    def tearDownClass(cls):
+        import psycopg
+        with psycopg.connect(_DB_URL) as conn:
+            with conn.cursor() as cur:
+                cur.execute("DELETE FROM user_firms WHERE user_id = %s;", (cls.aid,))
+        cls._ctx.__exit__(None, None, None)
+
+    def test_dashboard_has_diagnostic_and_timeline(self):
+        self.alice.post("/api/v1/timeline/firms", json={"firm_id": self.mck})
+        d = self.alice.get("/api/v1/dashboard").json()
+        # Additive — existing B4 keys still present.
+        self.assertIn("recommendations", d)
+        self.assertIn("dimension_averages", d)
+        # New B7 keys.
+        self.assertIn("diagnostic", d)
+        self.assertEqual(set(d["diagnostic"]) >= {
+            "cases_done_60d", "dimensions", "strengths", "weaknesses",
+            "focus_dimension", "trend"}, True)
+        self.assertIn("timeline", d)
+        self.assertEqual(d["timeline"]["tracked_count"], 1)
+        self.assertEqual(d["timeline"]["next_deadline"]["slug"], "mckinsey")
+
+
 if __name__ == "__main__":
     unittest.main()
diff --git a/webapp/routes/api_v1.py b/webapp/routes/api_v1.py
index f05a045..28e7993 100644
--- a/webapp/routes/api_v1.py
+++ b/webapp/routes/api_v1.py
@@ -17,24 +17,25 @@ from pydantic import BaseModel, Field
 from webapp.auth.dependencies import require_auth_api
 from webapp.auth.sessions import (
     SESSION_COOKIE_NAME,
     attach_session_cookie,
     clear_session_cookie,
     create_session,
     destroy_session,
 )
 from webapp.auth.users import User, authenticate
 from webapp.csrf import require_same_origin
 from webapp.db import get_pool
 from webapp import drills
+from webapp import timeline_service
 from webapp.preview_urls import preview_page_urls
 from webapp.push.events import push_to_user
 from webapp.repositories import availability as availability_repo
 from webapp.repositories import dashboard as dashboard_repo
 from webapp.repositories import device_tokens as repo
 from webapp.repositories import drill_attempts as drills_repo
 from webapp.repositories import live_activity_tokens as live_activity_repo
 from webapp.repositories import practice_sessions as sessions_repo
 from webapp.repositories import proposals as proposals_repo
 from webapp.repositories.cases import SearchFilters, get_case_by_id, search_cases
 
 router = APIRouter(prefix="/api/v1")
@@ -365,13 +366,18 @@ def dashboard(user: User = Depends(require_auth_api)):
     next_session = _upcoming_session_json(upcoming[0]) if upcoming else None
     return {
         "sessions_finalized": stats["sessions_finalized"],
         "streak_weeks": stats["streak_weeks"],
         "next_session": next_session,
         "streak_days": drills_repo.streak_days(user.id),
         "drill_done_today": drills_repo.attempted_today(user.id),
         # B4 §7 Home card: the recommendation engine's two candidate-facing
         # surfaces travel on the dashboard payload (dimension_averages =
         # existing web shape, recommendations = canonical item shape).
         "dimension_averages": dashboard_repo.dimension_averages(user.id),
         "recommendations": dashboard_repo.recommendations(user.id),
+        # B7 §4 Home: diagnostic block + timeline summary (next deadline across
+        # tracked firms). Additive — no existing key changes.
+        "diagnostic": dashboard_repo.diagnostic(user.id),
+        "timeline": timeline_service.next_deadline_summary(
+            user.id, datetime.now(timezone.utc).date()),
     }
