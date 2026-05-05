-- ============================================================================
-- 005: Add provider_message_id to sms_messages for tracking provider-assigned IDs
-- ============================================================================
ALTER TABLE sms_messages ADD COLUMN provider_message_id TEXT;
