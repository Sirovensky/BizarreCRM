# BizarreCRM Browser-Dashboard Migration Plan

Status: planning document only. No code changes shipped yet.

This plan replaces the Electron-based management dashboard (`packages/management/`) with a browser-served SPA hosted by the existing BizarreCRM server. The Electron app's ~4500 lines of main-process code, ~89 IPC handlers, ~100 MB Chromium-bundled binary, code-signing pipeline, MSI/DMG packaging, and per-OS auto-start machinery all go away. In their place: an additional set of `/super-admin/api/management/*` REST routes on the existing server, and a static SPA served at `/super-admin` that the operator opens in any browser on any device on the LAN.

This plan is a peer of [serviceplan.md](./serviceplan.md) (PM2 watchdog) and pairs with `TODO.md` `OPS-DEFERRED-001` (cross-platform setup migration). Together those three pieces complete the "any-OS, any-device, no-Electron" target shape.

## Why

Electron is the wrong tool for this app:

- **~100 MB binary per OS** ships Chromium even though every CRM operator already has a browser.
- **Three build pipelines** (main, preload, renderer) + **electron-builder packaging** + **per-OS code signing** is multi-week ongoing maintenance.
- **89 IPC handlers** are ~all "call the server / read a file / spawn a process" — every one of them duplicates work the server itself could do once.
- **Auto-start on boot** is a real cross-platform pain (the deferred multi-OS plan tackles it for the server; doing it AGAIN for Electron is wasted effort).
- **Phone/tablet management is impossible** with Electron. Operators can't check on a shop server from their phone in the parking lot today. Browser-served SPA fixes that for free.
- **Single-system constraint**: the Electron dashboard runs on the same machine as the server. With a browser-served dashboard, any LAN-connected device works.
- **Update flow is awkward**: Electron ships its own auto-updater on top of the server's update flow. Two update channels, two failure modes.

## Constraints That Already Exist

The Electron app does some things that have to keep working:

| Today (Electron) | Tomorrow (browser) |
|------------------|--------------------|
| Read `.env` directly | Auth-gated `GET/PUT /super-admin/api/management/env` |
| Read `logs/*.log` | Auth-gated `GET /super-admin/api/management/logs` (already partially exists) |
| Spawn `pm2 restart` | Auth-gated `POST /super-admin/api/management/server/restart` (exists at `/api/v1/management/restart`) |
| Spawn `sc.exe` | (drop — service mode is sunsetted in the watchdog plan) |
| Browse drives | Auth-gated `GET /super-admin/api/management/drives` |
| Watch crash broadcasts via Electron WS proxy | Direct `/super-admin/ws` from the browser |
| Cert pinning + Authenticode signature checks | Replaced by the browser's own TLS chain check; trust-on-first-use of the local cert |
| Open external links via `shell.openExternal` | `window.open()` |
| OS-native menus / window chrome | Browser tab |
| Auto-start on login | First-run script opens the browser to the dashboard URL; nothing to "auto-start" beyond what the server already does |

## Non-Goals

- **No new desktop app shell.** Tauri / Wails / pwa-builder all save SOME work but reintroduce per-OS packaging. The whole point is to escape that loop.
- **Not solving "manage a crashed server through its own dashboard."** That's a pre-existing gap (Electron only solved it because it could spawn `pm2` directly; users without operator-shell access were already stuck). The Rescue Agent below is a tiny separate process that handles the crashed-main-server case.
- **Not changing the customer-facing CRM web app.** This is purely the **operator/super-admin dashboard** migration. The shop UI stays at `https://localhost/`.

## Architecture

```text
Operator's browser (any device on LAN, any OS)
  │
  ├─→ https://<server>/super-admin               → static SPA (React + Vite build, served by Express)
  ├─→ https://<server>/super-admin/api/...        → existing super-admin routes (already exist)
  ├─→ https://<server>/super-admin/api/management/...  ← NEW — privileged ops moved from Electron main
  └─→ wss://<server>/super-admin/ws               ← NEW — crash + watchdog + log-tail broadcasts

Server (PM2-supervised, watchdog-supervised)
  │
  ├─ static SPA bundle:  packages/server/public/super-admin/      (built from packages/dashboard/)
  ├─ existing super-admin routes
  └─ NEW management routes (mostly thin wrappers around existing services/*)

Rescue Agent (Node, tiny, separate PM2 app — kicks in only when bizarre-crm is dead)
  │
  └─→ http://localhost:7474/rescue   → minimal HTML page that can pm2 restart bizarre-crm + show last logs
```

Three components on disk after migration:

```text
packages/dashboard/         — NEW: static SPA. React + Vite, no Electron.
packages/server/            — adds /super-admin/* HTML route + /super-admin/api/management/* routes
packages/rescue/            — NEW (Phase D): tiny stand-alone agent for the crashed-server case
packages/management/        — DELETED at end of migration (Phase E)
```

## Phased Migration

Each phase is independently shippable and reversible. Phase A and B can run in parallel with the existing Electron app; users do not see the new dashboard until Phase C flips the default.

### Phase A — Server-Side Management API (~1.5 weeks)

Goal: every privileged operation the Electron main process does today is reachable via an authenticated HTTPS route.

**Inventory of IPC handlers to migrate** (89 total — measured from current `packages/management/src/main/ipc/`):

| Domain | Count | Notes |
|--------|------:|-------|
| `management:*` | 19 | Crashes, updates, server control, watchdog events. Most already wrap existing server routes; new endpoints are the env editor, log viewer, watchdog events. |
| `super-admin:*` | 38 | Tenant CRUD, audit log, sessions, security alerts, JWT rotation, per-tenant backup, etc. ALL already exist as server routes — Electron is a passthrough. |
| `admin:*` | 13 | Backup management, env settings, log viewer. Mostly already exist; env editor + log viewer need new routes. |
| `service:*` | 8 | PM2 / Windows Service control. Sunsetted in single-tenant; superseded by watchdog + management:restart-server. |
| `system:*` | 11 | Disk space, drive list, open browser, cert pinning status. Most are not needed in browser context (browser can't open native dialogs from a remote tab; cert pinning is the browser's job). |

The actual NEW server work is small (~10 routes); the bulk is rerouting existing IPC passthroughs.

**Routes to add under `/super-admin/api/management/`** (all super-admin auth + step-up TOTP for state-changing ops):

```
GET    /env                     # Read .env (secrets masked, hasValue + length only — same shape Electron returns today)
PUT    /env                     # Write .env atomically with backup snapshot + length-cap + key-allowlist (mirror existing main-process logic)
GET    /logs                    # List log files under <repo>/logs/
GET    /logs/:name              # Tail a log file (Range header for streaming, max 1MB tail)
GET    /watchdog/events         # Read logs/watchdog-events.jsonl tail (already a management:* IPC handler)
POST   /watchdog/events/clear   # Truncate watchdog events
GET    /drives                  # Host disk list (already exists at admin:list-drives but tenant-blocked in multi-tenant)
GET    /system/disk-space       # Per-path disk space
GET    /system/info             # OS, hostname, Node version, uptime
POST   /server/restart          # Already exists at /api/v1/management/restart — new path is super-admin gated
```

**Security gates on every route**:

- Super-admin JWT (already enforced for `/super-admin/api/*` via `superAdminAuth` at line 535).
- Step-up TOTP on writes (already used for tenant ops; reuse `requireStepUpTotpSuperAdmin`).
- Path containment on every fs op: `isPathUnder(target, repoRoot)` mirroring `service-control.ts`'s trusted-anchor pattern.
- Allowlist for env keys (the Electron `ENV_FIELDS` list moves to a server-side constant — no new schema work).
- Rate limit: write ops max 5/min per super-admin to defeat key-stuffing.

**Dependencies that come along**:

- `audit_log` already used by every super-admin route. New routes write to it identically.
- `master_audit_log` for actor attribution. Backup-route fix from this week's review (`auditBackup(req, ...)`) is the template.
- WebSocket: existing `ws/server.ts` has a `broadcast()` helper for `management:crash`. Add `'/super-admin/ws'` channel that mirrors crash + watchdog + log-tail events. Already 80% of the wiring exists.

**Tests**:

- Existing vitest suite covers tenant + super-admin routes. Add a `__tests__/management-routes.test.ts` per new route — auth gate, step-up gate, path containment, payload validation, audit row written.
- Pester / cross-platform manual: skip — these are HTTP routes, not OS-specific.

**Acceptance**: every existing Electron `ipcMain.handle('management:*')`, `'admin:*'`, `'super-admin:*'`, and useful `'system:*'` channel has a peer HTTP route. No changes to the Electron app yet — it can keep using its IPC handlers in parallel.

### Phase B — Static SPA at `packages/dashboard/` (~1 week)

Goal: a browser-served version of the existing renderer that reuses 90%+ of the React code.

The existing Electron renderer is already React + Vite + Tailwind. The migration is mechanical:

1. **Copy `packages/management/src/renderer/` → `packages/dashboard/src/`.**
2. **Replace `getAPI()` bridge** (`api/bridge.ts`) — currently calls `window.electronAPI.management.foo()` — with a **fetch wrapper** that POSTs to `/super-admin/api/management/foo`. The two return shapes are deliberately compatible (both use `ApiResponse<T>`), so call sites do not change.
3. **Replace WebSocket hook** — currently uses Electron's IPC for crash broadcasts; switch to native `WebSocket('wss://.../super-admin/ws')`.
4. **Drop Electron-only components**: `WindowControls.tsx`, anything reading `process.platform` from Electron context, the Electron-specific cert-pinning warning banner.
5. **Add a session bootstrap**: SPA loads → checks for super-admin cookie → if missing, redirect to `/super-admin/login`. If present, fetch dashboard.
6. **Build target**: `vite build` outputs to `packages/server/public/super-admin/`. Server's static-file middleware already handles `/public/` (verify path; might need a new `app.use('/super-admin', express.static(...))`).
7. **Auth state**: server issues a super-admin JWT cookie (`HttpOnly, Secure, SameSite=Strict`). Login page already exists; just unbinds from Electron's localStorage flow.

**What changes for the operator visually**: nothing. Same dashboard, same components, same colors. The window chrome is now the browser's instead of Electron's.

**What changes under the hood**:

- `getAPI().management.getCrashes()` → `fetch('/super-admin/api/management/crashes', { credentials: 'include' })`.
- `useElectronWS()` → `useWebSocket('/super-admin/ws')`.
- No `preload` allowlist — everything goes through fetch with cookie auth.

**Tests**:

- Vitest renderer tests already exist; they should pass unchanged after the fetch swap.
- New cypress / playwright smoke: load /super-admin, log in, see crash list, click restart server, see status update.

**Acceptance**: SPA accessible at `https://<server>/super-admin/` after login. Functional parity with Electron dashboard for the 80% of operations operators actually use (crashes, backups, server restart, env editor, log viewer, watchdog status, tenant management).

### Phase C-pre — `setup.bat` / `setup.mjs` Migration (~1 day)

`setup.bat` today (verified at `/Users/serega/BizarreCRM/setup.bat`):

- **Step 9** runs `cd packages\management && npm run build && npm run package`. Builds the Electron main + preload + renderer, then runs electron-builder, then copies the unpacked `.exe` to `<repo>\dashboard\`. Several minutes per setup, plus failure modes around code-signing/NSIS.
- **Step 10** launches the server via PM2 AND launches `dashboard\BizarreCRM Management.exe` in a detached window.

Both have to change. The browser-served dashboard ships AS PART OF the server build — a static SPA bundle goes into `packages/server/public/super-admin/`. There is no separate dashboard build step, no Electron, no `.exe` to package.

**Setup.bat changes**:

- [ ] **Drop Step 9 entirely** (the `pushd packages\management && npm run build && npm run package` block). Phase E removes `packages\management\` from disk; Phase C-pre stops invoking it.
- [ ] **Replace dashboard launch in Step 10** with an "open browser to dashboard URL" command. Windows: `start "" https://localhost/super-admin/` — opens in default browser. The server must be reachable for this to work; PM2 starts it in a detached window earlier in Step 10 so by the time `start` runs the listener may not be ready yet. Tolerate the race: the browser shows a connection-refused page and the operator refreshes after a few seconds. Same UX as today's "dashboard shows connecting state if PM2 hasn't finished warming."
- [ ] **Drop the `set "DASHBOARD="` block + the `if defined DASHBOARD` block** entirely. There's no `.exe` to find.
- [ ] **Step 9 numbering**: setup.bat is currently 10 steps. Renumber to 9 OR replace Step 9 with "Build dashboard SPA" — `pushd packages\dashboard && npm run build` — which dumps the static bundle into `packages\server\public\super-admin\` for the server to serve. Build is fast (Vite production build, ~5-15s) and no packaging.
- [ ] **Web build idempotency**: SPA bundle goes into `packages\server\public\super-admin\` (in `.gitignore`). Repeated `setup.bat` runs delete + rebuild it, same as the existing `npm run build` for the server.

**Setup.mjs (per `OPS-DEFERRED-001`) lands the same logic cross-platform**:

- Replace setup.bat dashboard build/launch with:
  ```js
  // Build the dashboard SPA — one cross-platform npm script.
  await spawn('npm', ['run', 'build', '-w', '@bizarre-crm/dashboard']);
  // Open browser to dashboard URL after server is reachable. Try once;
  // if it fails (browser missing, headless env), print the URL and move on.
  const url = `https://localhost:${port}/super-admin/`;
  await openInBrowser(url).catch(() => {
    console.log(`Open ${url} in your browser to access the dashboard.`);
  });
  ```
- `openInBrowser(url)` lives in `scripts/autostart/index.mjs` (new helper, ~20 lines) and dispatches per-OS:
  - macOS: `spawn('open', [url])`
  - Linux: `spawn('xdg-open', [url])`
  - Windows: `spawn('cmd', ['/c', 'start', '', url])`

**Acceptance**:

- Fresh `setup.bat` run on Windows: builds server, builds dashboard SPA, starts PM2 + watchdog, opens browser to `https://localhost/super-admin/`. No Electron build. No `.exe` packaging. ~2-3 minutes faster than today.
- Same behavior on Linux/macOS once `setup.mjs` lands.
- An operator who closes the browser tab can reopen it any time at the same URL. Bookmarks work. Multiple devices on the LAN work.
- Operators on a fresh install hit the self-signed cert warning once per browser per device. Document in operator-guide.

### Phase C — Default Path Switch + First-Run UX (~3 days)

Goal: new operators land in the browser dashboard automatically; existing Electron operators get a deprecation banner.

**First-run flow**:

1. `setup.mjs` (per `OPS-DEFERRED-001`) finishes installing the server.
2. Last step: opens the system browser to `https://localhost/super-admin/setup` via the OS-native open command:
   - macOS: `spawn('open', [url])`
   - Linux: `spawn('xdg-open', [url])`
   - Windows: `spawn('cmd', ['/c', 'start', url])`
3. Setup wizard at that URL handles the existing super-admin password + 2FA bootstrap (the routes already exist; just needs UI).
4. After setup, operator bookmarks the URL and that's the dashboard.

**Existing Electron operators**:

- Phase B ships an in-Electron banner: "Browser dashboard available at `https://<server>/super-admin/` — Electron app will be removed in version X.Y."
- One release of dual-running (4-6 weeks).

**Self-signed cert UX**:

- First visit, browser warns about untrusted cert. Operator clicks "advanced → continue" once.
- Optional: ship a `.crt` file the operator can install in the OS keystore (one-time, documented in operator-guide).
- Real customers running on a public domain (Phase 2) get LE certs and skip this entirely.

**Acceptance**: fresh `setup.mjs` boots → opens browser → setup wizard runs → operator clicks through cert warning once → dashboard works. No Electron app required.

### Phase D — Rescue Agent (~3 days)

Goal: when `bizarre-crm` (the main server) is dead and won't start, the operator still has a browser-accessible page that can do the bare minimum: see why it died and `pm2 restart`.

This is the ONE thing browser-only loses vs Electron: the dashboard can't manage a server it depends on. The fix is a separate process, not bringing back Electron.

**Design**:

- New `packages/rescue/` package — single Node script, runs as a third PM2 app `bizarre-crm-rescue`.
- Listens on `http://localhost:7474` (HTTP, not HTTPS — local-only, no cert needed; `127.0.0.1`-bound).
- Serves a single HTML page (~50 lines, no framework) with three buttons:
  - "Show last 200 lines of `logs/bizarre-crm.err.log`"
  - "Show watchdog events (last 50)"
  - "Run `pm2 restart bizarre-crm`"
- Auth: reads a one-time token from `data/rescue-token` (mode 0600, regenerated on every server start). Operator gets the token from a `setup.mjs` printed line OR from running `cat data/rescue-token` locally.
- PM2 control: spawn pm2 (same pattern as the watchdog).
- Tiny — `~200 lines total` including the HTML.

**Why this isn't just the watchdog with a UI**:

- Watchdog already restarts on programmatic wedges. Rescue is for cases the watchdog gave up on (cascade-abort fatal) where a human needs to make a decision.
- Watchdog runs unconditionally; rescue page is only LOOKED AT when something is wrong.

**Acceptance**: `pm2 stop bizarre-crm` → dashboard at `https://localhost/super-admin` is unreachable → operator opens `http://localhost:7474/rescue` → enters token → sees logs → clicks restart → bizarre-crm is back → dashboard works again.

### Phase E — Delete Electron (~2 days, mostly cleanup)

Goal: remove all Electron-specific code from the repo.

**Order of operations**:

1. Confirm Phase B+C have been live for 4-6 weeks with no rollback signals from operators.
2. Delete `packages/management/` (the entire Electron app).
3. Remove `electron`, `electron-builder`, `electron-vite`, `electron-store` etc. from root + management `package.json`.
4. Drop the GitHub Actions matrix entries that build Electron per-OS.
5. Drop code-signing CI vars (no longer applicable).
6. Update README, operator-guide, developer-guide. Replace every "open the management dashboard" with "open https://<server>/super-admin in your browser."
7. Add a redirect: any user with the OLD Electron app pointing at the server gets a JSON `{ deprecated: true, message: "Use the browser dashboard at https://localhost/super-admin/" }` from any management:* IPC channel — the Electron app already shows toast on backend errors, so they get a clear path forward.

**Sized risk**: this is the only irreversible phase. Once the package is deleted, rolling back means restoring from git. Don't run E until B+C+D have soaked.

**Acceptance**: repo no longer contains `packages/management/`. CI no longer builds Electron. Operator-guide has zero references to "the management app." The Electron download artifacts are removed from any release page.

## Total Effort

| Phase | Effort | Risk |
|-------|--------|------|
| A — Server management API | 1.5 weeks | Medium — new attack surface |
| B — Static SPA | 1 week | Low — mostly mechanical port |
| C-pre — `setup.bat` / `setup.mjs` swap | 1 day | Low |
| C — First-run UX + default flip | 3 days | Low |
| D — Rescue agent | 3 days | Low |
| E — Electron deletion | 2 days | Reversible only via git |
| **Total** | **~4 weeks** | — |

For one engineer. Two engineers in parallel can collapse A and B and ship in ~2.5 weeks.

## Trade-Off Summary

**Wins**:
- ~100 MB binary, three build pipelines, code signing, per-OS packaging — all gone.
- Phone/tablet remote management — free.
- Single codebase, single deploy target.
- Cross-platform setup migration (`OPS-DEFERRED-001`) becomes simpler — only the server needs to start on boot, not server + dashboard.
- No more "Electron version mismatch" or Chromium CVE-tracking work.

**Losses**:
- Crashed-server case needs the Rescue Agent (Phase D) — a real but small piece of new code.
- Self-signed-cert browser warning on first visit per device. One click. Documented.
- No native window chrome / OS-integrated context menus. Operators who care use the browser's controls.
- Browser memory footprint per tab is real but not 100 MB.

**Neutral**:
- Update flow stays the same — already an HTTP-based flow today.
- Auth UX stays the same — login page already exists.
- WebSocket events become standard, not IPC-bridged.

## Decision Points (To Confirm Before Phase A)

1. **Hostname**: dashboard at `https://<server>/super-admin/` (path) vs `https://super-admin.<domain>/` (subdomain). Path-based is simpler; subdomain-based is cleaner for tenant isolation. Recommend path-based for Phase 1.
2. **Cert strategy**: keep self-signed for LAN-only deployments; document LE / Cloudflare Origin cert path for public deployments. Existing `generate-certs.cjs` script handles self-signed.
3. **First-run open-in-browser command**: trust the OS to default-handle `https://`. If multiple browsers installed, the OS picks. Operators can change browser preference. Don't try to be clever.
4. **Rescue token UX**: print to console at startup vs write to file vs print on the rescue page itself ("type this token from the terminal"). File + chmod 0600 is the safest balance.
5. **Phase E timing**: confirm 4-6 weeks of dual-running is enough soak. Could be less if the Electron app sees no usage; could be more if customers protest.

## Out of Scope (For Now)

- Multi-user super-admin sessions with role separation. Existing super-admin model is single-actor; this migration doesn't change that.
- Live tenant SSH-style "shell" into a tenant DB. Out of scope — separate future feature.
- PWA / installable browser-app shell. Could come post-Phase-E if there's demand.
- WebRTC live screen-share to a remote operator. Out of scope.
- Mobile-optimized responsive design beyond what the existing Tailwind layout already does. Phase B keeps current breakpoints; mobile polish is a follow-up.

## Touch Points With Other Plans

- **`serviceplan.md` (PM2 watchdog)**: the watchdog exposes `/api/v1/health/live` and writes `logs/watchdog-events.jsonl`. Phase A's `/super-admin/api/management/watchdog/events` reads that JSONL — one less new mechanism. The Rescue Agent in Phase D reuses the watchdog's `pm2 restart` spawn pattern.
- **`OPS-DEFERRED-001` (cross-platform setup migration)**: Phase C's first-run open-in-browser command lands inside `setup.mjs`. The two plans must merge at that point — implement Phase C as part of the deferred multi-OS work, not separately.
- **Existing `service-control.ts` security model**: Phase A's path-containment + trusted-anchor pattern is already proven there. Reuse, don't reinvent.

## Implementation Order (Across All Three Plans)

```
1. Watchdog (serviceplan.md)              — DONE this session
2. Multi-OS setup migration (OPS-DEFERRED-001)  — pending operator decision on Node bootstrap
3. Phase A  — Server management API       — independent, can start now
4. Phase B  — Static SPA                  — depends on (3)
5. Phase C-pre — setup.bat / setup.mjs swap — depends on (4); merges with (2) when both ready
6. Phase C  — First-run UX                — depends on (2) + (3) + (4) + (5)
7. Phase D  — Rescue agent                — independent, can start any time after (1)
8. Phase E  — Electron deletion           — depends on (4) + (5) + (6) soak time
```

(3), (4), (7) can land in any order without blocking each other. (5), (6), (8) gate on the others.

## Open Questions For The Implementer

- Should the SPA use the existing renderer's Vite config or a stripped-down one? (Existing config has Electron-specific bits. Cleanest: new `packages/dashboard/vite.config.ts` from scratch, copy theme + tailwind config.)
- Should the management routes live in a new `packages/server/src/routes/management.routes.ts` or be added to `super-admin.routes.ts`? (New file, keeps super-admin.routes.ts focused on tenant ops.)
- WebSocket auth: same JWT cookie that authenticates HTTP, or a separate WS token? (Cookie is enough — same-origin policy + SameSite=Strict means no cross-site WS hijack.)
- What happens to the existing Electron auto-updater channel? (Removed in Phase E. Operators update via `setup.mjs` / `setup.sh` — same path the server already uses.)
