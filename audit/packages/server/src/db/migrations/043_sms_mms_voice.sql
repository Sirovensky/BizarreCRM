-- SMS/MMS + Voice + Call Recording support

-- MMS columns on sms_messages
ALTER TABLE sms_messages ADD COLUMN media_urls TEXT;
ALTER TABLE sms_messages ADD COLUMN media_types TEXT;
ALTER TABLE sms_messages ADD COLUMN media_local_paths TEXT;
ALTER TABLE sms_messages ADD COLUMN message_type TEXT NOT NULL DEFAULT 'sms';

-- Delivery tracking
ALTER TABLE sms_messages ADD COLUMN delivered_at TEXT;

-- Tech mobile number for "send to phone" calling
ALTER TABLE users ADD COLUMN mobile_number TEXT;

-- Call logs with recording + transcription
CREATE TABLE IF NOT EXISTS call_logs (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    direction           TEXT NOT NULL DEFAULT 'outbound',
    from_number         TEXT,
    to_number           TEXT,
    conv_phone          TEXT,
    provider            TEXT,
    provider_call_id    TEXT,
    status              TEXT NOT NULL DEFAULT 'initiated',
    duration_secs       INTEGER,
    recording_url       TEXT,
    recording_local_path TEXT,
    transcription       TEXT,
    transcription_status TEXT NOT NULL DEFAULT 'none',
    call_mode           TEXT NOT NULL DEFAULT 'bridge',
    user_id             INTEGER REFERENCES users(id),
    entity_type         TEXT,
    entity_id           INTEGER,
    created_at          TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_call_logs_conv_phone ON call_logs(conv_phone);
CREATE INDEX IF NOT EXISTS idx_call_logs_created_at ON call_logs(created_at);
CREATE INDEX IF NOT EXISTS idx_call_logs_provider_call_id ON call_logs(provider_call_id);
CREATE INDEX IF NOT EXISTS idx_call_logs_entity ON call_logs(entity_type, entity_id);
