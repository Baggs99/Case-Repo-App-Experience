-- Dairy Farm split PDF was trimmed to 4 pages; catalog/manifest already reflect this.
-- Sync Postgres so the web UI and generate-previews use the correct page_count.
--
-- Alternatively (full catalog sync):  python main.py publish-cases

UPDATE cases
SET page_count = 4
WHERE source_school = 'MIT'
  AND source_year = 2011
  AND normalized_title = 'dairy farm bain round 1';
