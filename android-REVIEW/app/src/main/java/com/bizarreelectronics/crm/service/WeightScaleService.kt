package com.bizarreelectronics.crm.service

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.SharedPreferences
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import timber.log.Timber
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §17.7 — Bluetooth serial-over-SPP weight scale service.
 *
 * Supports scales that output ASCII weight strings over Bluetooth SPP
 * (Brecknell, Dymo M10/M25, Fairbanks, A&D models).
 *
 * Protocol: scales typically stream or respond to an on-demand read request
 * with a line like:
 *   "  0.84 lb\r\n"   or   "ST,GS,+   0.84kg\r\n"   (Brecknell format)
 *
 * [readWeight] opens the socket, reads one weight line, parses it, and
 * closes the socket.  All IO runs on [Dispatchers.IO].
 *
 * Pairing:
 *   - [savePairing] stores the MAC + unit preference in SharedPreferences.
 *   - [clearPairing] removes the pairing.
 *   - [isPaired] checks whether a MAC is stored.
 *
 * State:
 *   [scaleState] emits the most recently read weight (or an error/idle state)
 *   so POS / shipping / trade-in screens can observe reactively.
 *
 * mock-mode wiring: [readWeight] returns a simulated value when Bluetooth is
 * unavailable (emulator / test device). Needs physical-device test.
 */
@Singleton
class WeightScaleService @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private val prefs: SharedPreferences =
        context.getSharedPreferences("weight_scale_prefs", Context.MODE_PRIVATE)

    // ─── Reactive state ───────────────────────────────────────────────────────

    private val _scaleState = MutableStateFlow<ScaleState>(ScaleState.Idle)
    val scaleState: StateFlow<ScaleState> = _scaleState.asStateFlow()

    // ─── Pairing ──────────────────────────────────────────────────────────────

    fun savePairing(macAddress: String, displayName: String, unit: WeightUnit) {
        prefs.edit()
            .putString(PREF_MAC, macAddress)
            .putString(PREF_NAME, displayName)
            .putString(PREF_UNIT, unit.name)
            .apply()
        _scaleState.value = ScaleState.Idle
        Timber.d("WeightScaleService: paired $displayName ($macAddress) unit=${unit.name}")
    }

    fun clearPairing() {
        prefs.edit().remove(PREF_MAC).remove(PREF_NAME).remove(PREF_UNIT).apply()
        _scaleState.value = ScaleState.Idle
    }

    fun isPaired(): Boolean = prefs.getString(PREF_MAC, null) != null

    fun pairedMac(): String? = prefs.getString(PREF_MAC, null)
    fun pairedName(): String? = prefs.getString(PREF_NAME, null)
    fun pairedUnit(): WeightUnit =
        WeightUnit.entries.firstOrNull { it.name == prefs.getString(PREF_UNIT, null) } ?: WeightUnit.LB

    // ─── Weight read ──────────────────────────────────────────────────────────

    /**
     * Opens the Bluetooth socket, reads one weight line, parses it, and closes
     * the socket.  Times out after 3 seconds.
     *
     * Emits [ScaleState.Reading] while in flight, then [ScaleState.Ready] on
     * success or [ScaleState.Error] on failure.
     */
    @SuppressLint("MissingPermission")
    suspend fun readWeight(): Result<WeightReading> = withContext(Dispatchers.IO) {
        val mac = pairedMac()
        if (mac == null) {
            _scaleState.value = ScaleState.Error("No scale paired")
            return@withContext Result.failure(IllegalStateException("No scale paired"))
        }

        // Mock mode: no BT adapter (emulator)
        val btManager = context.getSystemService(BluetoothManager::class.java)
        val adapter = btManager?.adapter
        if (adapter == null || !adapter.isEnabled) {
            val mock = WeightReading(value = 0.84f, unit = pairedUnit(), raw = "  0.84 lb (mock)")
            _scaleState.value = ScaleState.Ready(mock)
            Timber.w("WeightScaleService: Bluetooth unavailable — returning mock reading")
            return@withContext Result.success(mock)
        }

        _scaleState.value = ScaleState.Reading

        val result = withTimeoutOrNull(3_000L) {
            runCatching {
                val device = adapter.getRemoteDevice(mac)
                val socket: BluetoothSocket = device.createRfcommSocketToServiceRecord(SPP_UUID)
                socket.use { s ->
                    s.connect()
                    val reader = BufferedReader(InputStreamReader(s.inputStream, Charsets.US_ASCII))
                    val line = reader.readLine() ?: ""
                    parseWeightLine(line, pairedUnit())
                }
            }
        } ?: Result.failure<WeightReading>(Exception("Scale read timed out (3 s)"))

        _scaleState.value = result.fold(
            onSuccess = { ScaleState.Ready(it) },
            onFailure = { ScaleState.Error(it.message ?: "Unknown error") },
        )
        result
    }

    // ─── Parsing ──────────────────────────────────────────────────────────────

    /**
     * Parses common ASCII weight formats:
     *   "  0.84 lb\r\n"          (simple)
     *   "ST,GS,+   0.84kg"       (Brecknell/Fairbanks SCP)
     *   "   384 g"               (grams)
     */
    internal fun parseWeightLine(line: String, defaultUnit: WeightUnit): WeightReading {
        val trimmed = line.trim()
        // Extract the numeric part and optional unit suffix
        val regex = Regex("""([0-9]+\.?[0-9]*)\s*(lb|kg|g|oz)?""", RegexOption.IGNORE_CASE)
        val match = regex.find(trimmed)
            ?: return WeightReading(value = 0f, unit = defaultUnit, raw = trimmed, unstable = true)

        val value = match.groupValues[1].toFloatOrNull() ?: 0f
        val unitStr = match.groupValues[2].lowercase()
        val unit = when (unitStr) {
            "kg" -> WeightUnit.KG
            "g"  -> WeightUnit.G
            "oz" -> WeightUnit.OZ
            "lb" -> WeightUnit.LB
            else -> defaultUnit
        }
        // Brecknell "ST" prefix = stable; "US" = unstable
        val unstable = trimmed.contains("US,", ignoreCase = true)
        return WeightReading(value = value, unit = unit, raw = trimmed, unstable = unstable)
    }

    // ─── Constants ────────────────────────────────────────────────────────────

    private companion object {
        const val PREF_MAC  = "scale_mac"
        const val PREF_NAME = "scale_name"
        const val PREF_UNIT = "scale_unit"
    }
}

// ── Domain models ─────────────────────────────────────────────────────────────

enum class WeightUnit { LB, KG, G, OZ }

data class WeightReading(
    val value: Float,
    val unit: WeightUnit,
    val raw: String,
    val unstable: Boolean = false,
) {
    /** Human-readable label e.g. "0.84 lb" */
    fun label(): String = "${"%.2f".format(value)} ${unit.name.lowercase()}"
}

sealed class ScaleState {
    data object Idle : ScaleState()
    data object Reading : ScaleState()
    data class Ready(val reading: WeightReading) : ScaleState()
    data class Error(val message: String) : ScaleState()
}
