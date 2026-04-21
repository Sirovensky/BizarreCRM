-- §18.3 FTS5 search index — porter tokenizer for stemming.
-- Unified virtual table across all entity types.

CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5(
    entity,
    entityId UNINDEXED,
    title,
    body,
    tags,
    updatedAt UNINDEXED,
    tokenize = 'porter unicode61'
);
