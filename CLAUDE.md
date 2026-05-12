# BizarreCRM — Claude operating rules

Goal: minimise token burn during autoloop runs. Every tick re-loads system reminders + memory + tool schemas; the marginal cost of each unnecessary `Read` or duplicated search compounds across 30+ wakes per day.

## Hard rules

### TODO files
- `TODO.md` and `DONETODOS.md` are 1.5 MB and 2.1 MB respectively. **NEVER read them in full.** Always `grep -n` for the specific marker you need.
- Blocked-item autoloop reads `TODO-blocked.md` (extracted subset, ≤300 lines). Pick next `[!]` from there.
- When a `[!]` flips to `[x]` it stays in `TODO-blocked.md` with the STALE/CLOSED prefix until the weekly sweep reconciles into `TODO.md` + `DONETODOS.md`.

### File reads
- For "where is X used / defined", `grep -n` first. Only `Read` when you need surrounding context.
- For broad multi-file exploration (≥3 likely files), spawn the Explore sub-agent. Do not search the main context.
- Never `Read` a file you already edited this turn — the edit tool errors if mismatched, so the file state is already known.

### Verification
- Cold preview against this CRM needs login + seeded data; do not attempt `preview_start` unless the change is observable on a public/portal route. Rely on `tsc --noEmit` + the existing Vitest suite.
- For server-only fixes, `npx tsc --noEmit` in `packages/server` is the contract; preview adds zero signal.

### Autoloop cadence
- `ScheduleWakeup` delay defaults to **1800s (30 min)**. Do not go below 600s without a specific signal to watch (a long-running build, a webhook reply, etc.). Sub-300s burns the prompt cache every tick.
- Cron-mode autoloops (`CronCreate`) should not fire more than 4× per hour. Today's incident: 45% of weekly token budget burned in one day from a 2-min cron.

### Model choice
- Mechanical TODO grinding = **Sonnet 4.6** (`claude-sonnet-4-6`). Reserve **Opus 4.7** for design, architecture, security review, multi-step planning.
- Toggle Fast mode (`/fast`) on Opus 4.6 only when needed.

### Sub-agent etiquette
- Sub-agents commit to the active integration branch directly. No `actionplan/§N-batch-*` per-agent branches (see memory).
- For broad codebase exploration spawn one `Explore` agent and digest its summary; do not run parallel duplicate searches in the main context.

### Commits
- Always push `origin/main` after every batch.
- Always include `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` (or current-model line) in the commit trailer.

### Out-of-scope detection
- Before editing, scan the candidate TODO item for one of: external HTTP scrape, multi-tenant schema migration, 30+ callsite codemod, new third-party SDK. Any of those = leave `[!]`, add a one-line BLOCKED annotation, move on. Do not start broad refactors mid-loop.

## Reference paths

- Server routes: `packages/server/src/routes/*.ts`
- Migrations: `packages/server/src/db/migrations/*.sql`
- Web pages: `packages/web/src/pages/**/*.tsx`
- Shared constants/perms: `packages/shared/src/constants/`
- Audit helper: `audit(db, event, userId, ip, details)`
- Perm helpers: `requirePermission`, `hasPermission`, `requireAdmin`, `requireManagerOrAdmin`, `requireAdminStrict`
