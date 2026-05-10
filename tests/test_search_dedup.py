"""
Tests for public-search duplicate hiding.

The dedup rule is implemented twice — once in SQL (SEARCH_SQL_DEDUP /
COUNT_SQL_DEDUP, exercised against Postgres) and once in pure Python
(``pick_canonical_case_ids``, exercised here). These tests pin the
algorithm's behaviour so any future SQL change must keep matching it.
"""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))

from webapp.repositories.cases import (
    SEARCH_SQL_DEDUP,
    SearchFilters,
    pick_canonical_case_ids,
)


def _row(id, title, school, year, normalized_title):
    return {
        "id": id,
        "case_title": title,
        "source_school": school,
        "source_year": year,
        "normalized_title": normalized_title,
    }


# ── pick_canonical_case_ids ────────────────────────────────────────────────────

class TestPickCanonicalCaseIds:
    def test_zoo_co_keeps_oldest_kellogg_2016(self):
        rows = [
            _row(101, "Zoo Co", "Kellogg", 2024, "zoo co"),
            _row(102, "Zoo Co", "Kellogg", 2023, "zoo co"),
            _row(103, "Zoo Co", "Kellogg", 2016, "zoo co"),
        ]
        assert pick_canonical_case_ids(rows) == {103}

    def test_lola_los_zoo_keeps_booth_2021(self):
        rows = [
            _row(201, "Lola Lo's Zoo", "Booth", 2026, "lola lo s zoo"),
            _row(202, "Lola Lo's Zoo", "Booth", 2021, "lola lo s zoo"),
        ]
        assert pick_canonical_case_ids(rows) == {202}

    def test_unrelated_titles_all_kept(self):
        rows = [
            _row(1, "Acme",  "Yale",    2019, "acme"),
            _row(2, "Beta",  "Booth",   2020, "beta"),
            _row(3, "Gamma", "Kellogg", 2018, "gamma"),
        ]
        assert pick_canonical_case_ids(rows) == {1, 2, 3}

    def test_tiebreak_same_year_lower_id_wins(self):
        rows = [
            _row(50, "Same Same", "Yale",  2020, "same"),
            _row(40, "Same Same", "Booth", 2020, "same"),
            _row(60, "Same Same", "Booth", 2020, "same"),
        ]
        assert pick_canonical_case_ids(rows) == {40}

    def test_null_year_ranks_after_dated_year(self):
        # A RocketBlocks-style entry (no source_year) should never displace
        # a dated school original of the same case.
        rows = [
            _row(10, "Foo Co", "RocketBlocks", None, "foo co"),
            _row(11, "Foo Co", "Yale",         2017, "foo co"),
        ]
        assert pick_canonical_case_ids(rows) == {11}

    def test_all_null_year_falls_back_to_lowest_id(self):
        rows = [
            _row(20, "Foo Co", "RocketBlocks", None, "foo co"),
            _row(15, "Foo Co", "RocketBlocks", None, "foo co"),
        ]
        assert pick_canonical_case_ids(rows) == {15}

    def test_empty_normalized_title_rows_are_each_their_own_group(self):
        # Two rows without a normalized_title must NOT collapse into one — we
        # only deduplicate on exact-match titles, per the requirement.
        rows = [
            _row(1, "Untitled A", "Yale",  2019, ""),
            _row(2, "Untitled B", "Booth", 2020, None),
            _row(3, "Real Case",  "Kellogg", 2018, "real case"),
        ]
        assert pick_canonical_case_ids(rows) == {1, 2, 3}

    def test_operator_flag_excludes_from_title_grouping(self):
        # Rows already marked duplicate never participate in the
        # normalized_title canonical race (mirrors SQL pre-filter).
        rows = [
            {**_row(101, "Zoo Co", "Kellogg", 2024, "zoo co"), "is_duplicate_case": True},
            _row(102, "Zoo Co", "Kellogg", 2023, "zoo co"),
            _row(103, "Zoo Co", "Kellogg", 2016, "zoo co"),
        ]
        assert pick_canonical_case_ids(rows) == {103}

    def test_duplicate_within_same_group_with_different_year_ordering(self):
        # Inputs in arbitrary order should still produce the same canonical.
        rows_a = [
            _row(7, "X", "Y", 2020, "x"),
            _row(8, "X", "Y", 2018, "x"),
            _row(9, "X", "Y", 2024, "x"),
        ]
        rows_b = list(reversed(rows_a))
        assert pick_canonical_case_ids(rows_a) == {8}
        assert pick_canonical_case_ids(rows_b) == {8}


# ── SearchFilters URL round-trip with include_duplicates ───────────────────────

class TestSearchFiltersIncludeDuplicates:
    def test_default_false(self):
        f = SearchFilters.from_query()
        assert f.include_duplicates is False

    def test_truthy_string_parses_true(self):
        for v in ("1", "true", "True", "yes", "on", "y"):
            assert SearchFilters.from_query(include_duplicates=v).include_duplicates is True, v

    def test_falsy_string_parses_false(self):
        for v in ("0", "false", "no", "", None):
            assert SearchFilters.from_query(include_duplicates=v).include_duplicates is False, v

    def test_query_string_omits_when_false(self):
        f = SearchFilters.from_query(q="zoo")
        qs = f.to_query_string()
        assert "include_duplicates" not in qs

    def test_query_string_appends_when_true(self):
        f = SearchFilters.from_query(q="zoo", include_duplicates="1")
        qs = f.to_query_string()
        assert "include_duplicates=1" in qs

    def test_search_url_round_trip(self):
        f = SearchFilters.from_query(
            q="zoo", difficulty="Hard", include_duplicates="1",
        )
        url = f.to_search_url()
        assert url.startswith("/search?")
        assert "q=zoo" in url
        assert "difficulty=Hard" in url
        assert "include_duplicates=1" in url


# ── Sanity-check the SQL string the DB ultimately runs ─────────────────────────

class TestDedupSqlShape:
    """We can't run Postgres in CI here, but we can verify the SQL string
    stays in sync with the algorithm tested above."""

    def test_partition_uses_normalized_title_with_id_fallback(self):
        # PARTITION key matches the Python helper's grouping rule: rows with
        # an empty normalized_title each form their own singleton group.
        assert "PARTITION BY COALESCE(NULLIF(cs.normalized_title, ''), '__id_' || cs.id::text)" in SEARCH_SQL_DEDUP

    def test_order_picks_oldest_year_then_lowest_id(self):
        assert "ORDER BY" in SEARCH_SQL_DEDUP
        assert "cs.source_year ASC NULLS LAST" in SEARCH_SQL_DEDUP
        assert "unique_case_count_eligible" in SEARCH_SQL_DEDUP
        assert "cs.id ASC" in SEARCH_SQL_DEDUP

    def test_excludes_operator_marked_duplicates_before_ranking(self):
        assert "WHERE NOT COALESCE(cs.is_duplicate_case, false)" in SEARCH_SQL_DEDUP

    def test_dedup_filters_to_rn_one(self):
        assert "rn = 1" in SEARCH_SQL_DEDUP

    def test_dedup_sql_still_orders_by_difficulty_then_title(self):
        # The outer ORDER BY (used to drive list rendering) must be preserved.
        assert "ORDER BY difficulty_score NULLS LAST, case_title" in SEARCH_SQL_DEDUP

    def test_industry_filter_uses_canonical_array_params(self):
        assert "industry_active" in SEARCH_SQL_DEDUP
        assert "industry_raws" in SEARCH_SQL_DEDUP
        assert "CASE WHEN NOT %(industry_active)s" in SEARCH_SQL_DEDUP
