-- Migration 189 — BUGHUNT-2026-05-10-24: per-row optimistic-concurrency
-- version stamp on gift_cards. Two reloads on two tabs can race: T1 reads
-- the row + balance, T2 reads the same row + balance, T1 commits +$25, T2
-- commits +$50, T1's UI shows the +$25 result while the row's actual
-- balance is the +$50 result — masking the second write. Version bump on
-- every mutating route lets the client detect a stale view via If-Match.
ALTER TABLE gift_cards ADD COLUMN version INTEGER NOT NULL DEFAULT 1;
