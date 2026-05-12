# BizarreCRM — Claude operating rules

Minimise token burn during autoloop. Every tick reloads system reminders + memory + tool schemas; unnecessary Read/dup search compounds across 30+ wakes/day.

## Hard rules

### TODO files
- `TODO.md` (1.5 MB) and `DONETODOS.md` (2.1 MB). **NEVER Read in full.** Always `grep -n` for specific marker.
- Loop reads `TODO-blocked.md` (≤300 lines). Pick next `[!]` there.
- When `[!]` → `[x]`, stays in `TODO-blocked.md` with STALE/CLOSED prefix until weekly sweep reconciles into `TODO.md` + `DONETODOS.md`.

### File reads
- "Where is X used/defined" — `grep -n` first. Read only when surrounding context needed.
- Broad multi-file exploration (≥3 likely files) — spawn Explore sub-agent. Don't search main context.
- Never Read a file edited this turn — Edit errors on mismatch, state already known.

### Verification
- Cold preview against this CRM needs login + seeded data. Don't `preview_start` unless route public. Rely on `tsc --noEmit` + Vitest.
- Server-only fixes — `npx tsc --noEmit` in `packages/server` is the contract. Preview adds zero signal.

### Autoloop cadence
- `ScheduleWakeup` delay default **1800s (30 min)**. Don't go below 600s without specific signal to watch. Sub-300s burns prompt cache every tick.
- Cron-mode autoloops (`CronCreate`) — max 4×/hour. 2026-05-11 incident: 45% weekly token budget burned in one day from 2-min cron.

### Model choice
- Mechanical TODO grinding — **Sonnet 4.6** (`claude-sonnet-4-6`). Reserve **Opus 4.7** for design, architecture, security review, multi-step planning.
- Fast mode (`/fast`) — Opus 4.6 only when needed.

### Sub-agent etiquette
- Sub-agents commit to active integration branch direct. No `actionplan/§N-batch-*` per-agent branches.
- Broad codebase exploration — one `Explore` agent, digest summary. No parallel dup searches in main context.

### Commits
- Push `origin/main` after every batch.
- Include `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` (or current-model line) in trailer.

### Out-of-scope detection
- Before editing, scan candidate TODO for: external HTTP scrape, multi-tenant schema migration, 30+ callsite codemod, new third-party SDK. Any = leave `[!]`, add one-line BLOCKED annotation, move on. No broad refactors mid-loop.

## Reference paths

- Server routes: `packages/server/src/routes/*.ts`
- Migrations: `packages/server/src/db/migrations/*.sql`
- Web pages: `packages/web/src/pages/**/*.tsx`
- Shared constants/perms: `packages/shared/src/constants/`
- Audit helper: `audit(db, event, userId, ip, details)`
- Perm helpers: `requirePermission`, `hasPermission`, `requireAdmin`, `requireManagerOrAdmin`, `requireAdminStrict`
