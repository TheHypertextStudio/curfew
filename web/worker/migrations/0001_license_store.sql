-- Additive issuer-only schema. Never marks an existing KV migration ready.
CREATE TABLE IF NOT EXISTS curfew_license_meta (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  revision INTEGER NOT NULL DEFAULT 0,
  ready INTEGER NOT NULL DEFAULT 0 CHECK (ready IN (0, 1))
);

INSERT OR IGNORE INTO
  curfew_license_meta (id, revision, ready)
VALUES
  (1, 0, 0);

CREATE TABLE IF NOT EXISTS curfew_license_record (
  "key" TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  expires_at INTEGER
);

CREATE TABLE IF NOT EXISTS curfew_license_guard (
  transaction_id TEXT PRIMARY KEY,
  valid INTEGER NOT NULL CHECK (valid = 1)
);

CREATE INDEX IF NOT EXISTS curfew_license_expiry ON curfew_license_record (expires_at)
WHERE
  expires_at IS NOT NULL;
