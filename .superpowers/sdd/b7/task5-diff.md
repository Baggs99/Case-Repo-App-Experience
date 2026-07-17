# Task 5 diff package (BASE bbbe7c6 .. HEAD)

## git log
9bd3e37 Add timeline router + assembly service (track, detail, post-deadline flow)

## diff --stat
 tests/test_b7_timeline_api.py | 156 ++++++++++++++++++++++++++++++++++++++++++
 webapp/main.py                |   2 +
 webapp/routes/timeline.py     |  96 ++++++++++++++++++++++++++
 webapp/timeline_service.py    | 113 ++++++++++++++++++++++++++++++
 4 files changed, 367 insertions(+)

## full diff
diff --git a/tests/test_b7_timeline_api.py b/tests/test_b7_timeline_api.py
new file mode 100644
index 0000000..b81f69a
--- /dev/null
+++ b/tests/test_b7_timeline_api.py
@@ -0,0 +1,156 @@
+"""B7 Task 5: timeline router — track/untrack, timeline-detail payload, the
+post-deadline result flow, auth + IDOR. Needs seeded dev Postgres + httpx."""
+
+from __future__ import annotations
+
+import unittest
+
+from tests.test_ws_integration import _DB_URL, _HTTPX, _READY
+
+
+@unittest.skipUnless(_READY, "requires seeded dev Postgres (scripts/seed_caseroom_dev.py)")
+@unittest.skipUnless(_HTTPX, "requires httpx for TestClient")
+class TestTimelineApi(unittest.TestCase):
+    @classmethod
+    def setUpClass(cls):
+        from fastapi.testclient import TestClient
+        from webapp.main import app
+        from webapp.auth.sessions import SESSION_COOKIE_NAME, create_session
+        from webapp.repositories import firms as firms_repo
+
+        cls._ctx = TestClient(app)
+        cls.alice = cls._ctx.__enter__()
+        cls.bob = TestClient(app)
+        import psycopg
+        with psycopg.connect(_DB_URL) as conn:
+            with conn.cursor() as cur:
+                cur.execute("SELECT email, id FROM users WHERE email = ANY(%s);",
+                            (["a@yale.edu", "b@yale.edu"],))
+                ids = dict(cur.fetchall())
+        cls.aid, cls.bid = ids["a@yale.edu"], ids["b@yale.edu"]
+        for client, uid in ((cls.alice, cls.aid), (cls.bob, cls.bid)):
+            s = create_session(uid, user_agent="b7-test", ip_address=None)
+            client.cookies.set(SESSION_COOKIE_NAME, s.id)
+        cls.mck = next(f for f in firms_repo.list_firms() if f["slug"] == "mckinsey")["id"]
+        cls.rb = next(f for f in firms_repo.list_firms() if f["slug"] == "roland-berger")["id"]
+
+    @classmethod
+    def tearDownClass(cls):
+        import psycopg
+        with psycopg.connect(_DB_URL) as conn:
+            with conn.cursor() as cur:
+                cur.execute("DELETE FROM user_firms WHERE user_id = ANY(%s);",
+                            ([cls.aid, cls.bid],))
+        cls._ctx.__exit__(None, None, None)
+
+    def tearDown(self):
+        import psycopg
+        with psycopg.connect(_DB_URL) as conn:
+            with conn.cursor() as cur:
+                cur.execute("DELETE FROM user_firms WHERE user_id = ANY(%s);",
+                            ([self.aid, self.bid],))
+
+    # ── auth ────────────────────────────────────────────────────────────────
+    def test_timeline_requires_auth(self):
+        from fastapi.testclient import TestClient
+        from webapp.main import app
+        self.assertEqual(TestClient(app).get("/api/v1/timeline").status_code, 401)
+
+    def test_track_requires_auth(self):
+        from fastapi.testclient import TestClient
+        from webapp.main import app
+        r = TestClient(app).post("/api/v1/timeline/firms", json={"firm_id": self.mck})
+        self.assertEqual(r.status_code, 401)
+
+    # ── track / list / untrack ───────────────────────────────────────────────
+    def test_track_untrack_and_catalog(self):
+        r = self.alice.post("/api/v1/timeline/firms", json={"firm_id": self.mck})
+        self.assertEqual(r.status_code, 200, r.text)
+        self.assertEqual(r.json()["status"], "tracking")
+
+        cat = self.alice.get("/api/v1/timeline/firms").json()["firms"]
+        mck = next(f for f in cat if f["firm_id"] == self.mck)
+        self.assertTrue(mck["tracked"])
+        self.assertIsNotNone(mck["next_deadline"])
+
+        tl = self.alice.get("/api/v1/timeline").json()
+        self.assertEqual(len(tl["firms"]), 1)
+        self.assertIn(tl["firms"][0]["readiness_tag"], {"on_track", "focus", "early"})
+        self.assertEqual(tl["readiness"]["label"], "needs_work")  # Alice: no data
+
+        self.assertEqual(
+            self.alice.delete(f"/api/v1/timeline/firms/{self.mck}").status_code, 204)
+        self.assertEqual(len(self.alice.get("/api/v1/timeline").json()["firms"]), 0)
+
+    def test_track_unknown_firm_404(self):
+        r = self.alice.post("/api/v1/timeline/firms", json={"firm_id": -1})
+        self.assertEqual(r.status_code, 404)
+
+    # ── post-deadline result flow ─────────────────────────────────────────────
+    def test_passed_deadline_prompt_then_offer(self):
+        self.alice.post("/api/v1/timeline/firms", json={"firm_id": self.rb})
+        tl = self.alice.get("/api/v1/timeline").json()
+        rb = next(f for f in tl["firms"] if f["firm_id"] == self.rb)
+        self.assertTrue(rb["deadline"]["passed"])
+        self.assertTrue(rb["prompt"]["show"])
+
+        r = self.alice.post(f"/api/v1/timeline/firms/{self.rb}/result",
+                            json={"outcome": "offer"})
+        self.assertEqual(r.status_code, 200, r.text)
+        self.assertEqual(r.json()["status"], "offer")
+        # Prompt gone once resolved.
+        tl2 = self.alice.get("/api/v1/timeline").json()
+        rb2 = next(f for f in tl2["firms"] if f["firm_id"] == self.rb)
+        self.assertFalse(rb2["prompt"]["show"])
+        self.assertEqual(rb2["status"], "offer")
+
+    def test_no_offer_returns_reweight(self):
+        self.alice.post("/api/v1/timeline/firms", json={"firm_id": self.rb})
+        r = self.alice.post(f"/api/v1/timeline/firms/{self.rb}/result",
+                            json={"outcome": "no_offer"})
+        self.assertEqual(r.status_code, 200, r.text)
+        body = r.json()
+        self.assertEqual(body["status"], "rejected")
+        self.assertEqual(set(body["reweight"]),
+                         {"focus_dimension", "suggested_drill_type", "extra_cases"})
+
+    def test_waiting_snoozes(self):
+        self.alice.post("/api/v1/timeline/firms", json={"firm_id": self.rb})
+        r = self.alice.post(f"/api/v1/timeline/firms/{self.rb}/result",
+                            json={"outcome": "waiting"})
+        self.assertEqual(r.json()["status"], "interviewed")
+        self.assertIsNotNone(r.json()["snooze_until"])
+
+    def test_didnt_interview_drops_off(self):
+        self.alice.post("/api/v1/timeline/firms", json={"firm_id": self.rb})
+        r = self.alice.post(f"/api/v1/timeline/firms/{self.rb}/result",
+                            json={"outcome": "didnt_interview"})
+        self.assertTrue(r.json()["dropped"])
+        self.assertEqual(len(self.alice.get("/api/v1/timeline").json()["firms"]), 0)
+
+    def test_bad_outcome_400(self):
+        self.alice.post("/api/v1/timeline/firms", json={"firm_id": self.rb})
+        r = self.alice.post(f"/api/v1/timeline/firms/{self.rb}/result",
+                            json={"outcome": "nope"})
+        self.assertEqual(r.status_code, 400)
+
+    # ── IDOR: Bob cannot resolve or untrack a firm only Alice tracks ──────────
+    def test_result_on_untracked_firm_404(self):
+        self.alice.post("/api/v1/timeline/firms", json={"firm_id": self.rb})
+        r = self.bob.post(f"/api/v1/timeline/firms/{self.rb}/result",
+                          json={"outcome": "offer"})
+        self.assertEqual(r.status_code, 404)
+        # Alice's row is untouched.
+        tl = self.alice.get("/api/v1/timeline").json()
+        self.assertEqual(tl["firms"][0]["status"], "tracking")
+
+    def test_untrack_is_per_user(self):
+        self.alice.post("/api/v1/timeline/firms", json={"firm_id": self.rb})
+        # Bob deleting the same firm_id only touches his own (absent) row.
+        self.assertEqual(
+            self.bob.delete(f"/api/v1/timeline/firms/{self.rb}").status_code, 204)
+        self.assertEqual(len(self.alice.get("/api/v1/timeline").json()["firms"]), 1)
+
+
+if __name__ == "__main__":
+    unittest.main()
diff --git a/webapp/main.py b/webapp/main.py
index 33fbc9d..c98d9a8 100644
--- a/webapp/main.py
+++ b/webapp/main.py
@@ -56,20 +56,21 @@ from webapp.routes import exhibits as exhibits_routes
 from webapp.routes import pages as pages_routes
 from webapp.routes import practice as practice_routes
 from webapp.routes import practice_exhibits as practice_exhibits_routes
 from webapp.routes import practice_feedback as practice_feedback_routes
 from webapp.routes import practice_recordings as practice_recordings_routes
 from webapp.routes import proposals as proposals_routes
 from webapp.routes import queues as queues_routes
 from webapp.routes import recommendations as recommendations_routes
 from webapp.routes import rooms as rooms_routes
 from webapp.routes import search as search_routes
+from webapp.routes import timeline as timeline_routes
 from webapp.routes import signal_ws as signal_ws_routes
 from webapp.routes import votes as votes_routes
 from webapp.settings import load_settings
 
 
 logger = logging.getLogger(__name__)
 
 
 @asynccontextmanager
 async def lifespan(app: FastAPI):
@@ -138,20 +139,21 @@ def create_app() -> FastAPI:
     app.include_router(rooms_routes.router)
     app.include_router(practice_routes.router)
     app.include_router(practice_exhibits_routes.router)
     app.include_router(practice_feedback_routes.router)
     app.include_router(practice_recordings_routes.router)
     app.include_router(queues_routes.router)
     app.include_router(proposals_routes.router)
     app.include_router(signal_ws_routes.router)
     app.include_router(exhibits_routes.router)
     app.include_router(recommendations_routes.router)
+    app.include_router(timeline_routes.router)
     app.include_router(api_v1_routes.router)
 
     return app
 
 
 def _safe_url(url: str) -> str:
     """Strip the password from a connection URL before logging."""
     try:
         from urllib.parse import urlparse, urlunparse
         u = urlparse(url)
diff --git a/webapp/routes/timeline.py b/webapp/routes/timeline.py
new file mode 100644
index 0000000..6ffdc25
--- /dev/null
+++ b/webapp/routes/timeline.py
@@ -0,0 +1,96 @@
+"""
+Purpose: /api/v1/timeline* — track/untrack firms, the timeline-detail payload,
+  and the post-deadline result flow (Offer / No offer→reweight / Waiting /
+  Didn't interview) for the B7 Home + Timeline-detail screens.
+Inputs:  session cookie (require_auth_api); firm_id path/body; outcome body.
+Outputs: JSON timeline payloads; user_firms writes (track/untrack/result).
+Run:     GET /api/v1/timeline  (Cookie: caseroom_session=…)
+"""
+
+from __future__ import annotations
+
+import datetime
+
+from fastapi import APIRouter, Depends, HTTPException
+from fastapi.responses import Response
+from pydantic import BaseModel
+
+from webapp import timeline_service
+from webapp.auth.dependencies import require_auth_api
+from webapp.auth.users import User
+from webapp.csrf import require_same_origin
+from webapp.readiness import reweight_payload
+from webapp.repositories import firms as firms_repo
+from webapp.repositories import user_firms as user_firms_repo
+
+router = APIRouter(prefix="/api/v1")
+_MUTATING = [Depends(require_same_origin)]
+
+_OUTCOMES = {"offer", "no_offer", "waiting", "didnt_interview"}
+
+
+def _today() -> datetime.date:
+    return datetime.datetime.now(datetime.timezone.utc).date()
+
+
+class TrackFirmBody(BaseModel):
+    firm_id: int
+
+
+class ResultBody(BaseModel):
+    outcome: str
+
+
+@router.get("/timeline")
+def get_timeline(user: User = Depends(require_auth_api)):
+    return timeline_service.timeline_view(user.id, _today())
+
+
+@router.get("/timeline/firms")
+def list_firms_catalog(user: User = Depends(require_auth_api)):
+    return {"firms": timeline_service.firm_catalog(user.id, _today())}
+
+
+@router.post("/timeline/firms", dependencies=_MUTATING)
+def track_firm(body: TrackFirmBody, user: User = Depends(require_auth_api)):
+    firm = firms_repo.get_firm(body.firm_id)
+    if firm is None:
+        raise HTTPException(status_code=404, detail="No such firm")
+    row = user_firms_repo.track(user.id, body.firm_id)
+    return {"firm_id": firm["id"], "name": firm["name"], "slug": firm["slug"],
+            "status": row["status"]}
+
+
+@router.delete("/timeline/firms/{firm_id}", status_code=204, dependencies=_MUTATING)
+def untrack_firm(firm_id: int, user: User = Depends(require_auth_api)):
+    # Idempotent: deleting an untracked firm is a 204 no-op (nothing leaked).
+    user_firms_repo.untrack(user.id, firm_id)
+    return Response(status_code=204)
+
+
+@router.post("/timeline/firms/{firm_id}/result", dependencies=_MUTATING)
+def record_result(firm_id: int, body: ResultBody, user: User = Depends(require_auth_api)):
+    """Post-deadline flow. outcome ∈ _OUTCOMES. A user can only resolve a firm
+    THEY track — an untracked firm_id is 404 (IDOR guard; identity is the
+    session, never a param)."""
+    if body.outcome not in _OUTCOMES:
+        raise HTTPException(status_code=400,
+                            detail=f"outcome must be one of {sorted(_OUTCOMES)}")
+    if not user_firms_repo.is_tracked(user.id, firm_id):
+        raise HTTPException(status_code=404, detail="Not tracking this firm")
+
+    if body.outcome == "offer":
+        row = user_firms_repo.record_result(user.id, firm_id, "offer")
+        return {"outcome": "offer", "status": "offer",
+                "result_recorded_at": row["result_recorded_at"].isoformat()}
+    if body.outcome == "no_offer":
+        user_firms_repo.record_result(user.id, firm_id, "rejected")
+        return {"outcome": "no_offer", "status": "rejected",
+                "reweight": reweight_payload(user.id)}
+    if body.outcome == "waiting":
+        row = user_firms_repo.mark_waiting(user.id, firm_id, days=7)
+        return {"outcome": "waiting", "status": "interviewed",
+                "snooze_until": row["snooze_until"].isoformat()}
+    # didnt_interview → drops off the line (DV-B7-1).
+    user_firms_repo.untrack(user.id, firm_id)
+    return {"outcome": "didnt_interview", "dropped": True}
diff --git a/webapp/timeline_service.py b/webapp/timeline_service.py
new file mode 100644
index 0000000..1c589ed
--- /dev/null
+++ b/webapp/timeline_service.py
@@ -0,0 +1,113 @@
+"""
+Purpose: Assemble tracked firms + curated deadlines + the readiness signal into
+  the B7 timeline payloads (GET /api/v1/timeline, /timeline/firms, and the
+  dashboard timeline summary).
+Inputs:  user_id, as_of (date, passed explicitly for determinism); firms +
+  user_firms repos; readiness swap-point.
+Outputs: plain dicts for the routers. No side effects.
+Run:     from webapp import timeline_service; timeline_service.timeline_view(uid, date.today())
+"""
+
+from __future__ import annotations
+
+import datetime
+
+from webapp import readiness
+from webapp.repositories import firms as firms_repo
+from webapp.repositories import user_firms as user_firms_repo
+
+# Far-out deadlines read as 'early' regardless of readiness (DV-B7-5).
+EARLY_DEADLINE_DAYS = 75
+
+
+def _deadlines_by_firm() -> dict[int, list[dict]]:
+    out: dict[int, list[dict]] = {}
+    for d in firms_repo.all_deadlines():
+        out.setdefault(d["firm_id"], []).append(d)
+    return out
+
+
+def _relevant_deadline(deadlines: list[dict], as_of: datetime.date) -> dict | None:
+    """Soonest upcoming deadline, else the latest passed one (the prompt anchor)."""
+    if not deadlines:
+        return None
+    upcoming = sorted((d for d in deadlines if d["deadline_date"] >= as_of),
+                      key=lambda d: d["deadline_date"])
+    if upcoming:
+        return upcoming[0]
+    return sorted(deadlines, key=lambda d: d["deadline_date"])[-1]
+
+
+def _deadline_block(d: dict | None, as_of: datetime.date) -> dict | None:
+    if d is None:
+        return None
+    days = (d["deadline_date"] - as_of).days
+    return {
+        "cycle_label": d["cycle_label"],
+        "deadline_date": d["deadline_date"].isoformat(),
+        "region": d["region"],
+        "is_estimate": d["is_estimate"],
+        "days_remaining": days,
+        "passed": days < 0,
+    }
+
+
+def _firm_tag(signal: dict, block: dict | None) -> str:
+    """Per-firm display tag over the firm-independent swap-point (DV-B7-5):
+    'early' when the deadline is far out, else on_track/focus from readiness."""
+    if block is not None and not block["passed"] and block["days_remaining"] > EARLY_DEADLINE_DAYS:
+        return "early"
+    return "on_track" if signal["ready"] else "focus"
+
+
+def timeline_view(user_id: int, as_of: datetime.date) -> dict:
+    """The 7b Timeline-detail payload: tracked firms + per-firm deadline +
+    readiness tag + post-deadline prompt state, plus the top-level signal."""
+    signal = readiness.readiness_signal(user_id)
+    by_firm = _deadlines_by_firm()
+    rows = []
+    for uf in user_firms_repo.list_tracked(user_id):
+        block = _deadline_block(_relevant_deadline(by_firm.get(uf["firm_id"], []), as_of), as_of)
+        rows.append({
+            "firm_id": uf["firm_id"],
+            "name": uf["name"],
+            "slug": uf["slug"],
+            "status": uf["status"],
+            "added_at": uf["added_at"].isoformat() if uf["added_at"] else None,
+            "deadline": block,
+            "readiness_tag": _firm_tag(signal, block),
+            # Prompt shows only for a still-tracking firm whose deadline passed.
+            "prompt": {"show": bool(block and block["passed"] and uf["status"] == "tracking")},
+        })
+    return {"as_of": as_of.isoformat(), "readiness": signal, "firms": rows}
+
+
+def firm_catalog(user_id: int, as_of: datetime.date) -> list[dict]:
+    """All firms with a tracked flag + next deadline — the add-a-firm picker."""
+    tracked_ids = {uf["firm_id"] for uf in user_firms_repo.list_tracked(user_id)}
+    by_firm = _deadlines_by_firm()
+    out = []
+    for f in firms_repo.list_firms():
+        block = _deadline_block(_relevant_deadline(by_firm.get(f["id"], []), as_of), as_of)
+        out.append({"firm_id": f["id"], "name": f["name"], "slug": f["slug"],
+                    "tracked": f["id"] in tracked_ids, "next_deadline": block})
+    return out
+
+
+def next_deadline_summary(user_id: int, as_of: datetime.date) -> dict:
+    """Dashboard timeline block: soonest UPCOMING deadline across tracked firms
+    + tracked_count. next_deadline is None when nothing is tracked or all
+    deadlines have passed."""
+    view = timeline_view(user_id, as_of)
+    upcoming = [f for f in view["firms"]
+                if f["deadline"] and not f["deadline"]["passed"]]
+    upcoming.sort(key=lambda f: f["deadline"]["days_remaining"])
+    nxt = None
+    if upcoming:
+        f = upcoming[0]
+        nxt = {"firm_id": f["firm_id"], "name": f["name"], "slug": f["slug"],
+               "cycle_label": f["deadline"]["cycle_label"],
+               "deadline_date": f["deadline"]["deadline_date"],
+               "days_remaining": f["deadline"]["days_remaining"],
+               "readiness_tag": f["readiness_tag"]}
+    return {"tracked_count": len(view["firms"]), "next_deadline": nxt}
