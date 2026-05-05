-- 014: Track when SMS conversations were last read by each user
CREATE TABLE IF NOT EXISTS sms_conversation_reads (
    conv_phone TEXT NOT NULL,
    user_id    INTEGER NOT NULL REFERENCES users(id),
    read_at    TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (conv_phone, user_id)
);
