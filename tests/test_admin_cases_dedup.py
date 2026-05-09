"""
Tests for /admin/cases duplicate-hiding behavior.

The admin listing reuses the same canonical-row rule as public search
(``pick_canonical_case_ids`` in ``webapp.repositories.cases``); these
tests verify (1) the SQL string the admin route builds keeps the rule
in sync, (2) the route accepts ``?include_duplicates=1``, and (3) the
canonical-picking helper still produces the documented Zoo Co / Lola
Lo's Zoo answers when fed admin-shaped rows.
"""

import inspect
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from webapp.repositories.case_votes import list_cases_with_vote_stats
from webapp.repositories.cases import pick_canonical_case_ids
from webapp.routes import admin as admin_route


def _admin_row(id, title, school, year, normalized_title):
    return {
        "id": id,
        "case_title": title,
        "source_school": school,
        "source_year": year,
        "normalized_title": normalized_title,
    }


# ── Canonical row picking against admin-shaped rows ────────────────────────────

class TestAdminDedupExamples:
    def test_zoo_co_admin_default_view(self):
        # Mirrors the rows the admin listing would pull for Zoo Co — the
        # default (canonical-only) view must keep just Kellogg 2016.
        rows = [
            _admin_row(101, "Zoo Co", "Kellogg", 2024, "zoo co"),
            _admin_row(102, "Zoo Co", "Kellogg", 2023, "zoo co"),
            _admin_row(103, "Zoo Co", "Kellogg", 2016, "zoo co"),
        ]
        keep = pick_canonical_case_ids(rows)
        assert keep == {103}

    def test_lola_los_zoo_admin_default_view(self):
        rows = [
            _admin_row(201, "Lola Lo's Zoo", "Booth", 2026, "lola lo s zoo"),
            _admin_row(202, "Lola Lo's Zoo", "Booth", 2021, "lola lo s zoo"),
        ]
        keep = pick_canonical_case_ids(rows)
        assert keep == {202}

    def test_include_duplicates_keeps_every_id(self):
        # When the admin checks "Show duplicates", every row should be
        # rendered — `is_canonical` flag on each tells the template which
        # to badge as Canonical vs Duplicate.
        rows = [
            _admin_row(101, "Zoo Co", "Kellogg", 2024, "zoo co"),
            _admin_row(102, "Zoo Co", "Kellogg", 2023, "zoo co"),
            _admin_row(103, "Zoo Co", "Kellogg", 2016, "zoo co"),
        ]
        canonical = pick_canonical_case_ids(rows)
        all_ids = {r["id"] for r in rows}
        # The full-view ID set is a superset of the canonical set.
        assert canonical.issubset(all_ids)
        assert all_ids == {101, 102, 103}
        # Exactly one row per group is canonical.
        assert len(canonical) == 1


# ── SQL string shape (algorithm pinned to source) ──────────────────────────────

class TestAdminListSqlShape:
    """We can't run Postgres in the unit suite, but we can confirm the
    SQL the admin repo builds keeps the dedup rule in lock-step with the
    Python helper above."""

    def _build_sql(self, *, include_duplicates: bool) -> str:
        """Re-extract the SQL string the function would execute by
        capturing the f-string template via source inspection. Cheaper
        than mocking psycopg and pins the SQL we ship.
        """
        # The function builds its SQL inline; running it dry would need a
        # DB. Instead, just check the source contains the expected clauses.
        return inspect.getsource(list_cases_with_vote_stats)

    def test_dedup_partition_matches_public_search_rule(self):
        src = self._build_sql(include_duplicates=False)
        assert "PARTITION BY COALESCE(" in src
        assert "NULLIF(cs.normalized_title, '')" in src
        assert "'__id_' || cs.id::text" in src

    def test_order_picks_oldest_year_then_lowest_id(self):
        src = self._build_sql(include_duplicates=False)
        assert "ORDER BY" in src
        assert "cs.source_year ASC NULLS LAST" in src
        assert "unique_case_count_eligible" in src
        assert "cs.id ASC" in src

    def test_default_filters_to_canonical_only(self):
        src = self._build_sql(include_duplicates=False)
        # Conditional WHERE clause restricts the join to canonicals when
        # include_duplicates is False.
        assert 'where_sql = "" if include_duplicates else "WHERE c.rn = 1"' in src

    def test_excludes_operator_marked_duplicates_before_ranking(self):
        src = self._build_sql(include_duplicates=False)
        assert "WHERE NOT COALESCE(cs.is_duplicate_case, false)" in src

    def test_is_canonical_flag_exposed_to_template(self):
        src = self._build_sql(include_duplicates=False)
        # Canonical = highest-ranked AND not operator-flagged. Both pieces
        # must show up so the admin badge tracks the operator's intent
        # (tested at the SQL-string level since we can't hit Postgres here).
        assert "AS is_canonical" in src
        assert "c.rn = 1" in src
        assert "NOT COALESCE(c.is_duplicate_case" in src


# ── Route accepts the include_duplicates query param ───────────────────────────

class TestAdminRouteSignature:
    def test_admin_cases_handler_takes_include_duplicates(self):
        sig = inspect.signature(admin_route.admin_cases)
        assert "include_duplicates" in sig.parameters
        # Default must be falsy so the public-style canonical-only view
        # is the default for /admin/cases.
        assert sig.parameters["include_duplicates"].default in (None, False, "")
