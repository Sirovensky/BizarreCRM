-- ENR-DB3: Per-user timezone preference
-- NULL means "use server default / browser timezone".
ALTER TABLE users ADD COLUMN timezone TEXT DEFAULT NULL;
