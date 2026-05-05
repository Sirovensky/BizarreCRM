package com.bizarreelectronics.crm.data.repository

import com.bizarreelectronics.crm.service.ScaleState
import com.bizarreelectronics.crm.service.WeightReading
import com.bizarreelectronics.crm.service.WeightScaleService
import com.bizarreelectronics.crm.service.WeightUnit
import com.bizarreelectronics.crm.util.PrinterManager
import kotlinx.coroutines.flow.StateFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §17.7 / §17.12 — Unified hardware state repository.
 *
 * Aggregates state from hardware singletons ([WeightScaleService],
 * [PrinterManager]) so ViewModels have a single injection point for hardware
 * state rather than depending on individual services directly.
 *
 * This repository does NOT own IO threads — it delegates all async work to
 * the underlying services.
 */
@Singleton
class HardwareRepository @Inject constructor(
    private val weightScaleService: WeightScaleService,
    private val printerManager: PrinterManager,
) {

    // ─── Weight scale ─────────────────────────────────────────────────────────

    /** Reactive weight-scale state; UI observes this via collectAsState(). */
    val scaleState: StateFlow<ScaleState> = weightScaleService.scaleState

    /** Triggers a single on-demand weight read from the paired scale. */
    suspend fun readWeight(): Result<WeightReading> = weightScaleService.readWeight()

    fun saveScalePairing(mac: String, name: String, unit: WeightUnit) =
        weightScaleService.savePairing(mac, name, unit)

    fun clearScalePairing() = weightScaleService.clearPairing()
    fun isScalePaired(): Boolean = weightScaleService.isPaired()
    fun pairedScaleName(): String? = weightScaleService.pairedName()
    fun pairedScaleUnit(): WeightUnit = weightScaleService.pairedUnit()

    // ─── Printer status ───────────────────────────────────────────────────────

    /** Reactive printer status map (address → PrinterStatus) from [PrinterManager]. */
    val printerStatus: StateFlow<Map<String, PrinterManager.PrinterStatus>> =
        printerManager.printerStatus

    /**
     * Trigger reconnect probes for all paired printers.
     * Call from Activity onResume (§17.12 auto-reconnect).
     */
    suspend fun reconnectPrinters() = printerManager.onActivityResume()
}
