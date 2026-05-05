-- ENR-SMS1: Add send_at for scheduled/delayed messages
ALTER TABLE sms_messages ADD COLUMN send_at TEXT DEFAULT NULL;

-- Index for the cron job to find due scheduled messages quickly
CREATE INDEX IF NOT EXISTS idx_sms_messages_scheduled
  ON sms_messages(status, send_at)
  WHERE status = 'scheduled';

-- ENR-SMS7: Add is_archived flag to conversation flags
ALTER TABLE sms_conversation_flags ADD COLUMN is_archived INTEGER NOT NULL DEFAULT 0;
