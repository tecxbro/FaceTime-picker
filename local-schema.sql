CREATE TABLE IF NOT EXISTS trusted_callers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  phone_number TEXT NOT NULL UNIQUE,
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1))
);

-- Example only. Do not commit real numbers.
-- INSERT INTO trusted_callers (phone_number, enabled) VALUES ('+1 202 555 0147', 1);
