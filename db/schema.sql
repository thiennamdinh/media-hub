PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS records (
  id INTEGER PRIMARY KEY,
  source TEXT NOT NULL,
  record_type TEXT NOT NULL,
  canonical_url TEXT,
  observed_at TEXT NOT NULL,
  title TEXT,
  raw_json TEXT NOT NULL,
  inserted_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_records_source ON records(source);
CREATE INDEX IF NOT EXISTS idx_records_type ON records(record_type);
CREATE INDEX IF NOT EXISTS idx_records_url ON records(canonical_url);
CREATE INDEX IF NOT EXISTS idx_records_observed_at ON records(observed_at);

-- Helps ingest skip duplicate non-snapshot records across repeated ticks.
-- Probability signals remain append-only snapshots so market movement can be
-- computed over time.
CREATE INDEX IF NOT EXISTS idx_records_external_id
ON records(json_extract(raw_json, '$.external_id'));

CREATE VIEW IF NOT EXISTS url_mentions AS
SELECT
  id AS record_id,
  canonical_url,
  source,
  json_extract(raw_json, '$.source_type') AS source_type,
  record_type,
  observed_at,
  title,
  raw_json
FROM records
WHERE canonical_url IS NOT NULL;

CREATE VIEW IF NOT EXISTS stories AS
SELECT
  canonical_url,
  COUNT(*) AS mentions,
  COUNT(DISTINCT source) AS sources,
  GROUP_CONCAT(DISTINCT source) AS by_sources,
  MIN(observed_at) AS first_seen,
  MAX(observed_at) AS last_seen,
  COALESCE(MAX(title), canonical_url) AS title
FROM records
WHERE canonical_url IS NOT NULL
GROUP BY canonical_url;

CREATE TABLE IF NOT EXISTS ingest_runs (
  id INTEGER PRIMARY KEY,
  source TEXT NOT NULL,
  started_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  finished_at TEXT,
  records_inserted INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'running',
  message TEXT
);
