package com.bizarreelectronics.crm.util

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §17.12 — Bluetooth hardware reconnect manager.
 *
 * Provides:
 * - [reconnectAll] — attempt reconnection for all roles in [PrinterManager]
 *   on Activity resume (delegates to [PrinterManager.onActivityResume]).
 * - [reconnectWithBackoff] — exponential back-off loop for a single role
 *   after a detected failure.  Stops when the socket becomes reachable.
 * - [hardwareResilience] — reactive [StateFlow] that surfaces the last
 *   skip message shown to the user (e.g. "Print skipped — reprint from
 *   Sales History") so UI components can render a transient banner.
 *
 * ### Non-blocking contract
 * All IO runs on [Dispatchers.IO].  The UI is never blocked by a hardware
 * failure — callers receive a [ResilenceEvent] and degrade gracefully.
 *
 * ### Backoff schedule (capped at 30 s)
 * | Attempt | Delay   |
 * |---------|---------|
 * | 1       | 2 s     |
 * | 2       | 4 s     |
 * | 3       | 8 s     |
 * | 4       | 16 s    |
 * | 5+      | 30 s    |
 */
@Singleton
class BluetoothReconnectManager @Inject constructor(
    private val printerManager: PrinterManager,
) {
    private val _resilience = MutableStateFlow<ResilienceEvent?>(null)
    val hardwareResilience: StateFlow<ResilienceEvent?> = _resilience.asStateFlow()

    private val reconnectJobs = mutableMapOf<PrinterManager.PrinterRole, Job>()

    /**
     * Called on Activity resume — probes all paired printers and updates
     * [PrinterManager.printerStatus] StateFlows.  Non-blocking fire-and-forget
     * on the provided [scope].
     */
    fun reconnectAll(scope: CoroutineScope) {
        scope.launch(Dispatchers.IO) {
            printerManager.onActivityResume()
        }
    }

    /**
     * Start an exponential back-off reconnect loop for [role].
     *
     * The loop runs until the printer is reachable or [stopReconnect] is called.
     * Each failed attempt updates [hardwareResilience] so the UI can show a banner.
     *
     * @param role   Printer role to reconnect.
     * @param scope  CoroutineScope to launch on (typically a ViewModel scope).
     */
    fun reconnectWithBackoff(role: PrinterManager.PrinterRole, scope: CoroutineScope) {
        reconnectJobs[role]?.cancel()
        reconnectJobs[role] = scope.launch(Dispatchers.IO) {
            var attempt = 0
            while (true) {
                attempt++
                val delayMs = (BASE_DELAY_MS shl (attempt - 1)).coerceAtMost(MAX_DELAY_MS)
                Timber.d("BluetoothReconnect: attempt $attempt for ${role.label}, next in ${delayMs}ms")
                delay(delayMs)
                printerManager.onActivityResume()
                val status = printerManager.printerStatus.value[printerManager.getPairedAddress(role)]
                if (status == PrinterManager.PrinterStatus.Ready) {
                    Timber.i("BluetoothReconnect: ${role.label} reconnected after $attempt attempt(s)")
                    _resilience.update { null }
                    break
                }
                emitSkipEvent(role)
            }
        }
    }

    /**
     * Stop the reconnect loop for [role].
     */
    fun stopReconnect(role: PrinterManager.PrinterRole) {
        reconnectJobs.remove(role)?.cancel()
    }

    /**
     * Emit a resilience skip event for [role].  Call this from printing
     * code when a hardware failure is detected so the UI can display the
     * "Print skipped — reprint from Sales History" banner.
     */
    fun emitSkipEvent(role: PrinterManager.PrinterRole) {
        val msg = when (role) {
            PrinterManager.PrinterRole.Receipt ->
                "Print skipped — reprint from Sales History when printer reconnects"
            PrinterManager.PrinterRole.Label ->
                "Label skipped — reprint from Inventory when printer reconnects"
            PrinterManager.PrinterRole.Invoice ->
                "Invoice print skipped — reprint from Invoice when printer reconnects"
        }
        _resilience.value = ResilienceEvent(role = role, message = msg)
        Timber.w("BluetoothReconnect: $msg")
    }

    fun clearResilienceEvent() {
        _resilience.value = null
    }

    companion object {
        private const val BASE_DELAY_MS = 2_000L
        private const val MAX_DELAY_MS = 30_000L
    }
}

/**
 * A transient skip notification surfaced to the UI when a hardware failure
 * prevents a print/kick operation.
 *
 * Display as a dismissible [Snackbar] or inline banner — never block the user flow.
 *
 * @param role    Which printer role failed.
 * @param message Human-readable skip description for the operator.
 */
data class ResilienceEvent(
    val role: PrinterManager.PrinterRole,
    val message: String,
)
