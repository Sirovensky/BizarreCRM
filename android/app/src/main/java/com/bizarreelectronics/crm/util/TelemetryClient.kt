package com.bizarreelectronics.crm.util

import android.content.Context
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import dagger.hilt.android.qualifiers.ApplicationContext
import timber.log.Timber
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §74 — Privacy-first analytics stub.
 *
 * Design:
 *   - Sovereignty: events target the **tenant's own server** only (§32.2).
 *     No third-party SDKs, no GAID, no ADID, no Firebase Analytics.
 *   - PII safety: all prop values are passed through [LogRedactor.redact] before
 *     any write. Tokens, passwords, PINs, full names, phone numbers, and IMEIs
 *     must never appear in event names or props.
 *   - Opt-out: when [AppPreferences.telemetryEnabled] is `false` the client drops
 *     all events immediately (local breadcrumb write is also skipped).
 *
 * ## Current state — STUB
 *
 * The server-side `/telemetry/events` endpoint has not yet been implemented.
 * Until it lands, [track] writes a structured entry to the [Breadcrumbs] ring
 * buffer (category "telemetry") and returns immediately.  The Room offline buffer
 * and batch-flush logic are stubs with NOTE-defer markers below.
 *
 * Server endpoint required: `POST /api/v1/telemetry/events` accepting a JSON
 * array of event objects matching the §74.1 schema.
 *
 * <!-- NOTE-defer: batch flush to POST /api/v1/telemetry/events — server endpoint
 *      not yet implemented; see §32.2 and §74 in ActionPlan.md -->
 * <!-- NOTE-defer: offline Room buffer for events — depends on the flush path above -->
 * <!-- NOTE-defer: session_id generation tied to auth lifecycle — wired stub below -->
 */
@Singleton
class TelemetryClient @Inject constructor(
    @ApplicationContext private val context: Context,
    private val appPreferences: AppPreferences,
    private val breadcrumbs: Breadcrumbs,
) {

    /**
     * Per-process session ID.  Regenerated on each cold start, not persisted.
     * Safe to expose: it is a random UUID with no user-identifying content.
     */
    private val sessionId: String = UUID.randomUUID().toString()

    /**
     * Records an analytics event.
     *
     * Current behaviour (stub): writes a structured breadcrumb entry and returns.
     * When the server endpoint is available the event will also be enqueued in
     * Room and flushed on the next foreground + connectivity window.
     *
     * @param event  The event to record.  Must not contain PII.
     */
    fun track(event: AnalyticsEvent) {
        if (!appPreferences.telemetryEnabled) return

        // Build a compact breadcrumb string safe for log/crash-report output.
        val propSummary = buildPropSummary(event)
        val redacted = LogRedactor.redact(
            "event=${event.name} session=$sessionId$propSummary",
        )
        breadcrumbs.log(CAT_TELEMETRY, redacted)

        Timber.d("[Telemetry] %s", redacted)

        // NOTE-defer: enqueue event in Room offline buffer and flush to
        // POST /api/v1/telemetry/events when server endpoint exists (§32.2).
    }

    // ─── Private helpers ──────────────────────────────────────────────────────

    /**
     * Returns a compact, redacted prop summary string for breadcrumb logging.
     * Only includes meaningful discriminators — no PII fields.
     */
    private fun buildPropSummary(event: AnalyticsEvent): String = when (event) {
        is AnalyticsEvent.ScreenView ->
            " screen=${LogRedactor.redact(event.screen)} duration_ms=${event.durationMs}"
        is AnalyticsEvent.ActionTap ->
            " screen=${LogRedactor.redact(event.screen)} action=${LogRedactor.redact(event.action)}" +
                (event.entityKind?.let { " kind=${LogRedactor.redact(it)}" } ?: "")
        is AnalyticsEvent.MutationStart ->
            " kind=${LogRedactor.redact(event.entityKind)}"
        is AnalyticsEvent.MutationSuccess ->
            " kind=${LogRedactor.redact(event.entityKind)}"
        is AnalyticsEvent.MutationFail ->
            " kind=${LogRedactor.redact(event.entityKind)}"
        is AnalyticsEvent.BarcodeScan ->
            " success=${event.success}"
        is AnalyticsEvent.PrinterPrint ->
            " success=${event.success}"
        is AnalyticsEvent.TerminalCharge ->
            " success=${event.success}"
        is AnalyticsEvent.FeatureFirstUse ->
            " feature=${LogRedactor.redact(event.featureName)}"
        else -> ""
    }

    companion object {
        private const val CAT_TELEMETRY = "telemetry"
    }
}
