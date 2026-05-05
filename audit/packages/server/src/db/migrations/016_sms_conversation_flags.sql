-- Add flagging and pinning for SMS conversations
CREATE TABLE IF NOT EXISTS sms_conversation_flags (
    conv_phone TEXT NOT NULL,
    is_flagged INTEGER NOT NULL DEFAULT 0,
    is_pinned  INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (conv_phone)
);
