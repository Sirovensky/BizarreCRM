-- Add show_in_canned flag to notification templates for canned response feature
ALTER TABLE notification_templates ADD COLUMN show_in_canned INTEGER NOT NULL DEFAULT 0;
