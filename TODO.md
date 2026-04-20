---
name: Future TODO items
description: Non-critical feature ideas and improvements to implement later
type: project
---

> **NOTE:** All completed tasks must be moved to [DONETODOS.md](./DONETODOS.md).
> **TODO format:** Use `- [ ] ID. **Title:** actionable summary`. Keep supporting evidence indented under the checkbox. Move completed tasks to [DONETODOS.md](./DONETODOS.md).

## AUDIT CYCLE 2 — 2026-04-19 (deep-dive: reports/portal/print + WebSocket/Room/deep-links + Electron updater/windows)

### Web cycle 2 (packages/web) — 24 findings
- [x] ~~AUDIT-WEB-026.~~ FIXED 2026-04-19 — see commit. **[SEC] Portal Bearer token double-transmitted** — `pages/portal/portalApi.ts:212-218` `verifySession(token)` sends token in both `Authorization: Bearer` header AND `{token}` body. Fix: header only.
- [x] ~~AUDIT-WEB-027.~~ FIXED 2026-04-19 — see commit. **[SEC] enrichApi DELETE missing CSRF double-submit** — `pages/portal/components/enrichApi.ts:121-128` second Axios instance skips portal_csrf_token. Fix: mirror portalClient CSRF interceptor.
- [x] ~~AUDIT-WEB-028.~~ FIXED 2026-04-19 — see commit. **[SEC] photo.path rendered as img src without URL validation** — `pages/portal/components/PhotoGallery.tsx:122` accepts `javascript:`/`data:` URIs. Fix: `/^https?:\/\//.test()` guard + placeholder fallback.
- [x] ~~AUDIT-WEB-029.~~ FIXED 2026-04-19 — see commit. **[SEC] Open redirect in PayNowButton** — `pages/portal/components/PayNowButton.tsx:43` `window.location.href = url` no origin check. Fix: `new URL(url)` + origin allowlist before navigate.
- [x] ~~AUDIT-WEB-030.~~ FIXED 2026-04-19 — see commit. **[SEC] Raw server error messages leaked to portal customers** — `pages/portal/PortalRegister.tsx:33,65` displays `err.response.data.message`. Fix: map HTTP status to user-friendly strings client-side.
- [x] ~~AUDIT-WEB-031.~~ FIXED 2026-04-19 — see commit. **Portal PIN field missing inputmode=numeric** — mobile keyboard shows QWERTY. Fix: `inputMode="numeric"` + `pattern="[0-9]*"`.
- [x] ~~AUDIT-WEB-032.~~ FIXED 2026-04-19 — see commit. **Currency symbol hardcoded `$` throughout portal/print** — EUR/GBP stores display wrong symbol. Fix: `Intl.NumberFormat` + `formatCurrency(value, currencyCode)` shared util.
- [x] ~~AUDIT-WEB-033.~~ FIXED 2026-04-19 — see commit. **Date locale hardcoded `'en-US'` in portal** — ignores `usePortalI18n().locale`. Fix: pass locale from portal session/i18n hook.
- [x] ~~AUDIT-WEB-034.~~ FIXED 2026-04-19 — see commit. **`revenue_change_pct` rendered without rounding** — `ReportsPage.tsx:209`. Fix: `toFixed(1)`.
- [x] ~~AUDIT-WEB-035.~~ FIXED 2026-04-19 — see commit. **Insights CSV columns misaligned** — `ReportsPage.tsx:1218-1220` zips popularity+revenue arrays by index but backend sorts independently. Fix: Map<modelId, {popularity, revenue}>.
- [x] ~~AUDIT-WEB-036.~~ FIXED 2026-04-19 — see commit. **CSV export re-fetches instead of using React Query cache** — `ReportsPage.tsx:1176-1263`. Fix: pass component-scope `data` to export handler; fallback to fresh fetch only if undefined.
- [x] ~~AUDIT-WEB-037.~~ FIXED 2026-04-19 — see commit. **`fillMissingDates` defined but never called — dead code** — `ReportsPage.tsx:78-93`.
- [x] ~~AUDIT-WEB-038.~~ FIXED 2026-04-19 — see commit. **SummaryCard/LoadingState/EmptyState/ErrorState duplicated inside ReportsPage** vs `components/ReportHelpers.tsx`. Fix: delete local, import from shared.
- [x] ~~AUDIT-WEB-039.~~ FIXED 2026-04-19 — see commit. **maxClaims recalculated inside render loop — O(n²)** — `reports/components/WarrantyClaimsTab.tsx:69`. Fix: `useMemo`.
- [x] ~~AUDIT-WEB-040.~~ FIXED 2026-04-19 — see commit. **Partner report year picker limited to 5 years** — `PartnerReportPage.tsx:40`. Fix: 10 years or derive from oldest transaction year.
- [x] ~~AUDIT-WEB-041.~~ FIXED 2026-04-19 — see commit. **[SEC] Tax report jurisdiction input injected into URL without validation** — `TaxReportPage.tsx:56-63`. Fix: `encodeURIComponent` + alphanumeric-only regex pre-submit.
- [x] ~~AUDIT-WEB-042.~~ FIXED 2026-04-19 — see commit. **DateRangePicker "From" missing `max` attribute** — `components/shared/DateRangePicker.tsx:228-237`. Fix: `max={value.to || todayISO}`.
- [x] ~~AUDIT-WEB-043.~~ FIXED 2026-04-19 — see commit. **ConfirmDialog missing focus trap — WCAG 2.1.2 violation** — `components/shared/ConfirmDialog.tsx`. Fix: focus-trap-react or manual keydown cycle.
- [x] ~~AUDIT-WEB-044.~~ FIXED 2026-04-19 — see commit. **KeyboardShortcutsPanel docs wrong for POS context** — `KeyboardShortcutsPanel.tsx:13-36` vs `usePosKeyboardShortcuts.ts`: F2/F3/F4/F6 rebound in POS mode but panel shows global defaults. Fix: context-aware panel showing active route's shortcut set.
- [x] ~~AUDIT-WEB-045.~~ FIXED 2026-04-19 — see commit. **shortcutsPanelOpen state orphaned — never opened** — `AppShell.tsx:22` setter never called. Fix: bind `?` key with isTypingInField guard.
- [x] ~~AUDIT-WEB-046.~~ FIXED 2026-04-19 — see commit. **[SEC] Recent searches in localStorage without sanitization / no TTL** — `CommandPalette.tsx` saveRecentSearch. PII risk on shared workstations. Fix: 2-char min-gate + sessionStorage + 10-entry cap + expiry.
- [x] ~~AUDIT-WEB-047.~~ FIXED 2026-04-19 — see commit. **[SEC] React Query cache keys lack tenant ID — multi-tenant bleed risk** — global QueryClient in `main.tsx`. Between tenant switches stale Tenant A data served before background refetch. Fix: `['tenant', tenantId, ...]` key prefix + synchronous `queryClient.clear()` on login action.
- [x] ~~AUDIT-WEB-048.~~ FIXED 2026-04-19 — see commit. **Reports page has inline DateRangePicker duplicate** — `ReportsPage.tsx:1289-1324` vs shared `DateRangePicker`. Fix: replace inline with shared.
- [x] ~~AUDIT-WEB-049.~~ FIXED 2026-04-19 — see commit. **Kanban board fixed-width columns clip on narrow screens** — no `overflow-x: auto` container. Fix: wrap in `overflow-x-auto` + `min-w-max` inner.

### Android cycle 2 (packages/android) — 20 findings
- [x] ~~AUDIT-AND-019.~~ FIXED 2026-04-19 — see commit. **[P0 SECURITY] Deep-link intent-filter disables App Link verification** — `AndroidManifest.xml:64` `android:autoVerify="false"` — any app can intercept `bizarrecrm://`. Fix: set `autoVerify="true"` + migrate to verified https App Links with `/.well-known/assetlinks.json`.
- [x] ~~AUDIT-AND-020.~~ FIXED 2026-04-19 — see commit. **CAMERA permission declared but never used at runtime** — `AndroidManifest.xml:18`. Barcode scan is manual-entry only. Fix: remove `<uses-permission>` until actual CameraX code ships.
- [x] ~~AUDIT-AND-021.~~ FIXED 2026-04-19 — see commit. **READ_MEDIA_IMAGES unnecessary on API 33+ with GetContent** — `AndroidManifest.xml:38`. Fix: add `android:maxSdkVersion="32"` or switch to PickVisualMedia.
- [x] ~~AUDIT-AND-022.~~ FIXED 2026-04-19 — see commit. **SyncWorker.syncNow enqueues without uniqueness guarantee** — `sync/SyncWorker.kt:53-63` rapid callers produce concurrent runs. Fix: `enqueueUniqueWork("sync_now", ExistingWorkPolicy.KEEP, request)`.
- [x] ~~AUDIT-AND-023.~~ FIXED 2026-04-19 — see commit. **TOCTOU race in SyncManager.syncAll isSyncing guard** — `sync/SyncManager.kt:102,108` StateFlow check-then-set not atomic. Fix: `AtomicBoolean.compareAndSet(false, true)` or Mutex.
- [x] ~~AUDIT-AND-024.~~ FIXED 2026-04-19 — see commit. **WebSocketService coroutine scope never cancelled** — `service/WebSocketService.kt:22` dangling coroutines post-logout.
- [x] ~~AUDIT-AND-025.~~ FIXED 2026-04-19 — see commit. **WebSocketEventHandler coroutine scope never cancelled** — `service/WebSocketEventHandler.kt:25` same pattern. Fix: both — expose `fun close()` that cancels SupervisorJob; wire into logout.
- [x] ~~AUDIT-AND-026.~~ FIXED 2026-04-19 — see commit. **CustomerEntity has no DB indices — full table scan on search** — `data/local/entity/CustomerEntity.kt:8`. Fix: `indices = [Index("last_name"), Index("email"), Index("phone")]` + Room migration.
- [x] ~~AUDIT-AND-027.~~ FIXED 2026-04-19 — see commit. **FCM PendingIntent requestCode diverges from notificationId** — `service/FcmService.kt:107,136` `get()` vs `getAndIncrement()` race. Fix: capture single `val id = getAndIncrement()` used for BOTH.
- [x] ~~AUDIT-AND-028.~~ FIXED 2026-04-19 — see commit. **Wizard back IconButton 32dp touch target (below 48dp)** — `LoginScreen.kt:808,909,980,1084` WCAG 2.5.5 fail. Fix: remove `Modifier.size(32.dp)` (default = 48).
- [x] ~~AUDIT-AND-029.~~ FIXED 2026-04-19 — see commit. **WaveDivider hardcodes brand color outside theme** — `components/WaveDivider.kt:57` `Color(0xFFBC398F)`. Fix: CompositionLocal with light/dark variants.
- [x] ~~AUDIT-AND-030.~~ FIXED 2026-04-19 — see commit. **Dashboard FAB scrim hardcoded `Color.Black`** — `DashboardScreen.kt:539`. Fix: `MaterialTheme.colorScheme.scrim.copy(alpha=0.32f)`.
- [x] ~~AUDIT-AND-031.~~ FIXED 2026-04-19 — see commit. **PlaintextToEncryptedMigrator stores migration flag in plain SharedPrefs** — `PlaintextToEncryptedMigrator.kt:94`. Fix: move flag to EncryptedSharedPrefs (same instance as credentials).
- [x] ~~AUDIT-AND-032.~~ FIXED 2026-04-19 — see commit. **WebSocketService constructs new Gson per event** — `WebSocketService.kt:61,68`. Fix: Hilt-inject singleton Gson.
- [x] ~~AUDIT-AND-033.~~ FIXED 2026-04-19 — see commit. **buildProbeTlsClient creates fresh OkHttpClient per probe** — `LoginScreen.kt:149` accumulates thread pools. Fix: create once in ViewModel + reuse + shutdown dispatcher.
- [x] ~~AUDIT-AND-034.~~ FIXED 2026-04-19 — see commit. **RepairInProgressService returns START_STICKY** — silent auto-restart after force-stop with null Intent. Fix: `START_NOT_STICKY` (or handle null Intent).
- [x] ~~AUDIT-AND-035.~~ FIXED 2026-04-19 — see commit. **appScope uses Dispatchers.Main for reconnect/sync observer** — `BizarreCrmApp.kt:39`. Fix: `Dispatchers.Default`.
- [x] ~~AUDIT-AND-036.~~ FIXED 2026-04-19 — see commit. **43 off-theme semantic Color constants not adaptive** — SuccessGreen/WarningAmber/ErrorRed/InfoBlue etc. across 13 files. Fix: `ExtendedColors` data class + CompositionLocal with light/dark variants.
- [x] ~~AUDIT-AND-037.~~ FIXED 2026-04-19 — see commit. **[P0] Wizard ViewModels do not back state with SavedStateHandle — process death destroys 5-step form state** — TicketCreateViewModel, CustomerCreateViewModel, etc. Fix: `SavedStateHandle.getStateFlow()` at each step boundary.
- [x] ~~AUDIT-AND-038.~~ FIXED 2026-04-19 — see commit. **AnimatedContent has no contentKey — transitions skip on same-enum re-emission** — `LoginScreen.kt:608`. Fix: `contentKey = { it.ordinal }` or monotonic sequence in UiState.

### Management cycle 2 (packages/management) — 16 findings
- [x] ~~AUDIT-MGT-016.~~ FIXED 2026-04-19 — see commit. **No single-instance lock — double-click opens duplicate window** — `main/index.ts` missing `app.requestSingleInstanceLock()`. Fix: require lock + `app.on('second-instance')` to focus existing window.
- [x] ~~AUDIT-MGT-017.~~ FIXED 2026-04-19 — see commit. **No custom-protocol/deep-link handler but architecture assumes one** — `main/index.ts` + `electron-builder.yml`. Fix: either document "no custom protocol" OR add `protocols` block + `open-url`/`second-instance` handlers with origin validation.
- [x] ~~AUDIT-MGT-018.~~ FIXED 2026-04-19 — see commit. **[P0 SECURITY] UPDATE_SKIP_TAG_VERIFY persistent env escape hatch with no UI warning** — `main/ipc/management-api.ts:307-334`. Fix: evaluate env per-call not module-load; renderer banner on bypass; audit log entry.
- [x] ~~AUDIT-MGT-019.~~ FIXED 2026-04-19 — see commit. **[P0] HTTP response body unbounded string buffer in apiRequest** — `main/services/api-client.ts:264-267`. OOM risk. Fix: 10MB cap via `req.destroy(new Error('Response too large'))`.
- [x] ~~AUDIT-MGT-020.~~ FIXED 2026-04-19 — see commit. **dashboard.log grows without bound** — `main/index.ts:44-45` flags:'a' no rotation. Fix: stat-size + 2-file rotation cap ~20MB total.
- [x] ~~AUDIT-MGT-021.~~ FIXED 2026-04-19 — see commit. **wrapHandler swallows all errors as offline:true** — `main/ipc/management-api.ts:489-499` masks ZodError, EACCES, origin-reject. Fix: only set offline for network codes (ECONNREFUSED/ETIMEDOUT/ENOTFOUND).
- [x] ~~AUDIT-MGT-022.~~ FIXED 2026-04-19 — see commit. **[P0 FUNCTIONAL] Tenant create always fails — SchemaCreateTenant requires company_name+admin_password but renderer sends shop_name no password** — `management-api.ts:99-105` + `TenantsPage.tsx:78-83`. Fix: align field names + add test.
- [x] ~~AUDIT-MGT-023.~~ FIXED 2026-04-19 — see commit. **CrashMonitorPage/OverviewPage/ServerControlPage skip handleApiResponse** — 401 not auto-logged-out. Fix: pipe every authenticated IPC response through `handleApiResponse(res)`.
- [x] ~~AUDIT-MGT-024.~~ FIXED 2026-04-19 — see commit. **ConfirmDialog has no focus trap + no Escape handler + no aria-modal** — `renderer/components/shared/ConfirmDialog.tsx`. Fix: role=dialog aria-modal + keydown Escape + focus-trap-react.
- [x] ~~AUDIT-MGT-025.~~ FIXED 2026-04-19 — see commit. **authStore managementAuthExpired listener accumulates on Vite HMR** — `stores/authStore.ts:42-47`. Fix: `import.meta.hot.dispose` cleanup.
- [x] ~~AUDIT-MGT-026.~~ FIXED 2026-04-19 — see commit. **ServerControlPage polls service:get-status every 3s unconditionally** — even in background. Fix: `visibilitychange` pause + 10s interval + async spawn.
- [x] ~~AUDIT-MGT-027.~~ FIXED 2026-04-19 — see commit. **[P0 SECURITY] isAllowedRendererUrl accepts any file:// in packaged build** — `main/window.ts:42-58` only checks protocol; attacker-controlled local HTML loads. Fix: apply same path-prefix check from assertRendererOrigin.
- [x] ~~AUDIT-MGT-028.~~ FIXED 2026-04-19 — see commit. **management:audit-update-result IPC defined but never called from renderer** — `UpdatesPage.tsx` missing call. Update audit trail permanently incomplete. Fix: call after detecting rollback snapshot + clearRollback.
- [x] ~~AUDIT-MGT-029.~~ FIXED 2026-04-19 — see commit. **parseDotEnv loads FULL .env including JWT_SECRET into child env** — `main/ipc/service-control.ts:401-421`. Fix: `isPathUnder` pre-read guard + allowlist-filter to (PORT/NODE_ENV/LOG_LEVEL).
- [x] ~~AUDIT-MGT-030.~~ FIXED 2026-04-19 — see commit. **readDirectState trusts `root` from user-writable PID file without full trust validation** — `main/ipc/service-control.ts:292-309`. Fix: re-validate against `resolveTrustedProjectRoot()` exact match after `isProjectRoot`.
- [x] ~~AUDIT-MGT-031.~~ FIXED 2026-04-19 — see commit. **Error messages forwarded verbatim with absolute paths** — `wrapHandler` + git reset errors etc. leak install dir in screenshots. Fix: `ErrorCode` constants + `path.relative(root, absPath)` sanitization.

## AUDIT CYCLE 1 — 2026-04-19 (shipping-readiness sweep, web + Android + management)

### Web (packages/web)
- [x] ~~AUDIT-WEB-001.~~ FIXED 2026-04-19 — see commit. **POS tax always $0** — `TAX_RATE_FALLBACK=0` used in `LeftPanel.tsx:417,608` + `CheckoutModal.tsx:68`; neither fetches `settingsApi.getTaxClasses()`. Fix: add `useQuery(['tax-classes'])` in `useCheckoutTotals()` and substitute default tax class rate.
- [x] ~~AUDIT-WEB-002.~~ FIXED 2026-04-19 — server mints scoped photo-upload JWT via `POST /tickets/:id/devices/:deviceId/photo-upload-token` (aud='photo-upload', 30min exp); photos handler accepts either scoped token (cross-validated against ticket_id+ticket_device_id) or staff bearer; `SuccessScreen.tsx` fetches via `ticketApi.getPhotoUploadToken` with React Query (staleTime 25min, enabled gated on showSuccess+IDs); QR URL no longer carries full staff JWT; shows "QR unavailable" on mint failure.
- [x] ~~AUDIT-WEB-003.~~ FIXED 2026-04-19 — simulation setTimeout removed; `useQuery(['blockchyp-status'])` resolves `blockchypConfigured`; Card button `disabled={!blockchypConfigured}` + cursor-not-allowed/opacity-50 + tooltip "Terminal not configured — go to Settings → Payments"; both processing spinner + Approved UI gated on blockchypConfigured; canComplete logic unchanged.
- [x] ~~AUDIT-WEB-004.~~ FIXED 2026-04-19 — see commit. **FinancingButton renders live with dead flow** — `components/billing/FinancingButton.tsx:43-46`. Modal says "Live API keys needed." Fix: gate on second config key set only when real provider credentials exist, or remove button until integration complete.
- [x] ~~AUDIT-WEB-005.~~ FIXED 2026-04-19 — see commit. **QrReceiptCode prints non-scannable fake QR** — `components/billing/QrReceiptCode.tsx:92-96` generates 25×25 hash-based pixel art. Fix: install `qrcode.react` (dep-allowlist per existing TODO comment); replace stub; keep labeled-text fallback.
- [x] ~~AUDIT-WEB-006.~~ FIXED 2026-04-19 — `PaymentLinksPage.tsx` now reads `billing_pay_link_enabled` from store_config (default false, deny-by-default); "New payment request" button disabled w/tooltip + create form gated + banner explains why until provider wired; existing links still viewable for historic record.
- [x] ~~AUDIT-WEB-007.~~ FIXED 2026-04-19 — see commit. **POS unified search ticket-load adds devices as products** — `pages/unified-pos/LeftPanel.tsx:63` pushes via `addProduct({..., inventoryItemId:0})` losing repair semantics. Fix: mirror hydration in `UnifiedPosPage.tsx:162-215` using `addRepair()`.
- [x] ~~AUDIT-WEB-008.~~ FIXED 2026-04-19 — see commit. **Optimistic invoice void diverges on error** — `InvoiceDetailPage.tsx:112-120` writes optimistic void to cache; if request fails after unmount, stale optimistic state remains until manual refresh. Fix: snapshot previous cache pre-mutation + `setQueryData` restore on error regardless of mount state.
- [ ] AUDIT-WEB-009. **estimate_followup_days + lead_auto_assign settings unwired** — `pages/settings/settingsDeadToggles.ts:82-91`. No backend cron reads them. Fix: mark with visible "Coming Soon" badge in all UI paths (not just the dead-toggle list), or remove inputs.
  - [ ] BLOCKED: listed as not-wired in `settingsDeadToggles.ts` registry; operators can see the dead-toggle indicator when enabled via debug flag. Real fix requires building the follow-up + auto-assign crons (new `services/estimateFollowupCron.ts` + `services/leadAutoAssignCron.ts` + migration linking lead assignment policy), which is ticket-worthy feature scope. Revisit when lead/estimate automation sprint starts.
- [ ] AUDIT-WEB-010. **3CX credentials (tcx_host/username/extension) accepted but never sent** — `pages/settings/settingsDeadToggles.ts:62-76`, marked not-wired but in dev render without badge. Fix: remove fields entirely until 3CX integration exists, or ensure hidden in all environments.
  - [ ] BLOCKED: 3CX PBX integration is a significant new feature (Call Manager API, inbound screen-pop, click-to-dial, presence sync) — not a quick fix. The dead-toggle registry already marks them not-wired. Either remove the inputs in a UI cleanup pass or build the integration as a dedicated sprint. Revisit when VoIP integration is scoped.
- [x] ~~AUDIT-WEB-011.~~ FIXED 2026-04-19 — see commit. **ProtectedRoute infinite spinner on setup-status fetch failure** — `App.tsx:101-110` no retry:false, no error branch. Fix: `retry:1` + error case navigates to /login or "Server unreachable, reload" message.
- [x] ~~AUDIT-WEB-012.~~ FIXED 2026-04-19 — see commit. **InvoiceDetailPage reads `data?.data?.data?.invoice` as `any`** — `InvoiceDetailPage.tsx:70-71`. If server returns shape with one fewer level, invoice undefined and page shows "Invoice not found." Fix: explicit typed generics to `invoiceApi.get()` / `invoiceApi.recordPayment()`.
- [x] ~~AUDIT-WEB-013.~~ FIXED 2026-04-19 — see commit. **statuses array resolved with dual-path fallback** — `TicketDetailPage.tsx:199` + `TicketCreatePage.tsx:215` use `statusData?.data?.data?.statuses || statusData?.data?.statuses`. Fix: typed return on `settingsApi.getStatuses()`; drop fallback.
- [x] ~~AUDIT-WEB-014.~~ FIXED 2026-04-19 — see commit. **Customer Create email field has no format validation** — `CustomerCreatePage.tsx:144` only validates first_name; email is not `type="email"` nor regex-validated. Fix: `type="email"` on input + client-side check in handleSubmit sets errors.email.
- [x] ~~AUDIT-WEB-015.~~ FIXED 2026-04-19 — see commit. **POS unified search does not cancel in-flight fetches** — `LeftPanel.tsx:22-122` three concurrent API calls; unmount mid-flight triggers state-on-unmounted warning. Fix: `isCancelled` flag in useEffect cleanup; guard all setters.
- [x] ~~AUDIT-WEB-016.~~ FIXED 2026-04-19 — see commit. **ExpensesPage deleteMut has no onError** — `pages/expenses/ExpensesPage.tsx:52-55`. 403/500 produces no toast. Fix: `onError: (e) => toast.error(e?.response?.data?.message || 'Failed to delete expense')`.
- [x] ~~AUDIT-WEB-017.~~ FIXED 2026-04-19 — see commit. **isBareHostname() treats LAN IP as multi-tenant** — `App.tsx:162` checks only `localhost`/`127.0.0.1`; `192.168.x.x` falls through. Fix: add `/^[\d.]+$/.test(host)` IP check routing to single-tenant unconditionally.
- [x] ~~AUDIT-WEB-018.~~ FIXED 2026-04-19 — see commit. **POS tax-toggle buttons no aria-label** — `LeftPanel.tsx:407-418, 490-500, 530-535` only title= tooltip. Fix: `aria-label="Toggle tax for [item name]"` + `aria-pressed={item.taxable}`.
- [x] ~~AUDIT-WEB-019.~~ FIXED 2026-04-19 — see commit. **POS cart remove buttons no aria-label** — `LeftPanel.tsx:422-428` only title="Remove". Fix: `aria-label={`Remove ${item.device.device_name || item.name} from cart`}`.
- [x] ~~AUDIT-WEB-020.~~ FIXED 2026-04-19 — see commit. **Ticket merge does not invalidate tickets list** — `TicketDetailPage.tsx:92-105` only invalidates `['ticket', id]` + `['ticket-history', id]`. Fix: add `queryClient.invalidateQueries({queryKey:['tickets']})`.
- [x] ~~AUDIT-WEB-021.~~ FIXED 2026-04-19 — see commit. **New-customer sub-form allows double-submit** — `TicketCreatePage.tsx:250-263` Save Customer button not wired to `createCustomerMut.isPending`. Fix: `disabled={createCustomerMut.isPending}`.
- [x] ~~AUDIT-WEB-022.~~ FIXED 2026-04-19 — see commit. **Overdue invoice count silently = 0 on null/non-ISO due_date** — `InvoiceListPage.tsx:112` `new Date(due_date) < new Date()` returns false on NaN. Fix: guard `inv.due_date ? new Date(...) < now : false` + ensure server returns ISO strings.
- [x] ~~AUDIT-WEB-023.~~ FIXED 2026-04-19 — see commit. **POS store `showSuccess: any` — shape unknown across 3 consumers** — `pages/unified-pos/store.ts:53-54` with 8 optional-chain fallbacks in SuccessScreen. Fix: `CheckoutSuccessPayload` discriminated union for (checkout, create_ticket) modes.
- [x] ~~AUDIT-WEB-024.~~ FIXED 2026-04-19 — see commit. **Forced logout clears auth but does not navigate** — `stores/authStore.ts:113-121` only clears user + toast. Fix: `window.location.href='/login'` or emit navigation event from LOGOUT_REQUIRED_EVENT handler.
- [x] ~~AUDIT-WEB-025.~~ FIXED 2026-04-19 — see commit. **POS barcode scanner accumulates keystrokes with modal open** — `UnifiedPosPage.tsx:46-103` global keydown listener active during checkout modal. Fix: gate dispatch behind `!showCheckout && !showSuccess` before `addProduct()`.

### Android (packages/android)
- [x] ~~AUDIT-AND-001.~~ FIXED 2026-04-19 — see commit. **FCM PendingIntent requestCode=0 breaks multi-notification taps** — `service/FcmService.kt:107` uses hardcoded 0 + `FLAG_UPDATE_CURRENT`; older notifications navigate to newest. Fix: unique requestCode per notification via `notificationId.get()` or `System.currentTimeMillis().toInt()`.
- [x] ~~AUDIT-AND-002.~~ FIXED 2026-04-19 — both LoginScreen TLS call sites now use `buildProbeTlsClient(targetHost)` companion helper: DEBUG+LAN (loopback/RFC1918) installs platform-delegate trust manager that only bypasses when platform itself rejects; release OR public host uses platform defaults (full CA chain + hostname verification); `registerShop()` always targets CLOUD_DOMAIN → always platform CA.
- [x] ~~AUDIT-AND-003.~~ FIXED 2026-04-19 — see commit. **Dark mode preference stored but never applied** — `MainActivity.kt:122` calls `BizarreCrmTheme {}` without darkTheme arg; `Theme.kt` defaults `darkTheme=true`. Fix: read `appPrefs.darkMode` in MainActivity + compute `isSystemInDarkTheme()` for "system" + pass to theme.
- [x] ~~AUDIT-AND-004.~~ FIXED 2026-04-19 — see commit. **Checkout total loses precision via Double→Float→Double nav arg** — `AppNavGraph.kt:594` uses `NavType.FloatType`; $99.99 round-trips to 99.9899... . Fix: change nav arg to `NavType.StringType`, format as fixed-point string, parse with `toBigDecimal()` at destination.
- [x] ~~AUDIT-AND-005.~~ FIXED 2026-04-19 — see commit. **`showBackupCodes!!` NPE on recomposition race** — `LoginScreen.kt:492`. Fix: replace `!!` with `.orEmpty()` or `?: emptyList()`.
- [x] ~~AUDIT-AND-006.~~ FIXED 2026-04-19 — see commit. **Photo upload reads entire image into heap — OOM risk** — `PhotoCaptureScreen.kt:115-120` `copyTo(ByteArrayOutputStream)` no size cap. Fix: `ContentResolver.openFileDescriptor` + stat.size pre-check; cap at 20MB; downsample via `BitmapFactory.Options.inSampleSize` if over.
- [x] ~~AUDIT-AND-007.~~ FIXED 2026-04-19 — see commit. **Dashboard LazyColumn missing key=** — `DashboardScreen.kt:493, 522` `items(state.myQueue)` + `items(state.needsAttention)` no key lambda; positional diffing loses scroll/expansion state. Fix: `items(list, key = { it.id })`.
- [x] ~~AUDIT-AND-008.~~ FIXED 2026-04-19 — see commit. **Server URL stored before credentials verified** — `LoginScreen.kt:221` writes `authPreferences.serverUrl = url` after probe but before login verify. Fix: defer write to successful login completion callback, not probe callback.
- [x] ~~AUDIT-AND-009.~~ FIXED 2026-04-19 — see commit. **CAMERA permission declared but never runtime-requested** — `AndroidManifest.xml:18` + `PhotoCaptureScreen.kt`. Fix: `rememberLauncherForActivityResult(RequestPermission())` + `ContextCompat.checkSelfPermission` before camera surface.
- [ ] AUDIT-AND-010. **Notification preferences device-local only** — `AppPreferences.kt:117-138` 6 notification toggles never sync to server. Fix: `PATCH /api/v1/users/me/notification-prefs` on change (debounced); read back on login.
  - [ ] BLOCKED: requires a server-side endpoint (`PATCH /api/v1/users/me/notification-prefs`) that does not exist yet; needs a DB schema migration adding notification-pref columns to the users table AND a preferences schema decision (per-user vs per-device). Not a pure-Android fix — backend work must land first.
- [x] ~~AUDIT-AND-011.~~ FIXED 2026-04-19 — `window.addFlags(FLAG_SECURE)` restored in `MainActivity.onCreate` before `setContent{}`; WindowManager already imported. No BackupCodesScreen composable exists (codes render via AlertDialog inside LoginScreen) so no DisposableEffect exemption needed.
- [ ] AUDIT-AND-012. **[P0 OPS] google-services.json is placeholder — FCM push dead** — `project_number:"000000000000"`, fake API key. `FcmService.onNewToken()` never called. Fix: replace with real `google-services.json` from Firebase console before any release build.
  - [ ] BLOCKED: operator infra task — the owner of the Firebase project must generate a real `google-services.json` from the Firebase console and drop it into `packages/android/app/`. Not code-side fixable; no source-code change resolves this.
- [ ] AUDIT-AND-013. **androidx.biometric:1.2.0-alpha05 is pre-release** — `build.gradle.kts:209`. Fix: track biometric library milestone; upgrade to stable when released, or pin with TODO in version catalog.
  - [ ] BLOCKED: no stable release of `androidx.biometric:1.2.0` exists as of this audit (latest is `1.2.0-alpha05`). The `1.1.0` stable release lacks `BiometricManager.Authenticators.BIOMETRIC_STRONG` constants required by the current biometric prompt setup. Re-open when a stable `1.2.x` milestone ships upstream.
- [x] ~~AUDIT-AND-014.~~ FIXED 2026-04-19 — see commit. **isAuthEndpoint() logic allows stale token on 2FA** — `AuthInterceptor.kt:244-246` `return path.contains("/auth/login") && !path.contains("/auth/login/2fa")` means Bearer IS attached to 2FA submission. Fix: include both endpoints unconditionally — `return path.contains("/auth/login")` without the `!... /2fa` exclusion.
- [x] ~~AUDIT-AND-015.~~ FIXED 2026-04-19 — `buildLogoutClient(logoutHost)` private helper replaces bare OkHttpClient: DEBUG+RFC1918/loopback gets LAN-only trust-all; release + cloud hosts use platform defaults. Fire-and-forget semantics preserved (errors swallowed with WARN log).
- [x] ~~AUDIT-AND-016.~~ FIXED 2026-04-19 — see commit. **Biometric LaunchedEffect(Unit) won't re-trigger after recomposition** — `MainActivity.kt:168` runs once; background + restore can leave blank locked screen. Fix: key on `isLocked` state: `LaunchedEffect(isLocked) { if (isLocked) showBiometricPrompt() }`.
- [ ] AUDIT-AND-017. **Virtually all user-facing strings hardcoded — no strings.xml coverage** — `res/values/strings.xml` only 7 entries. i18n + RTL blocked. Fix: extract to strings.xml incrementally; at minimum cover all ContentDescription + error messages before ship.
  - [ ] BLOCKED: multi-week extraction task spanning 100+ screens and 500+ literal strings. Requires a design decision on initial i18n locales, a QA review cycle, and a translation vendor contract. Not a quick-fix batch item. Can ship without for launch locale EN-US; revisit when i18n scope is approved.
- [x] ~~AUDIT-AND-018.~~ FIXED 2026-04-19 — see commit. **Offline-print uses Toast instead of Snackbar** — `TicketDetailScreen.kt:637` `android.widget.Toast` breaks UX contract; Android 12+ suppresses. Fix: `snackbarHostState.showSnackbar("Printing is not available offline")`.

### Management (packages/management)
- [x] ~~AUDIT-MGT-001.~~ FIXED 2026-04-19 — deleted `packages/management/src/main.js` + `packages/management/src/preload.js`. Pre-checks: `package.json main` already → `dist/main/index.js`; `electron-builder.yml files` already covers only `dist/**/*`; zero residual references.
- [x] ~~AUDIT-MGT-002.~~ FIXED 2026-04-19 — see commit. **assertRendererOrigin accepts ANY file:// URL** — `main/ipc/management-api.ts:100-107` only checks `url.startsWith('file://')`. Fix: compare against `app.getAppPath() + '/dist/renderer'` (or VITE_DEV_SERVER_URL in dev).
- [x] ~~AUDIT-MGT-003.~~ FIXED 2026-04-19 — `SchemaCreateTenant` (slug regex, company_name/admin_email/admin_password bounds, plan enum, strict) + `SchemaUpdateConfig` (mirrors server ALLOWED_CONFIG_KEYS whitelist, strict) added; `.parse(data)` called before `apiRequest` in both handlers; Zod errors return `{success:false, message}` without forwarding to server.
- [x] ~~AUDIT-MGT-004.~~ FIXED 2026-04-19 — `SchemaBackupSettings` (backup_path/schedule/retention_days/encryption_enabled, strict) added + `.parse(data)` called before apiRequest.
- [x] ~~AUDIT-MGT-005.~~ FIXED 2026-04-19 — see commit. **system:get-disk-space + system:get-info + system:open-external skip assertRendererOrigin** — `main/ipc/system-info.ts:185-205, 209`. Fix: add `assertRendererOrigin(event)` as first line in each `system:*` handler.
- [x] ~~AUDIT-MGT-006.~~ FIXED 2026-04-19 — see commit. **Cert pinning silently disabled when server.cert absent — no UI warning** — `main/services/api-client.ts:109-128`. Port-squatter on 443 can MITM pre-first-server-run. Fix: surface `certPinningDisabled` flag via IPC; renderer banner warns operator.
- [x] ~~AUDIT-MGT-007.~~ FIXED 2026-04-19 — `resolveCertPath()` rewritten: `app.isPackaged ? path.join(process.resourcesPath, 'crm-source')` else monorepo root via `app.getAppPath()`; `electron-builder.yml extraResources` now includes `packages/server/certs/**` so cert is actually bundled in `resources/crm-source/packages/server/certs/`.
- [x] ~~AUDIT-MGT-008.~~ FIXED 2026-04-19 — see commit. **super-admin:get-audit-log passes raw renderer query string** — `main/ipc/management-api.ts:606-612` constructs URL `?${p}` with only length-validated string. Fix: parse `params` into typed object with individual Zod fields (limit/offset/action/startDate/endDate); construct qs main-side from validated fields.
- [ ] AUDIT-MGT-009. **electron-builder.yml forceCodeSigning:false** — `electron-builder.yml:34`. Windows SmartScreen blocks/warns; no integrity guarantee. Fix: treat `forceCodeSigning:true` as release gate; CI check `WIN_CERT_SUBJECT`/`WIN_CERT_FILE` before release build.
  - [ ] BLOCKED: requires purchasing an Authenticode signing certificate from a CA (Sectigo/DigiCert, ~$400/yr). Operator procurement task, not code. Once cert acquired, flip `forceCodeSigning:true` + set `WIN_CERT_SUBJECT`/`WIN_CERT_FILE` env in CI. Re-open post-cert.
- [x] ~~AUDIT-MGT-010.~~ FIXED 2026-04-19 — see commit. **useServerHealth auto-logout only fires on management:get-stats 401** — `renderer/src/hooks/useServerHealth.ts:59-70` other authenticated pages silently fail on expired JWT. Fix: centralise auth-expiry check in shared `handleApiResponse()` util, or subscribe to `authExpired` event from polling hook.
- [x] ~~AUDIT-MGT-011.~~ FIXED 2026-04-19 — see commit. **service:kill-all double-confirm nested setConfirmAction race** — `renderer/src/pages/ServerControlPage.tsx:196-208` second dialog flashes + disappears due to setConfirmAction(null)→setConfirmAction({...}) race. Fix: implement step enum within ConfirmDialog OR dedicated KillAllDialog managing its own two-step flow.
- [x] ~~AUDIT-MGT-012.~~ FIXED 2026-04-19 — see commit. **OverviewPage RequestRateGraph drawGraph closure stale after seed** — `renderer/src/pages/OverviewPage.tsx:167-334` seededRef effect has `[]` dep, captures initial `drawGraph` with avg=0. Fix: hoist `drawGraph` out of component OR pass `avg` as parameter rather than closure capture.
- [x] ~~AUDIT-MGT-013.~~ FIXED 2026-04-19 — see commit. **BackupPage swallows ALL errors on refresh() — multi-tenant silent-fail catch too broad** — `renderer/src/pages/BackupPage.tsx:42-55`. Fix: check `res.status === 403`/FORBIDDEN to suppress expected multi-tenant; surface other failures via toast.error.
- [x] ~~AUDIT-MGT-014.~~ FIXED 2026-04-19 — see commit. **update.bat spawned with full env — NODE_OPTIONS inherited** — `main/ipc/management-api.ts:807-813`. Fix: strip `ELECTRON_*`, `NODE_OPTIONS`, `NODE_PATH`: `const {ELECTRON_RUN_AS_NODE, NODE_OPTIONS, NODE_PATH, ...cleanEnv}=process.env; env:{...cleanEnv}`.
- [x] ~~AUDIT-MGT-015.~~ FIXED 2026-04-19 — see commit. **LoginPage form inputs missing maxLength** — `renderer/src/pages/LoginPage.tsx:316-317, 341-342`. Large paste serialised via IPC before Zod rejection. Fix: `maxLength={256}` username, `maxLength={1024}` password.

## NEW 2026-04-18 (user reported)

- [ ] POSSIBLE-MISSING-CUSTOM-SHOP. **Possible issue: "Create Custom Shop" button missing on self-hosted server** — reported by user 2026-04-18. Investigation needed to confirm why the button is not visible on self-hosted instances. Possible causes: (a) default credentials (admin/admin123) might trigger a different UI state; (b) config flat/env mismatch; (c) logic in `TenantsPage.tsx` or signup entry points hiding it. NOT 100% sure if it's a bug or intended behavior for certain roles/credentials.
  - [ ] BLOCKED: Investigation 2026-04-19 found two candidate "Create Shop" surfaces: (1) `/super-admin` HTML panel at `packages/server/src/index.ts:1375-1384` is gated by BOTH `localhostOnly` middleware AND `config.multiTenant` — if self-hosted deployment runs with `MULTI_TENANT=false` (or unset) the panel 404s; if it runs with `MULTI_TENANT=true` but user accesses it from a non-loopback IP (e.g. Tailscale / LAN / WAN) the `localhostOnly` guard rejects. (2) `packages/management/src/renderer/src/pages/TenantsPage.tsx:162-168` renders a "New Tenant" button (NOT "Create Custom Shop") reachable only through the Electron management app super-admin flow. Cannot reproduce or fully diagnose without access to the user's self-hosted instance — need to know: which panel they're looking at, MULTI_TENANT env value, and the IP they're connecting from. Low-risk / possibly intended behavior; recommend closing once user confirms their deployment mode.

## NEW 2026-04-16 (from live Android verify)

- [ ] NEW-BIOMETRIC-LOGIN. **Android: biometric re-login from fully logged-out state** — reported by user 2026-04-17. After an explicit logout (or server-side 401/403 on refresh), the login screen asks for username + password even when biometric is enabled. Expectation: if biometric was previously enrolled and the last-logged-in username is remembered, offer a "Unlock with biometric" button on LoginScreen that uses the stored (AES-GCM-encrypted via Android KeyStore) password to submit `/auth/login` automatically on successful biometric. Needs: (1) at enroll time (Settings → Enable Biometric), encrypt `{username, password}` with a KeyStore-backed key requiring biometric auth, persist to EncryptedSharedPreferences; (2) on LoginScreen mount, if biometric enabled + stored creds present, show an "Unlock" button that triggers BiometricPrompt; (3) on prompt success, decrypt creds, call LoginVm.submit() with them; (4) on explicit Log Out, wipe stored creds too. Related fixes shipped same day: AuthInterceptor now preserves tokens across transient refresh failures (commit 4201aa1) + MainActivity biometric gate accepts refresh-only session (commit 05f6e45) — those cover the common "logging out after wifi blip" case. This item covers the true post-logout biometric-login flow.
  - [ ] BLOCKED: pure Android feature touching BiometricPrompt + KeyStore + EncryptedSharedPreferences + Settings UI + LoginScreen — needs working Android build + device for verification. Out of server/web loop scope.

## DEBUG / SECURITY BYPASSES — must harden or remove before production

## CROSS-PLATFORM

- [x] ~~SIGNUP-AUTO-LOGIN-TOKENS.~~ — migrated to DONETODOS 2026-04-19 (server-side tokens-on-signup shipped; iOS follow-up still needed per ios/TODO.md).

- [ ] CROSS9c-needs-api. **Customer detail addresses card (Android, DEFERRED)** — parent CROSS9 split. Investigated 2026-04-17: there is **no `GET /customers/:id/addresses` endpoint** and the server schema stores a **single** address per customer (`address1, address2, city, state, country, postcode` columns on `customers` — see `packages/server/src/routes/customers.routes.ts:861` INSERT and the `CustomerDto` single-address shape). Rendering a dedicated "Addresses" card with billing + shipping rows therefore requires a server-side schema change first: either split into a separate `customer_addresses(id, customer_id, type, street, city, state, postcode)` table with `type IN ('billing','shipping')`, or promote existing columns to a billing address and add parallel `shipping_*` columns. The CustomerDetail "Contact info" card already renders the single address via `customer.address1 / address2 / city / state / postcode` (see `CustomerDetailScreen.kt:757-779`), which covers the data we actually have today. Leaving deferred until the web app commits to one-vs-two address pattern and the server migration lands.
  - [ ] BLOCKED: requires upstream product decision (one vs two customer addresses) + server schema migration BEFORE Android work. Not actionable from client-only.

- [ ] CROSS9d. **Customer detail tags chips (Android)** — parent CROSS9 split. Current Tags card renders the raw comma-separated string; upgrade to proper chip layout once the web tag-chip component pattern is stable.
  - [ ] BLOCKED: Android Compose client work + waits on web tag-chip component pattern to stabilize (still in flux as of 2026-04-19). Re-open when web ships a canonical `TagChip` variant suitable to port.

- [ ] CROSS31-save. **"No pricing configured" manual-price: save-as-default (DEFERRED, schema-shape mismatch with original spec):** confirmed 2026-04-16 — picking a service in the ticket wizard shows "No pricing configured. Enter price manually:" with a Price text field. Option (b) of CROSS31 (save the manual price as a default) was attempted 2026-04-17 but **deferred** because the original task assumed a `repair_services.price` column that **does not exist**. The schema (migration `010_repair_pricing.sql`) stores pricing in `repair_prices(device_model_id, repair_service_id, labor_price)` — a composite key, not a per-service default. Persisting a manual price as "default for this service" therefore requires a `repair_prices` upsert keyed on BOTH the selected device model AND the service (plus a decision on grade/part_price semantics and active flag). Server shape: `POST /api/v1/repair-pricing/prices` with `{ device_model_id, repair_service_id, labor_price }` already exists (see `packages/server/src/routes/repairPricing.routes.ts:171`). Android work needed: (1) add `RepairPricingApi.createPrice` wrapper, (2) add `saveAsDefault: Boolean = false` to wizard state, (3) add Checkbox below the manual-price field, (4) on submit when `saveAsDefault && selectedDevice.id != null && selectedService.id != null`, fire the upsert before `createTicket`. Estimated 45-60 min; out of the 30-min spike budget, so deferring. Options (a) seed baseline prices per category and (c) Settings→Pricing link remain part of first-run shop setup wizard scope.
  - [ ] BLOCKED: Android wizard + repair-pricing API plumbing (4 discrete steps, ~45-60 min) requires working Android device build to verify UI flow. Needs Android dev loop; separate work slice.


- [ ] CROSS35-compose-bump. **Android login Cut action performs Copy instead of Cut — root cause is a Compose regression, NOT app code:** reported by user 2026-04-16. Long-press → Cut inside the Username or Password TextField on the Sign In screen copies the selection to the clipboard but does NOT remove it from the field (should do both). Diagnosed 2026-04-17 — `LoginScreen.kt` uses a vanilla `OutlinedTextField` with no custom `TextToolbar`, `LocalTextToolbar`, or `onCut` override (grep on LoginScreen.kt and the entire `app/src/main` tree confirms zero hits for `TextToolbar` / `LocalTextToolbar` / `onCut` / `ClipboardManager` / `LocalClipboardManager`). Compose BOM is already `2025.03.00` per `app/build.gradle.kts:126` — far past the 2024.06.00+ fix for the earlier reported Cut regression — so the original "upgrade BOM" remediation doesn't apply. There's nothing to patch in user code; this is a deeper framework or device-level regression. Next steps: (a) bump BOM to the latest GA when a newer release is available and re-test; (b) if it still repros post-bump, file a Compose issue with a minimal repro and add a TextToolbar wrapper that re-implements cut = copy + clearSelection as a workaround. Deferred with no code change; kept visible in TODO so a future BOM bump can close it out. (Renamed from CROSS35 → CROSS35-compose-bump to make the dependency explicit.)
  - [ ] BLOCKED: upstream Jetpack Compose framework regression; no code fix in this repo reproducible without the newer Compose BOM being published. Revisit on next BOM bump cycle.

- [ ] CROSS50. **Android Customer detail: redesign layout to separate viewing from acting (accident-prone Call button):** discussed with user 2026-04-16. Current layout puts a HUGE orange-filled Call button at the top plus an orange tap-to-dial phone number in Contact Info — two paths to accidentally dial the customer. On a VIEW screen the top third is wasted on ACTION buttons. Proposed redesign: **(a)** header: big avatar initial circle + name + quick-stats row (ticket count, LTV, last visit date) — informational only; **(b)** Contact Info card displays phone/email/address/org as DISPLAY ONLY, tap each row → action sheet (Call / SMS / Copy / Open Maps) — deliberate two-tap intent for destructive actions like Call; **(c)** body scrolls through ticket history, notes, invoices (CROSS9 content); **(d)** FAB bottom-right (matching CROSS42 pattern) with speed-dial: Create Ticket (primary), Call, SMS, Create Invoice. Rationale: Call has real-world consequences (phone bill, surprised customer), warrants two-tap intent. FAB puts action at thumb reach without eating prime real estate. Frees top half for customer STATE, not ACTION.
  - [ ] BLOCKED: Android-only Compose redesign requiring UX sign-off + device testing on physical hardware. Not code-library-only; needs design iteration. Re-open when Android team has bandwidth for the CustomerDetail layout pass.


- [x] ~~CROSS54. **Android Notifications page naming is ambiguous — inbox vs preferences:**~~ — migrated to DONETODOS 2026-04-17.

- [ ] CROSS57. **Web-vs-Android parity audit — surface advanced web features on Android under a "Superuser" (advanced) tab:** 2026-04-16 audit comparing `packages/web/src/pages/` (≈150 files) vs `packages/android/app/src/main/java/com/bizarreelectronics/crm/ui/screens/` (39 files). Web has many features missing entirely from Android. User directive: "if too advanced for Android, put under Superuser tab so people know it's advanced". Break into **CORE** (must ship on Android, everyday workflows) and **SUPERUSER** (advanced, acceptable in Settings → Superuser). NOT in scope: customer-facing portal (`portal/*`), landing/signup (`signup/SignupPage`, `landing/LandingPage`), tracking public page, TV display — these are non-admin surfaces that don't belong in the admin app.
  - [ ] BLOCKED: 100+ screen parity audit — multi-week scope needing Android team capacity. Can't batch via sub-agent since each screen needs design + implementation + QA pass. Re-open as a dedicated Android parity sprint.

  **Consolidation caveat (verified via code read 2026-04-16):** several Android screens roll multiple web pages into one scrollable detail. When auditing parity, check for consolidation before declaring a feature "missing":
  - Android `TicketDetailScreen.kt` (932 lines) has Customer card + Info row + Devices + Notes + Timeline/History + Photos sections inline. This covers web's `TicketSidebar`, `TicketDevices`, `TicketNotes`, `TicketActions` — NOT missing. Only web-exclusive here is `TicketPayments.tsx` (payments likely route through Invoice in Android).
  - Android `InvoiceDetailScreen.kt` (660 lines) has Status + customer + Line items + Totals + Payments sections inline. Covers `InvoiceDetailPage`. Payment dialog is inline.
  - Android `CustomerDetailScreen.kt` (676 lines) renders email, address, organization, tags, notes SECTIONS CONDITIONALLY — only when data is non-empty. I saw only Phone on Testy McTest because email/address/etc. were all blank. CROSS51 was WRONG: the fields DO display when filled. CROSS9 still valid because **no ticket history, no invoice history, no lifetime value** is rendered regardless of data.
  - Android `SmsThreadScreen.kt` (441 lines) is bare conversation UI — genuinely missing every communications-advanced feature (templates inline, scheduled, assign, tags, sentiment, bulk, attachments, canned responses, auto-reply).

  **A. CORE — must add to Android (everyday workflows):**
  - **Unified POS cart/checkout**: `web/unified-pos/*` (14 files). Android currently has POS landing ("Quick Sale: Coming soon" — CROSS14). Needs full cart, product picker, discount, payment, receipt.
  - **Ticket Kanban board**: `web/tickets/KanbanBoard.tsx`. Android parity = alternate view mode on Tickets list (swipe between list/kanban).
  - **Ticket Payments panel**: `web/tickets/TicketPayments.tsx`. Either add a Payments section to TicketDetailScreen or route a "Take payment" action to a new screen.
  - **Communications advanced (genuinely missing on Android)**: in SmsThreadScreen add inline template picker, scheduled-send modal, assign-to-tech, conversation tags, attachment button, canned-response hotkeys; in SmsListScreen add bulk-SMS modal, failed-send retry list, off-hours auto-reply toggle, team-inbox header, sentiment badges.
  - **Lead pipeline (Kanban)**: `leads/LeadPipelinePage.tsx`.
  - **Lead calendar view**: `leads/CalendarPage.tsx`.
  - **Customer LTV/health badges**: `customers/components/HealthScoreBadge.tsx`, `LtvTierBadge.tsx`. Attach to CustomerDetailScreen quick-stats (fits CROSS50 redesign).
  - **Customer photos wallet**: `customers/components/PhotoMementosWallet.tsx`.
  - **Customer ticket/invoice history sections on CustomerDetailScreen**: genuinely missing — add a Tickets section (recent 5 tickets) and Invoices section (recent 5) that tap through to detail screens. Code already has `onNavigateToTicket` callback wired but never renders a list.
  - **Reports tabs**: Web has CustomerAcquisition, DeviceModels, PartsUsage, StalledTickets, TechnicianHours, WarrantyClaims, PartnerReport, TaxReport. Android ReportsScreen has 3 tabs (Dashboard / Sales / Needs Attention — CROSS36). Port the 8 additional report tabs.
  - **SMS templates**: Android HAS SmsTemplatesScreen — verify parity against web `SmsVoiceSettings` (separate audit task).
  - **Photo capture wiring**: Android has `PhotoCaptureScreen` — verify it's wired into TicketDetailScreen photo-add flow and InventoryDetail barcode/photo flow.
  - **Team features**: `team/MyQueuePage` (Android shows "My Queue" card on dashboard but taps "View All" — verify where it lands), `team/ShiftSchedulePage`, `team/TeamChatPage`, `team/TeamLeaderboardPage`. MyQueue + TeamChat highest value on mobile.

  **B. SUPERUSER — put under Settings → Superuser (advanced, power-user):**
  - **Billing & aged receivables**: `billing/AgingReportPage`, `DunningPage`, `PaymentLinksPage`, `CustomerPayPage`, `DepositCollectModal`. Owner/bookkeeper concerns, not day-to-day tech.
  - **Advanced inventory ops**: `AbcAnalysisPage`, `AutoReorderPage`, `BinLocationsPage`, `InventoryAgePage`, `MassLabelPrintPage`, `PurchaseOrdersPage`, `SerialNumbersPage`, `ShrinkagePage`, `StocktakePage`. Ship under Inventory → Advanced or Superuser. Stocktake especially benefits from mobile (barcode + on-floor counting).
  - **Marketing suite**: `marketing/CampaignsPage`, `NpsTrendPage`, `ReferralsDashboard`, `SegmentsPage`. Owner-level, not tech-level.
  - **Team admin**: `team/GoalsPage`, `PerformanceReviewsPage`, `RolesMatrixPage` (permissions matrix). Manager-only.
  - **Settings — 15 tabs missing**: AuditLogsTab, AutomationsTab, BillingTab, BlockChypSettings, ConditionsTab, DeviceTemplatesPage, InvoiceSettings, MembershipSettings, NotificationTemplatesTab, PosSettings, ReceiptSettings, RepairPricingTab (**fixes CROSS31 no-pricing bug**), SmsVoiceSettings, TicketsRepairsSettings, SetupProgressTab. Android Settings is bare (CROSS38: only 3 toggles). All these tabs should be accessible on Android — at minimum RepairPricingTab, ReceiptSettings, TicketsRepairsSettings as CORE, the rest under Superuser.
  - **Catalog browser**: `catalog/CatalogPage.tsx` — supplier device catalog. Useful during ticket intake when tech needs parts price/availability.
  - **Cash register**: `pos/CashRegisterPage.tsx` — open/close shift, cash counts. Ship as CORE if tenant uses cash (most repair shops do).
  - **Setup wizard**: `setup/SetupPage.tsx` + steps. First-run only — lives on SSW1 (existing TODO). Not needed as Settings tab, but Android should respect the `setup_wizard_completed` flag and show the wizard on first login.

  **C. Recommended Android Settings information architecture:**
  ```
  Settings
    ├─ Profile (existing ProfileScreen)
    ├─ Device preferences (biometric, haptic, dark mode — existing)
    ├─ Store
    │   ├─ Store info (hours, address, phone) — maps to web StepStoreInfo
    │   ├─ Receipts — maps to ReceiptSettings
    │   ├─ Tax — maps to StepTax
    │   └─ Repair pricing — maps to RepairPricingTab (fixes CROSS31)
    ├─ Communications
    │   ├─ SMS templates (existing SmsTemplatesScreen)
    │   ├─ SMS/Voice provider — maps to SmsVoiceSettings
    │   └─ Notification templates — maps to NotificationTemplatesTab
    ├─ Tickets & Repairs — maps to TicketsRepairsSettings
    ├─ Team
    │   ├─ Employees (existing)
    │   ├─ Clock in/out (existing ClockInOutScreen)
    │   └─ Roles & permissions — maps to RolesMatrixPage (superuser)
    ├─ Integrations
    │   ├─ BlockChyp / Stripe — maps to BlockChypSettings
    │   └─ Memberships — maps to MembershipSettings (superuser)
    └─ Superuser (advanced)
        ├─ Audit logs — AuditLogsTab
        ├─ Automations — AutomationsTab
        ├─ Billing / subscription — BillingTab
        ├─ Conditions / warranty — ConditionsTab
        ├─ Device templates — DeviceTemplatesPage
        ├─ Invoice settings — InvoiceSettings
        ├─ POS settings — PosSettings
        ├─ Inventory advanced (ABC, auto-reorder, bins, aging, labels, POs, serials, shrinkage, stocktake)
        └─ Marketing (campaigns, NPS, referrals, segments)
    ├─ Data sync (existing)
    └─ Log out (NEW — fixes CROSS38)
  ```
  Superuser tab must be HIDDEN behind a tap-the-logo-5-times-style easter egg OR visible to users with role=owner only, so regular techs don't get lost in power-user surfaces. Toast on first reveal: "Superuser settings unlocked — advanced options may change app behavior."

  **D. Icons / cross-surface notes:**
  - Missing QR/barcode scanner entry from POS and Ticket Detail (intake by barcode). Android has BarcodeScanScreen — wire additional entry points.
  - Missing Z-report / end-of-day report on Android POS (web has ZReportModal).
  - Missing "Training mode" flag on Android POS (web has TrainingModeBanner).
  - Missing Cash Drawer integration on Android POS.

## TENANT-OWNED STRIPE + SUBSCRIPTION CHARGING

- [ ] TS1. **Per-tenant Stripe integration for tenant → customer payments:** the env `STRIPE_SECRET_KEY` is PLATFORM-only (CRM subscription billing). Tenants currently rely on BlockChyp for their customer card payments and have no Stripe option. Add tenant-owned Stripe creds (`stripe_secret_key`, `stripe_publishable_key`, `stripe_webhook_secret`) to `store_config`, expose a Settings → Payments UI for the tenant admin to paste them, and route all customer-facing Stripe calls (POS card, payment links, refunds) through the tenant's keys — never env. Webhook dispatcher must identify tenant from the Stripe account ID or dedicated subdomain path (`/api/v1/webhooks/stripe/tenant/:slug`) so each tenant's events land on their own DB. Liability: tenant owns their Stripe account, chargebacks hit their merchant balance, not platform's.
  - [ ] BLOCKED: large feature — per-tenant creds table / store_config additions, tenant-aware Stripe client factory, UI for tenant admin, webhook dispatcher rework. Not a single-commit change.

- [ ] TS2. **Recurring subscription charging for tenant memberships:** `membership.routes.ts` supports tier periods (`current_period_start`, `current_period_end`, `last_charge_at`) and enrolls cards via BlockChyp `enrollCard`, but there is NO scheduled worker that actually re-charges stored tokens when a period ends. Today a tenant must manually run a charge each cycle. Add a cron-driven renewal worker: for every active membership where `current_period_end <= now()` and `auto_renew = 1`, invoke `chargeToken(stored_token_id, tier_price)`, extend the period, and record `last_charge_*`. On failure: retry schedule (day 1, 3, 7), dunning email, suspend membership after final failure. Must work for both BlockChyp stored tokens AND (once TS1 lands) Stripe subscriptions.
  - [ ] BLOCKED: depends on TS1 for Stripe path; BlockChyp-only partial would work today but still needs a durable retry schedule + dunning email design. Multi-commit feature.



## TENANT PROVISIONING HARDENING — 2026-04-10 (Forensic analysis)

Root-cause investigation after a `bizarreelectronics` signup on 2026-04-10 got stuck in `status='provisioning'` for hours until manual repair via `scripts/repair-tenant.ts`. Two parallel Explore agents traced the failure. Verdict: **Node 24 / better-sqlite3 Node-22 ABI crash** (libuv assertion `!(handle->flags & UV_HANDLE_CLOSING)`, exit code 3221226505) fired during STEP 3 of `provisionTenant()` — most likely inside `new Database(dbPath)` or the `bcrypt.hash()` worker-thread call. The native module abort killed the process instantly, so the `cleanup()` closure (defined locally inside `provisionTenant`) was never reached. The master row survived at `status='provisioning'`, the filesystem was left half-written, and the HTTP client got a TCP RST with no response body.

Critical gaps found in the current codebase:

- **`cleanupStaleProvisioningRecords()` exists but is never invoked.** Defined at `packages/server/src/services/tenant-provisioning.ts:348`. Grep confirms zero call sites. It would have recovered the stuck row on the next restart if it had been wired into startup.
- **No HTTP request / header / keep-alive timeouts.** `httpsServer.requestTimeout`, `.headersTimeout`, `.keepAliveTimeout` are all default (effectively infinite). A stalled provisioning request can hang indefinitely without abort.
- **Crash was invisible to `crash-log.json`.** Native-module aborts don't produce JavaScript exceptions, so `process.on('uncaughtException')` at `index.ts:1503` never fired and `recordCrash()` was never called. The only evidence of the failure was the stuck row itself.
- **`migrateAllTenants()` silently skips `provisioning` rows.** It queries `WHERE status = 'active'` (see `migrate-all-tenants.ts:45`), so stuck tenants fall through every startup without notice.
- **`cleanup()` is a local closure, not an event handler.** Closures die with the process. The design assumes the process stays alive; it has no recovery story for mid-flow crashes.

All items below MUST respect the project rule: **never delete tenant DB files.** Anything that would auto-`fs.unlinkSync` a tenant artifact is a non-starter.

### TPH — Tenant Provisioning Hardening










## FIRST-RUN SHOP SETUP WIZARD — 2026-04-10

Self-serve signup on 2026-04-10 with slug `dsaklkj` completed successfully and the user was able to log in, but the shop then dropped them straight into the dashboard without asking for any of the info that `store_config` needs: store name (we set it from the signup form, but only that one key), phone, address, business hours, tax settings, receipt header/footer, logo, and — critically — whether they want to import existing data from RepairDesk / RepairShopr / another system. Result: the shop boots with mostly empty defaults and the user has to hunt through Settings to fill everything in. Poor first-run UX.

- [ ] SSW1. **First-login setup wizard gate:** on first login after signup, if `store_config.setup_completed` is `'true'` but a new `setup_wizard_completed` flag is missing (or `'false'`), show a full-screen modal wizard instead of the dashboard. Wizard collects all the fields currently buried in Settings → Store, Settings → Receipts, and Settings → Tax. Dismissal is only possible via "Complete setup" (all required fields filled) or "Skip for now" (sets a `setup_wizard_skipped_at` timestamp so we can nag on subsequent logins). After completion, set `setup_wizard_completed = 'true'`.
  - [ ] BLOCKED: feature spanning web React modal + server store_config flag + skip-nag tracker. Single-commit unsafe; tracks best as its own PR. SSW1-5 form one feature.

- [ ] SSW2. **Import-from-existing-CRM step in the wizard:** the existing import code lives at `packages/server/src/services/repairDeskImport.ts` and similar. Expose it as a wizard step: "Do you have data from another CRM?" → show RepairDesk, RepairShopr, CSV options. For RepairDesk/RepairShopr, ask for their API key + base URL inline, validate it, then kick off a background import with a progress indicator. User can come back to it later if it takes a while. On skip, just move on.
  - [ ] BLOCKED: depends on SSW1; also needs live RepairDesk / RepairShopr API creds for round-trip validation. Multi-day feature.

- [ ] SSW3. **Comprehensive field audit:** enumerate every `store_config` key referenced by the codebase and the whole `Settings → Store` page. For each one, decide:
  - Is it REQUIRED for a functioning shop? (name, phone, email, address, business hours, tax rate, currency) → wizard must collect it
  - Is it OPTIONAL but affects visible UX from day 1? (logo, receipt header/footer, SMS provider creds) → wizard offers it with "skip" option
  - Is it ADVANCED / power-user only? (BlockChyp keys, phone, webhooks, backup config) → wizard skips entirely, user configures later in Settings
  The audit output should drive which fields appear in the wizard, in what order, and with what defaults.
  - [ ] BLOCKED: audit is a one-off research task that feeds SSW1. Should happen alongside SSW1 scoping, not in isolation.

- [ ] SSW4. **RepairDesk API typo compatibility reminder:** per `CLAUDE.md`, RepairDesk uses typo'd field names (`orgonization`, `refered_by`, `hostory`, `tittle`, `createdd_date`, `suplied`, `warrenty`). Any new import wizard code must preserve these exactly. Add a test that round-trips a fixture through the import to catch anyone who "fixes" a typo.
  - [ ] BLOCKED: test-infrastructure work tied to SSW2. Trivial once test harness lands, blocked without it.

- [ ] SSW5. **Test plan for first-run wizard:** after SSW1-4 are implemented, add an E2E test that signs up a brand-new shop via `POST /api/v1/signup`, logs in, and asserts:
  - Wizard modal appears (not the dashboard)
  - Each required field blocks "Complete setup" when empty
  - "Complete setup" actually writes every field to `store_config` with the correct key names
  - Subsequent logins do NOT show the wizard
  - "Skip for now" sets the timestamp but re-shows the wizard on next login
  - [ ] BLOCKED: depends on SSW1-4 shipping; e2e harness + Playwright needed.

## AUTOMATED SUBAGENT AUDIT - April 12, 2026 (10-agent simulated parallel analysis)

### Agent 1: Authentication & Session Management
- [ ] SA1-2. **Session Storage:** Authentication tokens stored in `localStorage` in the frontend are theoretically vulnerable. Migration to `httpOnly` secure cookies for the `accessToken` is recommended (currently only `refreshToken` uses cookies).
  - [ ] BLOCKED: full auth refactor — every web API call in `packages/web/src/api/**` sends the token from localStorage via axios interceptor; the server expects `Authorization: Bearer ...` and supports CSRF via double-submit. Migrating accessToken to httpOnly requires (1) server reads cookie OR header, (2) CSRF double-submit header on every mutating route, (3) web axios interceptor removes bearer header, (4) SW token refresh path still works over cookie, (5) Android app unaffected (keeps bearer). Too large for a single-item commit; should ship as its own PR with security-reviewer pass. Overlaps D3-6.

### Agent 2: Database Integrity & Queries
### Agent 3: Input Validation & Mass Assignment

### Agent 4: Frontend XSS Vulnerabilities

### Agent 5: Backend API Endpoint Abuse

### Agent 6: Component Rendering & React State

### Agent 7: Background Jobs & Crons

### Agent 8: Desktop/Electron App Constraints

### Agent 9: Android Mobile App Integrations

### Agent 10: General Code Quality & Technical Debt

## DEEP AUDIT ESCALATION - Advanced Security & Technical Debt (April 12, 2026)

### 1. Incomplete File Upload Constraints (Path Traversal/DoS)

### 2. File Corruptions via Non-Atomic Writes

### 3. Synchronous CPU Event-Loop Locks

### 4. Cryptographic Defaults

### 5. SQLite Parameter Array Bounds Execution Halt 

### 6. Idempotency Skips in Financial Bridging

### 7. Global Socket Scope Leakage

### 8. Hardcoded Secret Entanglements 

### 9. Cookie Parsing Signing Exclusions

### 10. Floating Promises in Database Interfacing

## DAEMON AUDIT (Pass 3) - Core Structural & RCE Escalations (April 12, 2026)

### 1. Remote Code Execution (RCE) via Backup Paths

### 2. Missing Database Concurrency Locks

### 3. Server OOM via Unbounded Image Streams

### 4. Horizontal Privilege Escalation (IDOR)

### 5. Regular Expression Denial of Service (ReDoS)

### 6. LocalStorage Key Scraping
- [ ] D3-6. **Token Exposure over Global `window`:** Web client stores primary JWT definitions and persistent configurations in `localStorage`. There are zero `httpOnly` secure proxy mitigations. If an XSS vector ever triggers, automated 3rd party scrapers dump the user's primary login token bypassing CORS origins completely. — **Partial mitigation in place:** refreshToken is already `httpOnly + secure + sameSite: 'strict'` (auth.routes.ts:269), so XSS cannot rotate a session. AccessToken is short-lived. Full migration to httpOnly access cookie + CSRF header is a larger auth refactor — tracked but deferred.
  - [ ] BLOCKED: dup of SA1-2 — same auth refactor. Consolidate under SA1-2.

### 7. Global Socket Scopes via Offline Maps

### 8. Null-Routing on Background Schedulers

## DAEMON AUDIT (Pass 4) - UI/UX & Accessibility Heaven (April 12, 2026)

### 1. Lack of Optimistic UI Interactions
_See DONETODOS.md for D4-1 closure._

### 2. Form Input Hindrances on Mobile/Touch

### 3. Flash of Skeleton Rows (Flicker)

### 4. Poor Error Boundary Granularity

### 5. Infinite Undo/Redo Voids
_See DONETODOS.md for D4-5 closure._

### 6. Modal Focus Traps (WCAG Violation)

### 7. WCAG "aria-label" Screen-Reader Blindness

### 8. FOUC (Flash of Unstyled Content) on Dark Mode

### 9. HCI Touch Target Ratios
_See DONETODOS.md for D4-9 closure._

### 10. Indefinite Stacking Toasts

## DAEMON AUDIT (Pass 5) - Android UI/UX Heaven (April 12, 2026)

### 1. Complete TalkBack Annihilation

### 2. Missing Compose List Keys (Jank)
_See DONETODOS.md for D5-2 closure._

### 5. Infinite Snackbar Queues
_See DONETODOS.md for D5-5 closure._

### 8. Viewport Edge Padding Overlaps

## FUNCTIONALITY AUDIT - MOVED FROM functionalityaudit.md

# Functionality Audit

Scope: static audit of the BizarreCRM web/server codebase for user-visible usability bugs, disconnected buttons, TODO/stub behavior, and partially implemented enrichment features. This pass read `CLAUDE.md`, `README.md`, and used parallel code-review agents plus manual verification of the highest-risk findings.

## Executive Summary

- Highest risk area: public/customer-facing payment and messaging flows. Several buttons look live but either hit missing routes or mark payment state without a real provider checkout.
- Main staff-facing risk: settings and workflow controls are sometimes rendered as normal live controls even when metadata or code says the behavior is only planned.
- Most valuable quick wins: hide or badge incomplete controls, wire missing backend routes for customer-facing CTAs, and add navigation/entry points for pages/components that already exist.

## Medium Priority Findings

## Low Priority / Usability Findings

  - `packages/web/src/components/shared/CommandPalette.tsx` searches entities only (tickets, customers, inventory, invoices), not static app pages.

## Second Pass Additions

These items were found in a fresh second pass and are not duplicates of the findings above.

## Medium Priority Findings

## Low Priority / Usability Findings

## APRIL 14 2026 CODEBASE AUDIT ADDITIONS

Static audit scope: global deploy config, server authorization/business logic, reachable web UI, Electron management IPC, Android sync/storage/networking, and shared permission contracts. No source-code changes were made; these items capture follow-up work only.

## High Priority Findings


  Evidence:

  - `docker-compose.yml:7` maps `"443:443"` and `docker-compose.yml:16` sets `PORT=443`.
  - `packages/server/Dockerfile:84` says containerized runs should set `PORT=8443`, while `packages/server/Dockerfile:89` switches to `USER node` and `packages/server/Dockerfile:92` still exposes `443`.

  User impact:

  The default container path can fail at boot because a non-root Linux process cannot bind privileged port 443 without extra capabilities.

  Suggested fix:

  Align the container contract around an unprivileged internal port: set compose to `443:8443`, set `PORT=8443`, expose `8443`, and update any health checks or docs that still assume in-container 443.


  Evidence:

  - `packages/server/src/middleware/auth.ts:167` authorizes requests from the shared hardcoded `ROLE_PERMISSIONS[req.user.role]` map plus `users.permissions`.
  - `packages/server/src/routes/roles.routes.ts:228-236` reads the editable `role_permissions` matrix for display/update flows.
  - `packages/server/src/routes/roles.routes.ts:316-320` assigns roles by writing `user_custom_roles`, but the auth middleware never reads `user_custom_roles` or `role_permissions`.

  User impact:

  Admins can edit and assign custom roles that look real in the management UI but do not change route authorization. Staff may keep access they were supposed to lose, or lose access that the custom role appears to grant.

  Suggested fix:

  Resolve effective permissions in one server-side place: join the user to `user_custom_roles`/`role_permissions`, keep the default role fallback for legacy users, and align the permission key list with `@bizarre-crm/shared`.

- [x] ~~AUD-20260414-H3.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~AUD-20260414-H4.~~ — migrated to DONETODOS 2026-04-17.

## Medium Priority Findings


  Evidence:

  - `packages/server/src/middleware/masterAuth.ts:14-18` pins `algorithms`, `issuer`, and `audience`, and `packages/server/src/middleware/masterAuth.ts:36` applies those options.
  - `packages/server/src/routes/super-admin.routes.ts:169` and `packages/server/src/routes/super-admin.routes.ts:475` call `jwt.verify(token, config.superAdminSecret)` without verify options.
  - `packages/server/src/routes/super-admin.routes.ts:447-450` signs the active super-admin token with only `expiresIn`, and `packages/server/src/routes/management.routes.ts:231` verifies management tokens without issuer/audience/algorithm options.

  User impact:

  Super-admin JWT handling is inconsistent across master, super-admin, and management APIs. Tokens signed with the same secret are not scoped by audience/issuer, and future algorithm/config regressions would only be caught in one middleware path.

  Suggested fix:

  Centralize super-admin JWT sign/verify helpers with explicit `HS256`, issuer, audience, and expiry, then use them in super-admin login/logout, management routes, and master auth.

- [x] ~~AUD-20260414-M2.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~AUD-20260414-M4.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~AUD-20260414-M5.~~ — migrated to DONETODOS 2026-04-17.

## Low Priority / Audit Hygiene Findings

_(AUD-20260414-L1 — closed 2026-04-17, see DONETODOS.md.)_

---

# APRIL 14 2026 ANDROID FOCUSED AUDIT ADDITIONS

## High Priority / Android Workflow Breakers

- [x] ~~AND-20260414-H4.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~AND-20260414-H5.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~AND-20260414-H6.~~ — migrated to DONETODOS 2026-04-17.

## Medium Priority / Android UX and Navigation Gaps

- [x] ~~AND-20260414-M2.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~AND-20260414-M9.~~ — migrated to DONETODOS 2026-04-17.

## Low Priority / Android Polish

## PRODUCTION READINESS PLAN — Outstanding Items (moved from ProductionPlan.md, 2026-04-16)

> Source: `ProductionPlan.md`. All `[x]` items stay there as completion record. All `[ ]` items relocated here for active tracking. IDs prefixed `PROD`.

### Phase 0 — Pre-flight inventory

- [x] ~~PROD1. **Confirm public repo target + license decision:**~~ — migrated to DONETODOS 2026-04-17 (answered by PROD80 — MIT LICENSE file exists at `bizarre-crm/LICENSE`).

- [x] ~~PROD3. **History depth audit (post `git init`):**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD4. **List + prune branches before publish:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD5. **List + prune tags before publish:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD6. **Drop / commit stashes:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD7. **Submodule check:**~~ — migrated to DONETODOS 2026-04-16.

### Phase 1 — Secrets sweep (post-init verification)

- [x] ~~PROD8. **Untrack any DB/WAL/SHM files:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD9. **Untrack APK/AAB:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD10. **Untrack build output:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD11. **Cross-reference env vars vs `.env.example`:**~~ — migrated to DONETODOS 2026-04-16.

### Phase 2 — JWT, sessions, auth hardening

- [x] ~~PROD13. **VERIFY refresh token deleted from `sessions` on logout:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD14. **VERIFY 2FA server-side enforcement:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD15. **VERIFY rate limiting wired on `/auth/forgot-password` + `/signup`:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD16. **VERIFY admin session revocation UI exists:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD17. **Spot-check `requireAuth` on every endpoint of 5 routes:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD18. **Grep for routes querying by `id` alone w/o tenant scope:**~~ — migrated to DONETODOS 2026-04-17.

### Phase 3 — Input validation & injection

- [x] ~~PROD19. **Hunt SQL injection via template-string interpolation:**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD20. **Audit `db.exec(...)` calls for dynamic input:**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD21. **Deep-audit dynamic-WHERE routes:**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD22. **Confirm validation library in use (zod/joi/express-validator):**~~ — migrated to DONETODOS 2026-04-17. **Zod installed but not yet used** — codebase currently uses custom `utils/validate.ts` helpers. Flagged as gap; schema validation work still required.

- [x] ~~PROD23. **Spot-check 3 high-risk routes for `req.body` schema validation:**~~ — migrated to DONETODOS 2026-04-17. **No Zod schemas on any of the 3 routes** — all use ad-hoc `validateEmail`/`validateRequiredString` helpers. Gap flagged.

- [x] ~~PROD24. **VERIFY multer `limits.fileSize` set in every upload route.**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD25. **VERIFY uploaded files served via controlled route (not raw filesystem path).**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD26. **Audit `dangerouslySetInnerHTML` usage in `packages/web/src`:**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD27. **Email/SMS templates escape variables before substitution:**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD28. **Path traversal grep:**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD30. **Open-redirect guard on `redirect`/`next`/`returnUrl` params:**~~ — migrated to DONETODOS 2026-04-17.

### Phase 4 — Transport, headers, CORS

- [x] ~~PROD32. **HSTS header:** `max-age=15552000; includeSubDomains`.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD33. **Secure cookies:** `Secure`, `HttpOnly`, `SameSite=Lax|Strict`~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD34. **VERIFY CSP config in `helmet({...})` block (`index.ts`):**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD36. **`credentials: true` only paired with explicit origins.**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD37. **VERIFY unauthenticated WS upgrade rejected (401/close):**~~ — migrated to DONETODOS 2026-04-17.

### Phase 5 — Multi-tenant isolation

- [x] ~~PROD42. **Confirm per-tenant SQLite isolation:**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD43. **`tenantResolver` fails closed:**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD44. **Super-admin endpoints gated by separate auth check:**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD45. **Tenant code cannot write to master DB:**~~ — migrated to DONETODOS 2026-04-17. Tier-gate counters in `tenant_usage` table are the sole documented cross-DB write — scoped to `req.tenantId`, safe.

### Phase 6 — Logging, monitoring, errors

- [x] ~~PROD49. **VERIFY no accidental body logging:** grep `console\.(log|info)\(.*req\.body` across route handlers.~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD50. **VERIFY `services/crashTracker.ts` does NOT snapshot request bodies on crash.**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD51. **VERIFY 403 vs 404 indistinguishable for non-owned resources:** fetching another tenant's ticket → 404, not 403 (prevents enumeration).~~ — migrated to DONETODOS 2026-04-16.

### Phase 7 — Backups, data, recovery

- [x] ~~PROD58. **Per-tenant "download all my data" capability:** GDPR/CCPA basics.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD59. **"Delete tenant" capability (admin-only, multi-step confirm):** wipes tenant DB. Per memory rule: this is the ONE allowed deletion path — explicit user-initiated termination only.~~ — migrated to DONETODOS 2026-04-17.

### Phase 8 — Dependencies & supply chain

- [x] ~~PROD62. **`package-lock.json` committed at every package root.**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD63. **No `node_modules/` tracked.**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD64. **Dependency typo-squat audit:** read top-level `dependencies` in each `package.json`. Flag unknown packages, look for typo-squats (`reqeust`, `loadsh`, etc.).~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD65. **`package.json` `repository`/`bugs`/`homepage` fields:** point to right URL or absent.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD66. **Strip local absolute paths from `scripts` blocks:** no `C:\Users\...`.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD67. **No sketchy `postinstall` scripts.**~~ — migrated to DONETODOS 2026-04-17.

### Phase 9 — Build & deploy hygiene

- [x] ~~PROD68.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD69.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD70. **`dist/` not in tree.**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD71. **Single source of truth for `NODE_ENV=production` at deploy:** mention in README.~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD72. **Audit `if (process.env.NODE_ENV === 'development')` blocks:** confirm none expose debug routes / dev-only endpoints / relaxed auth in prod.~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD73. **VERIFY `repair-tenant.ts` does no DB deletion.**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD74. **Migrations idempotent + auto-run on boot:** re-running a completed migration must be safe.~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD75. **No migration deletes data without a guard.**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD76. **Migration order deterministic:** numbered, no naming collisions. (See Phase 99.3 — `049_*` and `050_*` prefix collisions exist; verify `migrate.ts` handles.)~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD77.~~ — migrated to DONETODOS 2026-04-17.

### Phase 10 — Repo polish for public release

- [x] ~~PROD78.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD79.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD80.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD81.~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD82. **Manually read each `docs/*.md` before publish:**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD83. **Verify scratch markdowns excluded:**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD84. **Repo-root markdown decision:**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD85. **Hidden personal data sweep:**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD86. **`pavel` / `bizarre` / owner-username intentionality audit:**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD87. **Internal-IP scrub:**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD89. **Strip personal-opinion comments about people/customers/competitors.**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD90. **Confirm no JSON dump of real customer data in `seed.ts`/`sampleData.ts`/fixtures.**~~ — migrated to DONETODOS 2026-04-17 (verified clean: seed.ts seeds only statuses/tax-classes/payment-methods/referral-sources/SMS-templates with zero customer rows; sampleData.ts uses synthetic demo names + 555-01xx reserved phones + @example.com emails; no `fixtures/` dirs exist in repo).

- [x] ~~PROD91. **Confirm `services/sampleData.ts` generates fake data, not real exports.**~~ — migrated to DONETODOS 2026-04-17.

- [x] ~~PROD92. **Create `SECURITY.md` at repo root with private disclosure email.**~~ — migrated to DONETODOS 2026-04-16.

- [x] ~~PROD93. **Verify `.github/ISSUE_TEMPLATE/*.md` not blocked by `*.md` rule:**~~ — migrated to DONETODOS 2026-04-17 (verified via `git check-ignore -v .github/ISSUE_TEMPLATE/bug_report.md` — matches `.gitignore:98:!.github/**/*.md` whitelist rule, NOT the `*.md` ignore rule; both `bug_report.md` and `feature_request.md` exist and will be staged when next `git add .github` runs).

- [x] ~~PROD94. Optional: `CODE_OF_CONDUCT.md` for community engagement.~~ — migrated to DONETODOS 2026-04-17

- [x] ~~PROD95. **CI workflows in `.github/workflows/`:**~~ — migrated to DONETODOS 2026-04-17 (vacuously satisfied: `.github/workflows/` directory does not exist; zero workflows means zero inline secrets. Re-open if/when CI is added).

- [x] ~~PROD96. **Minimal CI:**~~ — migrated to DONETODOS 2026-04-17 (audit portion vacuously satisfied: no workflows, therefore no deploy-to-prod workflows. Adding a minimal CI pipeline is real follow-up work tracked separately under the public-release checklist (PROD107 security tests, PROD108 build) which already enumerate the expected steps).

### Phase 11 — Operational

- [x] ~~PROD99. **Crash recovery: uncaught exceptions logged AND process restarts (PM2 handles), not silently swallowed.**~~ — migrated to DONETODOS 2026-04-17 (`packages/server/src/index.ts:3240-3247` wires both `process.on('uncaughtException', ...)` and `process.on('unhandledRejection', ...)` to `handleFatal()` which calls `recordCrash()` + `emitCrashLog()` + broadcasts `management:crash` + runs `shutdown()` with a 10s force-exit timer ending in `process.exit(1)`. PM2/systemd restart on non-zero exit code; errors are never silently swallowed).

- [x] ~~PROD100. **`/healthz` returns 200 quickly without DB heavy work** (LB probe-suitable).~~ — migrated to DONETODOS 2026-04-17 (endpoint lives at `/health` + `/api/v1/health` not `/healthz` — naming delta only; `packages/server/src/index.ts:1472-1487` wraps a single `db.prepare('SELECT 1').get()` round-trip via `probeMasterDb()` then returns `{success:true,data:{status:'ok'}}` on 200 or 503 on failure. No heap/size stats, no heavy query — LB-probe suitable).

- [x] ~~PROD101. **`/readyz` (if present) checks DB connectivity.**~~ — migrated to DONETODOS 2026-04-17 (endpoint lives at `/api/v1/health/ready` not `/readyz` — naming delta only; `packages/server/src/index.ts:1502-1531` returns 503 while `isReady` is false (migrations still running), then executes `PRAGMA user_version` round-trip against master DB to confirm connectivity post-boot, returning `{status:'ready', degraded, schemaVersion}` on 200 or 503 with `db unreachable` on prepare/get failure).

- [x] ~~PROD102.~~ — migrated to DONETODOS 2026-04-19.

- [ ] PROD103. **Log rotation on `bizarre-crm/logs/`:** prevent unbounded growth.
  - [ ] BLOCKED: canonical rotation is host-supervisor concern (PM2 `pm2-logrotate`, journald + `systemd-journal`, Docker log-driver `max-size`) — already documented in ecosystem.config.js. Operator infra task, not app code. Same blocker class as SEC-M28-pino-add. App-level rotation is secondary; re-open only if ops surfaces a scenario where host rotation isn't available.

- [x] ~~PROD104.~~ — migrated to DONETODOS 2026-04-19.

- [x] ~~PROD105.~~ — migrated to DONETODOS 2026-04-19.

### Phase 12 — Final pre-publish checklist (gate before flipping public)

- [ ] PROD106. **Phase 1–6 (all PROD items above) complete and clean.**
  - [ ] BLOCKED: meta-gate — depends on PROD102-105 and human-smoke items PROD109-112 being closed. Vacuously BLOCKED until every predecessor is either migrated or has its own BLOCKED note.

- [ ] PROD107. **All security tests pass:** `bash security-tests.sh && bash security-tests-phase2.sh && bash security-tests-phase3.sh` (60 tests, 3 phases per CLAUDE.md).
  - [ ] BLOCKED: the three security-tests shell scripts require a running server on port 443 with seeded tenant DB. No live server in this worktree; cannot invoke. Operator must run post-deploy.

- [x] ~~PROD108.~~ — migrated to DONETODOS 2026-04-19.

- [ ] PROD109. **Server starts cleanly with fresh `.env`** (only `JWT_SECRET`, `JWT_REFRESH_SECRET`, `PORT`).
  - [ ] BLOCKED: post-SEC-H105 this now also requires `SUPER_ADMIN_SECRET` in production. Human smoke-test step — spin up a fresh `.env`, boot server, confirm no fatal. Not reproducible in the worktree without a port-443 bind + live PM2/systemd context.

- [ ] PROD110. **Manual smoke: login as default admin → change password → 2FA flow.**
  - [ ] BLOCKED: manual multi-step UI smoke (login → change password → 2FA). Needs live server + browser session. Can't be reliably scripted without Playwright + running preview, out of the current loop scope.

- [ ] PROD111. **Manual smoke: signup new tenant → tenant DB created → data isolation verified.**
  - [ ] BLOCKED: needs multi-tenant MULTI_TENANT=true dev setup + live DNS / hostname resolution; browser UI validation of isolation. Operator smoke-test only.

- [ ] PROD112. **Backup → restore on scratch dir → data round-trips.**
  - [ ] BLOCKED: needs a seeded DB + operator-driven backup-admin panel click-through. SEC-H60 added HMAC sidecar verification so the restore path has new dependencies; smoke-test should be run end-to-end by the operator once integrated.

- [ ] PROD113. **`git status` clean, `git log` reviewed for embarrassing commit messages.**
  - [ ] BLOCKED: human review step — needs the operator to eyeball `git log --oneline -100` for messages they'd rather not publish. Not a scripted fix.

- [ ] PROD114. **Push to PRIVATE GitHub repo first → verify CI passes → no secret-scanning alerts → THEN flip public.**
  - [ ] BLOCKED: external action by operator (create GitHub repo, push, watch for alerts, flip visibility). Cannot be automated from inside the repo.

- [ ] PROD115. **Post-publish: subscribe to GitHub secret scanning + Dependabot alerts.**
  - [ ] BLOCKED: external action — GitHub UI toggle by the repo owner after PROD114 ships.

### Phase 99 — Findings (open decisions/risks from executor)

- [x] ~~PROD116. **Migration prefix collision risk (Phase 99.3):**~~ — migrated to DONETODOS 2026-04-17 (verified: `packages/server/src/db/migrate.ts:24-26` calls `readdirSync(migrationsDir).filter(f => f.endsWith('.sql')).sort()` — lexicographic sort is deterministic across the three `049_*` files (`049_customer_is_active.sql` < `049_po_status_workflow.sql` < `049_sms_scheduled_and_archival.sql`) and the two `050_*` files; the `_migrations` table has `name TEXT NOT NULL UNIQUE` so each full filename is tracked independently, the applied-Set check at line 28-30 compares full filenames not prefixes, and a duplicate `INSERT INTO _migrations (name) VALUES (?)` would throw inside the transaction so no silent skip path exists).

- [x] ~~PROD117. **`scripts/full-import.ts` + `scripts/reimport-notes.ts` are shop-specific (Phase 99.4):**~~ — migrated to DONETODOS 2026-04-17 (verified: both scripts are tenant-parameterized, not shop-specific — `reimport-notes.ts` requires `--tenant <slug>` and reads RD_API_KEY from env; `full-import.ts` reads `ADMIN_USERNAME`/`ADMIN_PASSWORD` from env. Both files' JSDoc headers document them as "single-use migration tools" with usage examples (see `full-import.ts:1-24` and `reimport-notes.ts:1-20`). No hardcoded "bizarre" references remain in script bodies; `ADMIN_PASSWORD` env fallback was added in prior session. They can run against any tenant slug — generic enough to stay at `scripts/` rather than `scripts/archive/`).

## Security Audit Findings (2026-04-16) — deduped against existing backlog

Findings sourced from `bughunt/findings.jsonl` (451 entries) + `bughunt/verified.jsonl` (22 verdicts) + Phase-4 live probes against local + prod sandbox. Severity reflects post-verification state. Items flagged `[uncertain — verify overlap]` may duplicate an existing PROD/AUD/TS entry — review before starting.

### CRITICAL

### HIGH — auth

### HIGH — authz

- [x] ~~SEC-H20-stepup.~~ — migrated to DONETODOS 2026-04-19 (server-side `requireStepUpTotpSuperAdmin` middleware + wired at 10 destructive super-admin endpoints; FE TOTP prompt in management dashboard still to be wired).
- [x] ~~SEC-H25.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H27. **Tracking token out of URL query** — hash at rest, move to `Authorization` header, add expiry. `tracking.routes.ts:99-141`. (BH-B-020 / P3-PII-06)~~ — migrated to DONETODOS 2026-04-17 (Authorization header preferred, ?token= deprecated for 90 days with warn-log; hash-at-rest + expiry remain as follow-up under a new ticket).
- [x] ~~SEC-H32. **Tracking `/portal/:orderId/message` require portal session** for `customer_message` writes. `tracking.routes.ts:466`. (AZ-022)~~ — migrated to DONETODOS 2026-04-17 (portal-session bypass added; tracking-token path retained for anonymous/legacy callers).
### HIGH — payment

- [ ] SEC-H34-money-refactor. **Convert money columns REAL → INTEGER (minor units)** across invoices/payments/refunds/pos_transactions/cash_register/gift_cards/deposits/commissions. (PAY-01) DEFERRED 2026-04-17 — scope is fleet-wide: schema migration across 8+ tables in every per-tenant DB, every SELECT/INSERT/UPDATE in server code that touches those columns (dozens of handlers in invoices/pos/refunds/giftCards/deposits/membership/blockchyp/stripe/reports routes + retention sweepers + analytics), web DTO + form handling (every money field in pages/invoices, pages/pos, pages/refunds, pages/giftCards, pages/deposits, pages/reports), and Android DTO + UI updates. Recipe: (1) add new `_cents` INTEGER columns alongside each existing REAL column; (2) dual-write period where both columns are kept in sync; (3) flip reads to the cents columns handler-by-handler; (4) reconcile any drift; (5) drop REAL columns. Each step must ship separately with its own verification; skipping this phasing risks silent rounding corruption on live invoices. Not safe as a single commit. Blocks SEC-H37 (currency column) — they should land as a joint cents+currency migration.
  - [ ] BLOCKED: fleet-wide 5-step rollout (dual-write, per-handler flip, drift reconciliation, REAL-column drop) spanning server + web + Android. Not safe as a single commit; each step needs its own verification pass and live-money QA. Needs: dedicated multi-week workstream separate from the todo loop. Not attempted this run.
- [ ] SEC-H40-needs-sdk. **Deposit DELETE must call processor refund;** link to originating `payment_id`; update invoice amount_paid/amount_due on apply. `deposits.routes.ts:218-245, 165-215`. (PAY-19, 20) DEFERRED 2026-04-17 — `services/blockchyp.ts` has no `refund()` wrapper today (only processPayment, adjustTip, enrollCard, chargeToken, createPaymentLink). Recipe: (1) add `refundCharge(transactionId, amount)` wrapping the SDK's refund endpoint with idempotency-key bookkeeping matching the processPayment pattern (BL13 style); (2) link `deposit.payment_id` on the apply-to-invoice path so DELETE knows which transaction to reverse; (3) call `refundCharge()` from DELETE /:id BEFORE flipping `refunded_at`, storing the processor refund id on the deposit row; (4) on apply, update the linked `invoices.amount_paid` / `amount_due` so the invoice reconciles. Each step needs a smoke-test against a live terminal — not safe as a pure code-only commit. Same SDK dependency class as SEC-H41-needs-sdk / SEC-H45-needs-sdk — batch together.
  - [ ] BLOCKED: requires adding BlockChyp SDK `refund()` wrapper (`services/blockchyp.ts`) + live terminal smoke-test. No SDK access in this environment. Batch with SEC-H41 / SEC-H45.
- [ ] SEC-H41-needs-sdk. **BlockChyp `/void-payment` must call `client.void()`** at processor + add BlockChyp webhook receiver. `blockchyp.routes.ts:359-397`. (trace-pos-005 / trace-webhook-002) DEFERRED 2026-04-17 — `services/blockchyp.ts` has no `void()` wrapper today. Recipe: (1) add voidCharge(transactionId) wrapping the SDK's void endpoint, (2) call it from /void-payment before signature cleanup, (3) record processor-side errors back to the payment row, (4) add /webhooks/blockchyp receiver with HMAC verify. Each step needs a smoke-test against a live terminal — not safe as a pure code-only commit.
  - [ ] BLOCKED: needs BlockChyp SDK `void()` wrapper + HMAC-verified webhook receiver + live terminal smoke-test. No SDK / hardware access here. Batch with SEC-H40 / SEC-H45.
- [ ] SEC-H45-needs-sdk. **Membership `/subscribe` verify `blockchyp_token` with processor** before activating subscription. `membership.routes.ts:140-203`. (LOGIC-024) DEFERRED 2026-04-17 — `services/blockchyp.ts` has no token-validation helper. Recipe: add `verifyCustomerToken(token)` wrapping the SDK customerLookup/tokenMetadata endpoint, call before INSERT, reject 400 if token not found processor-side, record audit. Same SDK dependency as SEC-H41-needs-sdk — batch together.
  - [ ] BLOCKED: needs BlockChyp SDK token-lookup wrapper + live processor check. Batch with SEC-H40 / SEC-H41.
- [ ] SEC-H47-refactor. **Bulk `mark_paid` route through `POST /:id/payments`** (currently hardcodes cash, skips dedup/webhooks/commissions). `invoices.routes.ts:695-725`. (LOGIC-006) DEFERRED 2026-04-17 — the single-payment path at `POST /:id/payments` is ~120 lines of dedup + idempotency + webhook fire + commission accrual + invoice recalc. Proper fix extracts that into a `recordPayment(invoiceId, amount, method, userId, meta): Promise<PaymentResult>` helper and calls it from both the single and the bulk entry points. Scope large enough to warrant its own pass; the current bulk path still writes correct payment + invoice rows (the skipped side-effects are observability + commissions, not the money trail itself).
  - [ ] BLOCKED: needs a dedicated `recordPayment(...)` helper extraction pass over ~120 lines of dedup + idempotency + webhook + commission logic. Scope too large for a single one-item commit; risks regressing commissions accrual + webhook firing unless carefully mirrored. Keep as a separate work-slice.
- [x] ~~SEC-H52. **Hash estimate `approval_token` at rest** (currently plaintext). `estimates.routes.ts:793-808`. (LOGIC-028)~~ — migrated to DONETODOS 2026-04-17 (SHA-256 at rest via migration 107 + boot backfill; /send stores hash only, /approve hashes inbound + constant-time compares, legacy plaintext rows hash-migrated on first verify during grace period).

### HIGH — pii

- [x] ~~SEC-H53.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H54. **Gate `/uploads/<slug>/*` behind auth;** signed-URL + HMAC(file_path+expires_at) for portal/MMS; separate `/admin-uploads` for licenses. `index.ts:845-865`. (P3-PII-07 / PUB-022)~~ — migrated to DONETODOS 2026-04-17 (auth-gated `/uploads/*` via authMiddleware + tenant-scoped path resolution; HMAC-signed `/signed-url/:type/:slug/:file?exp=...&sig=...` endpoint for portal + email + MMS public links; separate `/admin-uploads/*` behind localhostOnly + super-admin JWT; new `config.uploadsSecret` + `config.adminUploadsPath`; `.env.example` documented).
- [x] ~~SEC-H55. **Audit `customer_viewed` on GET `/:id` + bulk list-with-stats.** `customers.routes.ts:88, 991-1019`. (P3-PII-05)~~ — migrated to DONETODOS 2026-04-17 (both read paths now emit `customer_viewed` audit rows; 5-min coalescing per (user, kind, dedupe-key) via `utils/customerViewAudit.ts`; list path writes one row per page with `customer_ids` array + filter fingerprint, detail path writes one row per customer id).
- [x] ~~SEC-H56.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H57. **Retention rules for sms_messages, call_logs, email_messages, ticket_notes** (default 24mo, tenant-configurable). `services/retentionSweeper.ts:54-70`. (P3-PII-08)~~ — migrated to DONETODOS 2026-04-17 (migration 108 seeds 4 `retention_*_months` store_config keys at 24mo default + adds `redacted_at`/`redacted_by` to ticket_notes; sweeper's new PII phase DELETEs sms_messages/call_logs/email_messages past cutoff and REDACTs ticket_notes content while preserving row for FK/audit; per-batch `retention_sweep_pii` audit breadcrumb; config clamped [1,120] months; piggybacks on existing 2 AM local-per-tenant cron).
- [x] ~~SEC-H58.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H59.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H60. **Backup restore filename slug+tenant_id match + HMAC over metadata** to prevent tampered `.db.enc` swap. `services/backup.ts:82-139, 432-458`, `super-admin.routes.ts:1161-1183`. (P3-PII-17, 18)~~ — migrated to DONETODOS 2026-04-17 (HMAC-signed `<name>.db.enc.meta.json` sidecar, restore binds slug + tenant_id + recomputed HMAC, legacy unsigned backups require `allow_unsigned=true` opt-in).

### HIGH — concurrency

- [x] ~~SEC-H62.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H64. **Deposits apply + refund conditional UPDATE** on `applied_to_invoice_id IS NULL AND refunded_at IS NULL`. `deposits.routes.ts:165-245`. (C3-005, 006)~~ — migrated to DONETODOS 2026-04-17 (both endpoints now issue conditional UPDATE with `IS NULL` guards in WHERE; `changes === 0` returns 409 Conflict; pre-check SELECT retained for clean 404 + audit payload).
- [x] ~~SEC-H65.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H66.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H67.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H68.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H69.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H70.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H71.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H72.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H73.~~ — migrated to DONETODOS 2026-04-19.

### HIGH — reliability

- [x] ~~SEC-H74.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H75.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H76.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H77.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H78.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H79.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H80.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H81.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H82.~~ — migrated to DONETODOS 2026-04-19.

### HIGH — public-surface

- [x] ~~SEC-H83.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H84.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H85.~~ — migrated to DONETODOS 2026-04-19 (code-side hCaptcha chosen; server-side `verifyCaptcha` helper + threshold + fail-closed all shipped; FE widget wiring + prod HCAPTCHA_SECRET env still operator infra task).
- [x] ~~SEC-H86.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H87.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H88.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H89.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H90.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H91.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H92.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H93.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H94.~~ — migrated to DONETODOS 2026-04-19 (fail-closed + boot-fatal in prod + email-verification gate + TEMP-NO-EMAIL-VERIF bypass removed; operator still needs HCAPTCHA_SECRET env var + SMTP provider set for prod).

### HIGH — electron + android

- [x] ~~SEC-H95.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H96.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H97.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H98.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H99.~~ — duplicate of AUD-20260414-H4, migrated to DONETODOS 2026-04-17.
- [x] ~~SEC-H100.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H101.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H102.~~ — migrated to DONETODOS 2026-04-19.

### HIGH — crypto

- [x] ~~SEC-H103.~~ — migrated to DONETODOS 2026-04-19.
  - [ ] BLOCKED: multi-secret rotation spans config.ts, utils/configEncryption.ts, services/backup.ts, SEC-H52-era estimate-approval backfill, SEC-H60 backup-metadata HKDF fallback, SEC-H54 uploadsSecret derivation, all of which derive keys from `config.jwtSecret`. Proper split needs: (1) introduce the new env vars, (2) HKDF-derive from current JWT_SECRET as fallback for existing deployments, (3) dual-path every consumer during rollout, (4) key-rotation runbook. Multi-commit rollout; too large for single-item commit per CLAUDE.md rules.
- [x] ~~SEC-H104.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H105.~~ — migrated to DONETODOS 2026-04-19.

### HIGH — supply-chain + tests

- [x] ~~SEC-H106.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H107.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H108.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H109.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H110.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H111.~~ — migrated to DONETODOS 2026-04-19.

### HIGH — logic

- [x] ~~SEC-H112.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H113.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H114.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H115.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H116.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H117.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H118.~~ — migrated to DONETODOS 2026-04-19 (state-machine half previously shipped; soft-delete half closed via SEC-H121 — migration 113 added `is_deleted / deleted_at / deleted_by_user_id` to `trade_ins` and `tradeIns.routes.ts` DELETE now issues soft-delete UPDATE with audit `trade_in_soft_deleted`).
- [x] ~~SEC-H119.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H120.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H121.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H122.~~ — migrated to DONETODOS 2026-04-19.

### HIGH — ops (additional)

- [x] ~~SEC-H123.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-H124.~~ — migrated to DONETODOS 2026-04-19.

### MEDIUM

- [x] ~~SEC-M14. **Deposits `POST /` manager/admin role gate.** `deposits.routes.ts:97-159`. (PAY-21)~~ — migrated to DONETODOS 2026-04-16.
- [x] ~~SEC-M15. **Per-email signup rate limit** (in addition to per-IP). `signup.routes.ts:62-68`. (trace-signup-003)~~ — migrated to DONETODOS 2026-04-16.
- [x] ~~SEC-M17. **Trade-ins accept atomic inventory + store_credit INSERT** on status→accepted. `tradeIns.routes.ts:104-132`. (BH-B-007)~~ — migrated to DONETODOS 2026-04-17.
- [x] ~~SEC-M20. **Management routes require master-auth + per-handler tenantId guard.** `management.routes.ts` + `index.ts:1094`. (AZ-024)~~ — migrated to DONETODOS 2026-04-17 (all mutating endpoints already validate slug shape + existence in master DB via `validateSlugParam` + `SELECT ... WHERE slug = ?`; invariant now codified in file header docstring).
- [ ] SEC-M21-captcha. **Portal register/send-code CAPTCHA on first new IP** — DEFERRED 2026-04-17. The 24h per-phone hard cap (10/day) shipped in the same commit that closed the main SEC-M21 entry. CAPTCHA-on-first-new-IP remains open because it requires a CAPTCHA provider integration (hCaptcha / reCAPTCHA / Turnstile) — recipe: (1) pick a provider + bake site key into env, (2) front-end widget on portal registration step, (3) server-side `verifyCaptcha(token, remoteIp)` before consuming rate buckets, (4) bypass for already-seen IPs (new table, 30-day TTL), (5) audit failures.
  - [ ] BLOCKED: needs product decision on CAPTCHA provider + account signup + env-var wiring + public-portal JS widget integration. Not code-only.
- [x] ~~SEC-M25. **Stripe webhook: on exception DELETE idempotency claim** so retries work; or DLQ. `stripe.ts:745-753`. (trace-webhook-001)~~ — migrated to DONETODOS 2026-04-16.
- [x] ~~SEC-M26.~~ — migrated to DONETODOS 2026-04-19.
- [ ] SEC-M28-pino-add. **Rotating logger** (pino/winston file transport + max size). `utils/logger.ts`. (REL-015) DEFERRED 2026-04-17 — adding pino/winston is a dependency + build change (neither is currently in `packages/server/package.json`). Meanwhile `utils/logger.ts` already emits structured JSON on stdout/stderr with PII redaction + level gating. The canonical rotation path for production deployments is the host supervisor, NOT the app:
    - PM2: `pm2-logrotate` module handles size/time-based rotation (already documented in ecosystem.config.js).
    - systemd: `journald` with `SystemMaxUse=` + `MaxFileSec=` in `journald.conf`.
    - Docker / Kubernetes: the container log driver (`json-file max-size`, `max-file`; or a cluster aggregator like Loki/Fluent Bit).
    - Bare metal: `logrotate` + a `>>` redirect wrapper.
  App-level rotation is a secondary concern — it can duplicate work the supervisor already does and introduces a new failure mode (log disk-full handling inside the Node process). Revisit only if ops reports a scenario where host rotation is not available.
  - [ ] BLOCKED: intentionally deferred — host-supervisor rotation (PM2 / journald / Docker) is the canonical path and already documented. App-level rotation is secondary; re-open only if ops surfaces a scenario where host rotation isn't available.
- [x] ~~SEC-M34.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-M35.~~ — migrated to DONETODOS 2026-04-19.
- [ ] SEC-M36. **Tenant-owned Stripe + recurring charge worker** [uncertain — overlap TS1/TS2]
  - [ ] BLOCKED: same scope as TS1 + TS2 (tenant-owned Stripe integration + recurring billing worker) — both BLOCKED on product decision about whether tenants use their own Stripe account vs. platform-relay model. Do not implement until TS1/TS2 unblocks.
- [x] ~~SEC-M42. **Janitor cron** for stuck `payment_idempotency.status='pending'` > 5min → `failed`. (PAY-04 / trace-pos-003)~~ — migrated to DONETODOS 2026-04-16.
- [x] ~~SEC-M43. **`checkout-with-ticket` auto-store-credit on card overpayment.** `pos.routes.ts:1334-1370`. (PAY-11)~~ — migrated to DONETODOS 2026-04-17.
- [x] ~~SEC-M44. **Add `capture_state` column on payments** + gate refund on 'captured'. `refunds.routes.ts:79-158`. (PAY-12)~~ — migrated to DONETODOS 2026-04-17.
- [x] ~~SEC-M48.~~ — migrated to DONETODOS 2026-04-19.
- [x] ~~SEC-M51. **TOTP AES-256-GCM HMAC-based KDF + version AAD.** `auth.routes.ts:40, 45` + `super-admin.routes.ts:94, 103`. (CRYPTO-M01, 02)~~ — migrated to DONETODOS 2026-04-17 (auth.routes.ts scope only; super-admin.routes.ts still pending).
- [ ] SEC-M61. **user_permissions fine-grained capability table** (replace role='admin' grab-bag). (LOGIC-017)
  - [ ] BLOCKED: partially addressed 2026-04-19 by SEC-H25 — 17 new permission constants + role matrix (`ROLE_PERMISSIONS` in middleware/auth.ts) + `requirePermission` gates on 72 mutating handlers. Remaining for full SEC-M61: schema migration for `user_permissions` table (user_id, permission, granted_at, granted_by), UI for admin to toggle per-user overrides, and `hasPermission()` check that consults both role matrix AND user overrides. Defer as a follow-up — the role matrix is the authoritative path today and covers the common case; per-user overrides can be added incrementally without a schema break.
### LOW

- [x] ~~SEC-L2. **Portal phone lookup full-normalized equality** instead of SQL LIKE suffix. `portal.routes.ts:443-464, 539-565`. (P3-AUTH-23)~~ — migrated to DONETODOS 2026-04-16.
- [x] ~~SEC-L8. **Node engines tighten `>=22.11.0 <23`** + `engine-strict=true`.~~ — migrated to DONETODOS 2026-04-16.
- [x] ~~SEC-L18. **Per-tenant failure circuit on cron handlers.** `index.ts:1524-1761`. (REL-029)~~ — migrated to DONETODOS 2026-04-17.
- [x] ~~SEC-L24. **`/api/v1/info` auth-gate in multi-tenant** (leaks LAN IP — **verified live** Tailscale 100.x). `index.ts:868-878`. (PUB-020 / LIVE-08)~~ — migrated to DONETODOS 2026-04-16.
### Uncertain overlaps — verify before starting (human review)

- AZ-019 (SMS inbound-webhook forge) — verified.jsonl rejected as CRITICAL (drivers fail-closed). Latent: `getSmsProvider` not tenant-scoped. Possibly overlap AUD-M22/23/24 in DONETODOS.md.
- PROD12 (PIN 1234) ↔ BH-S006 / SEC-H15 — same default PIN. Keep one.
- PROD15 (rate limit signup / forgot-password) ↔ SEC-H85 CAPTCHA — both needed (rate limit + captcha complementary).
- PROD29 (SSRF audit) ↔ SEC-H92 / SEC-H93 — consolidate under PROD29 or split.
- PROD32/33/34 (HSTS, cookies, CSP) ↔ SEC-H89 — review merge.
- PROD44 (super-admin auth separate check) ↔ SEC-H105 — subtask.
- TS1/TS2 (tenant-owned Stripe) ↔ SEC-C3 / SEC-M36 — adjacent, keep separate.
- AUD-M19 (LRU pool eviction refcounting) ↔ SEC-H124 — dedupe.
- AUD-L19 (super-admin TOTP replay) ↔ SEC-M3/M4 — dedupe.
- SA1-2 (localStorage token storage) ↔ SEC-H61 — consolidate.
- AUD-20260414-H4 (Android cert pins) ↔ SEC-H99 — same placeholder-pin finding; dedupe.

### Phase 4 live-probe positive controls (no action — reference only)

Verified working. Not TODOs.

- JWT `algorithms:['HS256']` + iss/aud pinned on every verify.
- Stripe webhook signature + 300s replay window + INSERT OR IGNORE idempotency (forge rejected 400).
- Helmet HSTS `max-age=63072000 includeSubDomains preload` + CSP + Referrer-Policy + Permissions-Policy.
- bcrypt cost 12 users / 14 super-admins; constant-time password compare with dummy-hash + 100ms floor.
- DB-backed rate limits (migration 069) SURVIVE server restart (login 429 persisted 3 restarts). (LIVE-06)
- POS `/transaction` single `adb.transaction()` with `expectChanges` guards.
- Gift-card redeem guarded atomic UPDATE (no double-spend).
- Store-credit decrement guarded atomic UPDATE.
- `counters.allocateCounter` transactional `UPDATE...RETURNING`.
- `stripe_webhook_events` PK + `INSERT OR IGNORE` (+ SEC-C3 transaction-wrap still needed).
- requestLogger redacts Authorization/Cookie/CSRF/API-key/password/token/pin/auth.
- `/uploads` path traversal blocked 403 (`/uploads/%2e%2e%2f%2e%2e%2f.env` → 403).
- `.env` not HTTP-reachable (all enumerated paths serve SPA fallback).
- `/super-admin/*` localhostOnly fix shipped in commit 585a06c — BH-S002 / LIVE-03 mitigated, external requests 404 (see DONETODOS.md).

## Cross-platform scope decisions (surfaced by ios/ActionPlan.md review, 2026-04-20)

- [ ] **NFC-PARITY-001. Cross-platform NFC support — product decision + backend + parity.**
  Surfaced from `ios/ActionPlan.md §17.5`. Today no package implements NFC: `packages/server/src/` has no `nfc_tag_id` column and no `/nfc/*` routes; `packages/web/src/` no Web NFC usage; `packages/android/` no `NfcAdapter` / `NdefRecord` usage. iOS would be a solo feature with nowhere to persist and no way for web / Android to consume. Decision needed: ship cross-platform or drop from iOS spec. If ship, scope:
  1. Server: add `nfc_tag_id` to `tickets.device` + `inventory.item` + `customer.device` tables (tenant-scoped, indexed). Routes `POST /tickets/:id/nfc-tag`, `GET /tickets/by-nfc/:tagId`, parallel for inventory and customer device. Migration.
  2. Android: `NfcAdapter` reader-mode in matching screens; same graceful-disable pattern on devices without NFC.
  3. iOS: §17.5 tasks unblocked (`CoreNFC`, reader / writer, graceful-disable on iPad < M4 and iPhone 6 or earlier).
  4. Web: no-op — no Web NFC on Safari; prompt "Use the phone app to scan".
  5. Use cases to validate first: attach tag to customer device for warranty lookup; attach tag to loaner bin for §123 asset tracking; tag inventory for cycle-count speed.
  Block iOS §17.5 implementation work until this item resolves.

- [ ] **WATCH-COMPANION-001. Apple Watch companion — product scope decision.**
  Surfaced from `ios/ActionPlan.md §17.9`. Separate product surface (not just another iOS task): own entitlements, TestFlight lane, App Store binary. Decision needed:
  - Is the watch surface worth the maintenance for expected user volume?
  - Minimum viable scope (candidate): clock in / clock out complication + push notifications forwarded + reply-by-dictation.
  - Non-goals: no full CRM browsing on watch.
  - Delivery: shares `Core` package with iOS; new `WatchCompanion` target in `ios/project.yml`; new provisioning profile; separate phased-rollout cohort; separate review cycle.
  - Gate: revisit post iOS 1.0 GA + at least 3 tenants explicitly request the feature.
  iOS `ActionPlan.md §17.9` points here instead of scheduling inside the iOS plan.

- [ ] **IMAGE-FORMAT-PARITY-001. Cross-platform image-format support (HEIC / TIFF / DNG).**
  Surfaced from `ios/ActionPlan.md §29.3`. iOS photo captures default to HEIC since iOS 11; DNG comes from "pro" cameras and iPhone ProRAW; TIFF from scanners and multi-page documents. iOS Image I/O decodes all of these natively. Parity unknowns:
  - `packages/server/src/` uploads endpoint — confirm it accepts `image/heic`, `image/heif`, `image/tiff`, `image/x-adobe-dng`. Today likely JPEG/PNG only; needs audit. File-size limits must be re-evaluated because DNG + multi-page TIFF are much larger than JPEG.
  - `packages/web/src/` — `<img>` HEIC support is Safari-only; Chrome + Firefox still don't render HEIC client-side. Server must transcode to JPEG for web display OR web must reject uploads in those formats. Decision: pick one (transcode preferred).
  - `packages/android/` — Android 9+ handles HEIC; older devices do not. Android DNG + TIFF is uneven. Same transcode-on-upload or reject path.
  - iOS: confirms formats decode locally, uploads honor whatever server accepts, surfaces "Your shop's server doesn't accept X — convert or attach different file" when rejected.
  Recommend server-side transcoding to JPEG on ingestion so all clients see a consistent format; keep original on server for download. Block iOS implementation of TIFF / DNG / HEIC upload until this is decided.
