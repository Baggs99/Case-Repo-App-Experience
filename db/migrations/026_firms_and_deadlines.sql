-- ============================================================================
-- 026 — firm reference table + curated interview deadlines (roadmap §B7)
-- ----------------------------------------------------------------------------
-- Apply with:  psql -d <db> -v ON_ERROR_STOP=1 -f db/migrations/026_firms_and_deadlines.sql
-- Idempotent:  CREATE TABLE / INDEX IF NOT EXISTS; seed via ON CONFLICT DO NOTHING.
--
-- firm_deadlines dates are a CURATED 2026–27 US full-time stand-in (is_estimate
-- = TRUE): no authoritative source was consulted. Thomas replaces these with
-- real cycle dates before launch (see the B7 report).
-- ============================================================================

CREATE TABLE IF NOT EXISTS firms (
    id    SERIAL PRIMARY KEY,
    name  TEXT NOT NULL,
    slug  TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS firm_deadlines (
    id            SERIAL PRIMARY KEY,
    firm_id       INTEGER NOT NULL REFERENCES firms(id) ON DELETE CASCADE,
    cycle_label   TEXT NOT NULL,
    deadline_date DATE NOT NULL,
    region        TEXT,
    is_estimate   BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT firm_deadlines_unique UNIQUE (firm_id, cycle_label, region)
);

CREATE INDEX IF NOT EXISTS idx_firm_deadlines_firm
    ON firm_deadlines (firm_id, deadline_date);

-- ~12 curated firms: MBB + Big-4 strategy arms + common T2.
INSERT INTO firms (name, slug) VALUES
    ('McKinsey & Company',       'mckinsey'),
    ('Boston Consulting Group',  'bcg'),
    ('Bain & Company',           'bain'),
    ('Deloitte',                 'deloitte'),
    ('PwC Strategy&',            'strategyand'),
    ('EY-Parthenon',             'ey-parthenon'),
    ('KPMG',                     'kpmg'),
    ('Kearney',                  'kearney'),
    ('Oliver Wyman',             'oliver-wyman'),
    ('L.E.K. Consulting',        'lek'),
    ('Roland Berger',            'roland-berger'),
    ('Accenture Strategy',       'accenture-strategy')
ON CONFLICT (slug) DO NOTHING;

-- Curated 2026–27 US full-time dates (is_estimate = TRUE). McKinsey/BCG/Bain
-- match the design persona anchors (Sep 12 / Sep 30 / Oct 08); Roland Berger's
-- Jul 02 is intentionally a PASSED deadline (design persona) so the post-
-- deadline prompt has a fixture.
INSERT INTO firm_deadlines (firm_id, cycle_label, deadline_date, region, is_estimate)
SELECT f.id, v.cycle_label, v.deadline_date::date, 'US', TRUE
FROM (VALUES
    ('mckinsey',           '2026 Full-time', '2026-09-12'),
    ('bcg',                '2026 Full-time', '2026-09-30'),
    ('bain',               '2026 Full-time', '2026-10-08'),
    ('deloitte',           '2026 Full-time', '2026-10-15'),
    ('strategyand',        '2026 Full-time', '2026-10-20'),
    ('ey-parthenon',       '2026 Full-time', '2026-10-22'),
    ('kpmg',               '2026 Full-time', '2026-10-25'),
    ('kearney',            '2026 Full-time', '2026-09-25'),
    ('oliver-wyman',       '2026 Full-time', '2026-09-18'),
    ('lek',                '2026 Full-time', '2026-10-05'),
    ('roland-berger',      '2026 Full-time', '2026-07-02'),
    ('accenture-strategy', '2026 Full-time', '2026-10-30')
) AS v(slug, cycle_label, deadline_date)
JOIN firms f ON f.slug = v.slug
ON CONFLICT ON CONSTRAINT firm_deadlines_unique DO NOTHING;
