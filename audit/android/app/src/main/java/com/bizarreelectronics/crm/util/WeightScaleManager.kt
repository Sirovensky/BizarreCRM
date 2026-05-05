package com.bizarreelectronics.crm.util

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
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
 * §17.7 — Serial-over-Bluetooth weight scale driver.
 *
 * Communicates with common postal / trade-in scales (Brecknell, Dymo USB/BT)
 * that expose a virtual serial port (SPP) and stream weight readings as ASCII
 * lines, e.g. `"  0.84 lb\r\n"`.
 *
 * ### Supported protocols
 * - **Brecknell SBI/Simple** — responds to a single CR with a fixed-field
 *   weight string (`"S ST,GS,  0.840 lb\r\n"`).  [requestWeight] sends 0x0D
 *   and reads until newline.
 * - **Dymo S100 / Postal** — polls on open; first line is weight.
 *
 * ### Usage
 * 1. Call [discoverScales] to list bonded BT devices matching scale heuristics.
 * 2. Call [pairScale] to persist the chosen device address.
 * 3. Call [requestWeight] from a ViewModel to get the current reading.
 *
 * ### Connection lifecycle
 * [requestWeight] opens a fresh RFCOMM socket, reads one response line, and
 * closes immediately — no persistent connection needed for on-demand reads.
 */
@Singleton
class WeightScaleManager @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    private val prefs = context.getSharedPreferences("scale_prefs", Context.MODE_PRIVATE)

    private val _status = MutableStateFlow<ScaleStatus>(ScaleStatus.Idle)
    val status: StateFlow<ScaleStatus> = _status.asStateFlow()

    // ─── Pairing ──────────────────────────────────────────────────────────────

    fun pairScale(address: String, name: String) {
        prefs.edit()
            .putString("scale_address", address)
            .putString("scale_name", name)
            .apply()
        Timber.d("WeightScaleManager: paired scale $name ($address)")
    }

    fun unpairScale() {
        prefs.edit().remove("scale_address").remove("scale_name").apply()
        _status.value = ScaleStatus.Idle
    }

    fun pairedAddress(): String? = prefs.getString("scale_address", null)
    fun pairedName(): String? = prefs.getString("scale_name", null)

    // ─── Discovery ────────────────────────────────────────────────────────────

    @SuppressLint("MissingPermission")
    fun discoverScales(): List<BluetoothDevice> {
        val manager = context.getSystemService(BluetoothManager::class.java) ?: return emptyList()
        val adapter: BluetoothAdapter = manager.adapter ?: return emptyList()
        if (!adapter.isEnabled) return emptyList()
        return adapter.bondedDevices.filter { isScaleDevice(it) }
    }

    @SuppressLint("MissingPermission")
    private fun isScaleDevice(device: BluetoothDevice): Boolean {
        val name = runCatching { device.name?.lowercase() }.getOrNull() ?: return false
        return name.contains("scale") || name.contains("brecknell") ||
            name.contains("dymo") || name.contains("postal") ||
            name.contains("weigh")
    }

    // ─── Weight request ───────────────────────────────────────────────────────

    /**
     * Request the current weight reading from the paired scale.
     *
     * Opens an RFCOMM socket, sends a carriage-return poll byte (Brecknell
     * SBI protocol), reads the first complete response line, parses it, and
     * immediately closes the socket.  Times out after 3 s.
     *
     * @return [ScaleReading.Weight] with the parsed value + unit on success,
     *         [ScaleReading.Error] with a reason string on any failure.
     */
    suspend fun requestWeight(): ScaleReading = withContext(Dispatchers.IO) {
        val address = pairedAddress()
            ?: return@withContext ScaleReading.Error("No scale paired")

        _status.value = ScaleStatus.Reading

        val reading = withTimeoutOrNull(3_000L) {
            runCatching {
                val socket = openSocket(address)
                    ?: return@runCatching ScaleReading.Error("Could not open socket to $address")
                socket.use { s ->
                    s.connect()
                    // Brecknell SBI poll: single CR prompts an immediate weight line.
                    s.outputStream.write(byteArrayOf(0x0D))
                    s.outputStream.flush()
                    val line = BufferedReader(InputStreamReader(s.inputStream))
                        .readLine() ?: ""
                    parseWeightLine(line)
                }
            }.getOrElse { e ->
                Timber.w(e, "WeightScaleManager: read failed")
                ScaleReading.Error(e.message ?: "IO error")
            }
        } ?: ScaleReading.Error("Scale read timed out (3 s)")

        _status.value = when (reading) {
            is ScaleReading.Weight -> ScaleStatus.Idle
            is ScaleReading.Error -> ScaleStatus.Error(reading.reason)
        }
        reading
    }

    // ─── Parsing ──────────────────────────────────────────────────────────────

    /**
     * Parse a raw scale ASCII line into a [ScaleReading].
     *
     * Handles common formats:
     * - Brecknell SBI: `"S ST,GS,  0.840 lb"` — extract last token pair.
     * - Dymo simple: `"  1.20 kg"` — trim, split on whitespace.
     */
    internal fun parseWeightLine(raw: String): ScaleReading {
        val trimmed = raw.trim()
        if (trimmed.isBlank()) return ScaleReading.Error("Empty response from scale")

        // Brecknell SBI: comma-separated fields, last two are value + unit.
        if (trimmed.contains(',')) {
            val parts = trimmed.split(',').map { it.trim() }
            val value = parts.getOrNull(parts.size - 2)?.toDoubleOrNull()
            val unit = parts.lastOrNull() ?: ""
            if (value != null) return ScaleReading.Weight(value, unit)
        }

        // Generic: last two whitespace-delimited tokens are value + unit.
        val tokens = trimmed.split(Regex("\\s+")).filter { it.isNotBlank() }
        val value = tokens.getOrNull(tokens.size - 2)?.toDoubleOrNull()
            ?: tokens.firstOrNull()?.toDoubleOrNull()
        val unit = tokens.lastOrNull() ?: "lb"
        if (value != null) return ScaleReading.Weight(value, unit)

        return ScaleReading.Error("Unrecognised scale response: $trimmed")
    }

    @SuppressLint("MissingPermission")
    private fun openSocket(address: String): BluetoothSocket? {
        val manager = context.getSystemService(BluetoothManager::class.java) ?: return null
        val adapter = manager.adapter ?: return null
        return runCatching {
            adapter.getRemoteDevice(address).createRfcommSocketToServiceRecord(SPP_UUID)
        }.getOrNull()
    }
}

/** Result of a weight read attempt. */
sealed class ScaleReading {
    data class Weight(val value: Double, val unit: String) : ScaleReading() {
        /** Format as a display string, e.g. `"0.84 lb"`. */
        val displayString: String get() = "%.2f %s".format(value, unit)
    }
    data class Error(val reason: String) : ScaleReading()
}

/** Connection / read lifecycle state for UI status chips. */
sealed class ScaleStatus {
    data object Idle : ScaleStatus()
    data object Reading : ScaleStatus()
    data class Error(val reason: String) : ScaleStatus()
}
