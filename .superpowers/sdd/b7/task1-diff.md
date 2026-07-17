# Task 1 diff package (BASE e7e2c51 .. HEAD c0bfab5)

## git log
c0bfab5 Add firms + firm_deadlines reference table (migration 026) and read repo

## diff --stat
 db/migrations/026_firms_and_deadlines.sql | 68 +++++++++++++++++++++++++++++++
 tests/test_b7_firms.py                    | 63 ++++++++++++++++++++++++++++
 webapp/repositories/firms.py              | 40 ++++++++++++++++++
 3 files changed, 171 insertions(+)

## full diff
diff --git a/db/migrations/026_firms_and_deadlines.sql b/db/migrations/026_firms_and_deadlines.sql
new file mode 100644
index 0000000..b267191
--- /dev/null
+++ b/db/migrations/026_firms_and_deadlines.sql
@@ -0,0 +1,68 @@
+-- ============================================================================
+-- 026 — firm reference table + curated interview deadlines (roadmap §B7)
+-- ----------------------------------------------------------------------------
+-- Apply with:  psql -d <db> -v ON_ERROR_STOP=1 -f db/migrations/026_firms_and_deadlines.sql
+-- Idempotent:  CREATE TABLE / INDEX IF NOT EXISTS; seed via ON CONFLICT DO NOTHING.
+--
+-- firm_deadlines dates are a CURATED 2026–27 US full-time stand-in (is_estimate
+-- = TRUE): no authoritative source was consulted. Thomas replaces these with
+-- real cycle dates before launch (see the B7 report).
+-- ============================================================================
+
+CREATE TABLE IF NOT EXISTS firms (
+    id    SERIAL PRIMARY KEY,
+    name  TEXT NOT NULL,
+    slug  TEXT NOT NULL UNIQUE
+);
+
+CREATE TABLE IF NOT EXISTS firm_deadlines (
+    id            SERIAL PRIMARY KEY,
+    firm_id       INTEGER NOT NULL REFERENCES firms(id) ON DELETE CASCADE,
+    cycle_label   TEXT NOT NULL,
+    deadline_date DATE NOT NULL,
+    region        TEXT,
+    is_estimate   BOOLEAN NOT NULL DEFAULT TRUE,
+    CONSTRAINT firm_deadlines_unique UNIQUE (firm_id, cycle_label, region)
+);
+
+CREATE INDEX IF NOT EXISTS idx_firm_deadlines_firm
+    ON firm_deadlines (firm_id, deadline_date);
+
+-- ~12 curated firms: MBB + Big-4 strategy arms + common T2.
+INSERT INTO firms (name, slug) VALUES
+    ('McKinsey & Company',       'mckinsey'),
+    ('Boston Consulting Group',  'bcg'),
+    ('Bain & Company',           'bain'),
+    ('Deloitte',                 'deloitte'),
+    ('PwC Strategy&',            'strategyand'),
+    ('EY-Parthenon',             'ey-parthenon'),
+    ('KPMG',                     'kpmg'),
+    ('Kearney',                  'kearney'),
+    ('Oliver Wyman',             'oliver-wyman'),
+    ('L.E.K. Consulting',        'lek'),
+    ('Roland Berger',            'roland-berger'),
+    ('Accenture Strategy',       'accenture-strategy')
+ON CONFLICT (slug) DO NOTHING;
+
+-- Curated 2026–27 US full-time dates (is_estimate = TRUE). McKinsey/BCG/Bain
+-- match the design persona anchors (Sep 12 / Sep 30 / Oct 08); Roland Berger's
+-- Jul 02 is intentionally a PASSED deadline (design persona) so the post-
+-- deadline prompt has a fixture.
+INSERT INTO firm_deadlines (firm_id, cycle_label, deadline_date, region, is_estimate)
+SELECT f.id, v.cycle_label, v.deadline_date::date, 'US', TRUE
+FROM (VALUES
+    ('mckinsey',           '2026 Full-time', '2026-09-12'),
+    ('bcg',                '2026 Full-time', '2026-09-30'),
+    ('bain',               '2026 Full-time', '2026-10-08'),
+    ('deloitte',           '2026 Full-time', '2026-10-15'),
+    ('strategyand',        '2026 Full-time', '2026-10-20'),
+    ('ey-parthenon',       '2026 Full-time', '2026-10-22'),
+    ('kpmg',               '2026 Full-time', '2026-10-25'),
+    ('kearney',            '2026 Full-time', '2026-09-25'),
+    ('oliver-wyman',       '2026 Full-time', '2026-09-18'),
+    ('lek',                '2026 Full-time', '2026-10-05'),
+    ('roland-berger',      '2026 Full-time', '2026-07-02'),
+    ('accenture-strategy', '2026 Full-time', '2026-10-30')
+) AS v(slug, cycle_label, deadline_date)
+JOIN firms f ON f.slug = v.slug
+ON CONFLICT ON CONSTRAINT firm_deadlines_unique DO NOTHING;
diff --git a/tests/test_b7_firms.py b/tests/test_b7_firms.py
new file mode 100644
index 0000000..cd45197
--- /dev/null
+++ b/tests/test_b7_firms.py
@@ -0,0 +1,63 @@
+"""B7 Task 1: firms reference table + read repo. Needs seeded dev Postgres."""
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
+class TestFirmsRepo(unittest.TestCase):
+    @classmethod
+    def setUpClass(cls):
+        # Enter the app lifespan so the shared connection pool is initialized
+        # (repo functions go through webapp.db.get_pool()). Matches the harness
+        # note in the B7 plan's File Structure section.
+        from fastapi.testclient import TestClient
+        from webapp.main import app
+
+        cls._ctx = TestClient(app)
+        cls._ctx.__enter__()
+
+    @classmethod
+    def tearDownClass(cls):
+        cls._ctx.__exit__(None, None, None)
+
+    def test_list_firms_has_mbb(self):
+        from webapp.repositories import firms as firms_repo
+        firms = firms_repo.list_firms()
+        slugs = {f["slug"] for f in firms}
+        self.assertGreaterEqual(len(firms), 12)
+        self.assertTrue({"mckinsey", "bcg", "bain"}.issubset(slugs))
+        for f in firms:
+            self.assertEqual(set(f), {"id", "name", "slug"})
+
+    def test_get_firm_by_id_and_missing(self):
+        from webapp.repositories import firms as firms_repo
+        first = firms_repo.list_firms()[0]
+        got = firms_repo.get_firm(first["id"])
+        self.assertEqual(got["slug"], first["slug"])
+        self.assertIsNone(firms_repo.get_firm(-1))
+
+    def test_all_deadlines_are_dates_flagged_estimate(self):
+        from webapp.repositories import firms as firms_repo
+        deadlines = firms_repo.all_deadlines()
+        self.assertGreaterEqual(len(deadlines), 12)
+        for d in deadlines:
+            self.assertIsInstance(d["deadline_date"], datetime.date)
+            self.assertTrue(d["is_estimate"])
+            self.assertEqual(d["region"], "US")
+
+    def test_roland_berger_deadline_is_in_the_past_fixture(self):
+        # The persona's passed deadline — powers the post-deadline prompt tests.
+        from webapp.repositories import firms as firms_repo
+        rb = next(f for f in firms_repo.list_firms() if f["slug"] == "roland-berger")
+        rb_dl = [d for d in firms_repo.all_deadlines() if d["firm_id"] == rb["id"]]
+        self.assertEqual(rb_dl[0]["deadline_date"], datetime.date(2026, 7, 2))
+
+
+if __name__ == "__main__":
+    unittest.main()
diff --git a/webapp/repositories/firms.py b/webapp/repositories/firms.py
new file mode 100644
index 0000000..52ba9bd
--- /dev/null
+++ b/webapp/repositories/firms.py
@@ -0,0 +1,40 @@
+"""
+Purpose: Read-only access to the firm reference table + curated interview
+  deadlines (migration 026) for the B7 timeline.
+Inputs:  firm_id; the firms / firm_deadlines tables via the shared pool.
+Outputs: plain dict rows (no side effects).
+Run:     from webapp.repositories import firms; firms.list_firms()
+"""
+
+from __future__ import annotations
+
+from psycopg.rows import dict_row
+
+from webapp.db import get_pool
+
+
+def list_firms() -> list[dict]:
+    """All firms, alphabetical — the add-a-firm catalog source."""
+    with get_pool().connection() as conn:
+        with conn.cursor(row_factory=dict_row) as cur:
+            cur.execute("SELECT id, name, slug FROM firms ORDER BY name;")
+            return cur.fetchall()
+
+
+def get_firm(firm_id: int) -> dict | None:
+    with get_pool().connection() as conn:
+        with conn.cursor(row_factory=dict_row) as cur:
+            cur.execute("SELECT id, name, slug FROM firms WHERE id = %(id)s;",
+                        {"id": firm_id})
+            return cur.fetchone()
+
+
+def all_deadlines() -> list[dict]:
+    """Every firm deadline; the timeline service groups these by firm_id and
+    picks the relevant one (soonest upcoming, else latest passed) in Python."""
+    with get_pool().connection() as conn:
+        with conn.cursor(row_factory=dict_row) as cur:
+            cur.execute(
+                "SELECT firm_id, cycle_label, deadline_date, region, is_estimate"
+                " FROM firm_deadlines ORDER BY firm_id, deadline_date;")
+            return cur.fetchall()
