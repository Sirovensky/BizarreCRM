-- PROD12: Track whether a user has explicitly set their PIN, mirroring
-- password_set. Default PIN '1234' is stamped on admin/new users for
-- switch-user convenience. Without a pin_set flag there's no way to
-- force a first-use change — anyone with physical proximity to a
-- logged-in tablet could switch user and hit admin with the default.
--
-- All existing rows default to pin_set = 0 so the next PIN touch via
-- /auth/change-pin will flip it to 1 (see change-pin handler in
-- auth.routes.ts).

ALTER TABLE users ADD COLUMN pin_set INTEGER NOT NULL DEFAULT 0;
