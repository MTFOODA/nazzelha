CREATE TABLE IF NOT EXISTS statistics (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  visits INTEGER NOT NULL DEFAULT 0,
  started_at INTEGER NOT NULL
);
INSERT OR IGNORE INTO statistics (id, started_at) VALUES (1, unixepoch());
CREATE TABLE IF NOT EXISTS visit_sessions (id TEXT PRIMARY KEY, created_at INTEGER NOT NULL);
CREATE INDEX IF NOT EXISTS visit_sessions_created ON visit_sessions(created_at);
CREATE TRIGGER IF NOT EXISTS count_visit AFTER INSERT ON visit_sessions
BEGIN
  UPDATE statistics SET visits = visits + 1 WHERE id = 1;
END;
CREATE TABLE IF NOT EXISTS download_cache (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  windows INTEGER NOT NULL,
  android INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
