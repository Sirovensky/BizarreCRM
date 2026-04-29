package com.bizarreelectronics.crm.util

/**
 * §74 — Privacy-first analytics event catalog.
 *
 * All events target the tenant's own server (§32 sovereignty principle).
 * No GAID / ADID / Firebase Analytics / Google Analytics / Mixpanel / Amplitude.
 *
 * Schema per event:
 * ```json
 * {
 *   "event": "<name>",
 *   "ts": "2026-04-19T14:03:22.123Z",
 *   "app_version": "1.2.3 (24041901)",
 *   "android_version": "16",
 *   "device_model": "Pixel 8",
 *   "session_id": "uuid",
 *   "user_id": "hashed_8",
 *   "tenant_id": "hashed_8",
 *   "props": { ... }
 * }
 * ```
 *
 * PII contract:
 * - [name] must NEVER contain tokens, passwords, PINs, full names, phone numbers, or IMEIs.
 * - [props] values are passed through [LogRedactor.redact] by [TelemetryClient] before
 *   serialisation. Call-sites must not embed raw PII in prop values.
 *
 * Transmission is deferred until the server-side `/telemetry/events` endpoint lands
 * (see [TelemetryClient] NOTE-defer).  Until then events are only written to the
 * [Breadcrumbs] ring buffer as structured log entries (category "telemetry").
 */
sealed class AnalyticsEvent(
    /** Wire name used in the JSON payload — stable, never rename. */
    val name: String,
) {

    // ─── App lifecycle ────────────────────────────────────────────────────────

    /** Cold or warm launch. */
    data object AppLaunch : AnalyticsEvent("app.launch")

    /** Process transitions to foreground from background. */
    data object AppForeground : AnalyticsEvent("app.foreground")

    /** Process transitions to background. */
    data object AppBackground : AnalyticsEvent("app.background")

    // ─── Auth ─────────────────────────────────────────────────────────────────

    data object AuthLoginSuccess : AnalyticsEvent("auth.login.success")

    data object AuthLoginFailure : AnalyticsEvent("auth.login.failure")

    data object AuthLogout : AnalyticsEvent("auth.logout")

    data object AuthBiometricSuccess : AnalyticsEvent("auth.biometric.success")

    // ─── Navigation ───────────────────────────────────────────────────────────

    /**
     * @property screen  Route name (e.g. "dashboard", "ticket_detail").
     * @property durationMs  Time the screen was visible, in milliseconds.
     */
    data class ScreenView(val screen: String, val durationMs: Long) :
        AnalyticsEvent("screen.view")

    // ─── User actions ─────────────────────────────────────────────────────────

    /**
     * Tap on a named UI element.
     *
     * @property screen      Route name of the hosting screen.
     * @property action      Logical action label (e.g. "save", "open_menu", "retry").
     * @property entityKind  Optional domain entity kind (e.g. "ticket", "invoice"), or null.
     */
    data class ActionTap(
        val screen: String,
        val action: String,
        val entityKind: String? = null,
    ) : AnalyticsEvent("action.tap")

    // ─── Mutations ────────────────────────────────────────────────────────────

    /** A write operation (create, update, delete) started. */
    data class MutationStart(val entityKind: String) : AnalyticsEvent("mutation.start")

    /** Write operation completed successfully. */
    data class MutationSuccess(val entityKind: String) : AnalyticsEvent("mutation.success")

    /** Write operation failed. */
    data class MutationFail(val entityKind: String) : AnalyticsEvent("mutation.fail")

    // ─── Sync ─────────────────────────────────────────────────────────────────

    data object SyncCycleStart : AnalyticsEvent("sync.cycle.start")

    data object SyncCycleComplete : AnalyticsEvent("sync.cycle.complete")

    data object SyncFailure : AnalyticsEvent("sync.failure")

    // ─── POS ─────────────────────────────────────────────────────────────────

    data object PosSaleStart : AnalyticsEvent("pos.sale.start")

    data object PosSaleComplete : AnalyticsEvent("pos.sale.complete")

    data object PosSaleFail : AnalyticsEvent("pos.sale.fail")

    data object PosReturnComplete : AnalyticsEvent("pos.return.complete")

    data object PosShiftOpen : AnalyticsEvent("pos.shift.open")

    data object PosShiftClose : AnalyticsEvent("pos.shift.close")

    // ─── Hardware ─────────────────────────────────────────────────────────────

    /**
     * @property success  True if the scan decoded a valid barcode.
     */
    data class BarcodeScan(val success: Boolean) : AnalyticsEvent("barcode.scan")

    /**
     * @property success  True if the print job was accepted by the printer.
     */
    data class PrinterPrint(val success: Boolean) : AnalyticsEvent("printer.print")

    /**
     * @property success  True if the payment terminal accepted the charge.
     */
    data class TerminalCharge(val success: Boolean) : AnalyticsEvent("terminal.charge")

    // ─── Comms ────────────────────────────────────────────────────────────────

    data object SmsSend : AnalyticsEvent("sms.send")

    // ─── Push notifications ───────────────────────────────────────────────────

    data object PushReceived : AnalyticsEvent("push.received")

    data object PushTapped : AnalyticsEvent("push.tapped")

    // ─── Widgets / Live Updates / Deep links ──────────────────────────────────

    data object WidgetView : AnalyticsEvent("widget.view")

    data object LiveUpdateStart : AnalyticsEvent("live_update.start")

    data object LiveUpdateEnd : AnalyticsEvent("live_update.end")

    data object DeepLinkOpened : AnalyticsEvent("deeplink.opened")

    // ─── Feature discovery ────────────────────────────────────────────────────

    /**
     * First time the user accesses a named feature in this installation.
     *
     * @property featureName  Stable snake_case feature identifier (e.g. "barcode_scanner").
     *   Must not contain PII.
     */
    data class FeatureFirstUse(val featureName: String) : AnalyticsEvent("feature.first_use")
}
