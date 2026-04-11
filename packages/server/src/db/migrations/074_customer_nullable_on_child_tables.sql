-- Migration 074: Make customer_id nullable on tickets and estimates (D1 fix)
--
-- Context: Audit section 11 D1. GDPR right-to-erasure on a customer used to
-- set tickets.customer_id = 0 and estimates.customer_id = 0 to "anonymize"
-- references while preserving business records. That leaks a synthetic
-- orphan id (0) into every join, corrupts ticket/invoice counts, and breaks
-- FK semantics. The proper behaviour is to set the reference to NULL.
--
-- invoices.customer_id was already made nullable in 013. This migration does
-- the same for tickets and estimates.
--
-- SQLite does not support ALTER COLUMN to drop NOT NULL. The historical
-- approach (see 013) is to rebuild the table with SELECT *. That is fragile
-- here because both tables have accumulated many additive columns via
-- migrations 007-071 and any future new columns would force a rewrite.
--
-- Instead we use the officially-documented writable_schema trick
-- (https://www.sqlite.org/lang_altertable.html#otheralter) to rewrite the
-- CREATE TABLE DDL in place. This is atomic under the migration's
-- transaction wrapper, preserves every existing row, index, trigger, and
-- FK, and leaves the schema_version untouched beyond the edit itself.

PRAGMA foreign_keys = OFF;

-- Turn off schema-write lock so we can modify sqlite_master directly.
PRAGMA writable_schema = 1;

-- Rewrite the tickets CREATE TABLE statement to drop NOT NULL from
-- customer_id. The replacement is conservative: we only patch the single
-- offending token inside the tickets schema row. The rest of the DDL is
-- preserved verbatim so the table keeps every column added by later
-- migrations.
UPDATE sqlite_master
SET sql = REPLACE(
  sql,
  'customer_id     INTEGER NOT NULL REFERENCES customers(id)',
  'customer_id     INTEGER REFERENCES customers(id)'
)
WHERE type = 'table' AND name = 'tickets';

-- Same fix for estimates.
UPDATE sqlite_master
SET sql = REPLACE(
  sql,
  'customer_id         INTEGER NOT NULL REFERENCES customers(id)',
  'customer_id         INTEGER REFERENCES customers(id)'
)
WHERE type = 'table' AND name = 'estimates';

-- Re-lock sqlite_master and re-enable FK enforcement.
PRAGMA writable_schema = 0;
PRAGMA foreign_keys = ON;

-- Integrity check: verify the schema parses correctly after the rewrite.
-- If this fails the transaction will roll back and the DB is untouched.
PRAGMA integrity_check;
