package com.bizarreelectronics.crm.util

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.SharedPreferences
import android.print.PrintManager
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import timber.log.Timber
import java.io.IOException
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §17.4/17.5 — Printer discovery, pairing, and reconnect manager.
 *
 * Responsibilities:
 * - [discoverBluetoothPrinters] — scans [BluetoothAdapter.bondedDevices] filtered
 *   by device class (Printer) or known thermal-printer name heuristics.
 * - [discoverMopriaPrinters] — stubs Mopria service discovery via
 *   [PrintManager]; falls through to the OS print dialog for full-page jobs.
 * - [pair] — assigns a role (Receipt | Label | Invoice) to a discovered device
 *   and persists the assignment to SharedPreferences.
 * - [unpair] — removes the role assignment for a device address.
 * - [testPrint] — sends a sample ESC/POS job to the assigned printer for a role.
 * - [onActivityResume] — re-establishes socket connections to all paired devices;
 *   updates [printerStatus] StateFlows reactively.
 * - [kickDrawer] — forwards to [CashDrawerController.openDrawer] for verification
 *   from the PrinterDiscoveryScreen "Kick drawer" button.
 */
@Singleton
class PrinterManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val cashDrawerController: CashDrawerController,
) {
    private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    // Dedicated prefs file so printer keys don't pollute app_prefs.
    private val prefs: SharedPreferences =
        context.getSharedPreferences("printer_prefs", Context.MODE_PRIVATE)

    // ─── Printer roles ────────────────────────────────────────────────────────

    enum class PrinterRole(val prefKey: String, val label: String) {
        Receipt("receipt", "Receipt"),
        Label("label", "Label"),
        Invoice("invoice", "Invoice"),
    }

    // ─── Reactive status map keyed by BT address ──────────────────────────────

    private val _statusMap = MutableStateFlow<Map<String, PrinterStatus>>(emptyMap())
    val printerStatus: StateFlow<Map<String, PrinterStatus>> = _statusMap.asStateFlow()

    enum class PrinterStatus { Ready, NotConnected, Connecting }

    // ─── Discovery ────────────────────────────────────────────────────────────

    /**
     * Returns the list of Bluetooth devices that are already bonded (paired at
     * the OS level) and whose device class indicates a Printer, OR whose name
     * matches common thermal-printer brands.
     */
    @SuppressLint("MissingPermission")
    fun discoverBluetoothPrinters(): List<BluetoothDevice> {
        val btManager = context.getSystemService(BluetoothManager::class.java) ?: return emptyList()
        val adapter: BluetoothAdapter = btManager.adapter ?: return emptyList()
        if (!adapter.isEnabled) return emptyList()
        return adapter.bondedDevices.filter { device -> isPrinterDevice(device) }
    }

    /**
     * Returns a stub list of Mopria-capable print services discovered via
     * [PrintManager.getPrintServices]. Full-page document printing delegates
     * to the OS print dialog (android.print.PrintHelper).
     */
    fun discoverMopriaPrinters(): List<String> {
        val pm = context.getSystemService(PrintManager::class.java) ?: return emptyList()
        return try {
            pm.printJobs
                .mapNotNull { it.info?.label?.toString() }
                .distinct()
        } catch (e: Exception) {
            Timber.w(e, "PrinterManager: failed to enumerate Mopria print services")
            emptyList()
        }
    }

    // ─── Pairing / role assignment ────────────────────────────────────────────

    /**
     * Assigns [device] to [role] and persists the BT address + display name.
     * Replaces any previous assignment for that role.
     */
    @SuppressLint("MissingPermission")
    fun pair(device: BluetoothDevice, role: PrinterRole) {
        val address = device.address ?: return
        val name = runCatching { device.name }.getOrNull() ?: address
        prefs.edit()
            .putString("${role.prefKey}_address", address)
            .putString("${role.prefKey}_name", name)
            .apply()
        updateStatus(address, PrinterStatus.NotConnected)
        Timber.d("PrinterManager: paired $name ($address) as ${role.label}")
    }

    /**
     * Removes the role assignment for the printer currently assigned to [role].
     */
    fun unpair(role: PrinterRole) {
        val address = getPairedAddress(role) ?: return
        prefs.edit()
            .remove("${role.prefKey}_address")
            .remove("${role.prefKey}_name")
            .apply()
        _statusMap.value = _statusMap.value.toMutableMap().also { it.remove(address) }
        Timber.d("PrinterManager: unpaired ${role.label} printer ($address)")
    }

    /** Returns the persisted device address for [role], or null if none. */
    fun getPairedAddress(role: PrinterRole): String? =
        prefs.getString("${role.prefKey}_address", null)

    /** Returns the persisted display name for [role], or null if none. */
    fun getPairedName(role: PrinterRole): String? =
        prefs.getString("${role.prefKey}_name", null)

    // ─── Test print ───────────────────────────────────────────────────────────

    /**
     * Sends a short ESC/POS test banner to the printer assigned to [role].
     * Returns [Result.success] on success, [Result.failure] with a descriptive
     * message if no printer is assigned or the socket times out.
     */
    suspend fun testPrint(role: PrinterRole): Result<Unit> = withContext(Dispatchers.IO) {
        val address = getPairedAddress(role)
            ?: return@withContext Result.failure(IOException("No ${role.label} printer paired"))

        updateStatus(address, PrinterStatus.Connecting)
        val socket = openSocket(address)
            ?: run {
                updateStatus(address, PrinterStatus.NotConnected)
                return@withContext Result.failure(IOException("Could not open socket to $address"))
            }

        val result = withTimeoutOrNull(5_000L) {
            runCatching {
                socket.use { s ->
                    s.connect()
                    val out = s.outputStream
                    out.write(byteArrayOf(0x1B, 0x40)) // ESC @ — initialise
                    val name = getPairedName(role) ?: address
                    val text = "\u001B\u0045\u0001" +    // bold on
                        "Bizarre Electronics\n" +
                        "\u001B\u0045\u0000" +            // bold off
                        "Test print — ${role.label} printer\n" +
                        "$name\n\n"
                    out.write(text.toByteArray(Charsets.US_ASCII))
                    out.write(byteArrayOf(0x0A, 0x0A, 0x0A, 0x1D, 0x56, 0x41, 0x10)) // feed + cut
                    out.flush()
                }
            }
        } ?: Result.failure(IOException("Test print timed out"))

        updateStatus(address, if (result.isSuccess) PrinterStatus.Ready else PrinterStatus.NotConnected)
        result
    }

    // ─── Cash drawer verification (§17.4) ────────────────────────────────────

    /**
     * Kicks the cash drawer by delegating to [CashDrawerController.openDrawer].
     * Exposed here so [PrinterDiscoveryScreen] "Kick drawer" button has a single
     * entry point without a direct dep on [CashDrawerController].
     */
    suspend fun kickDrawer(): Result<Unit> = cashDrawerController.openDrawer()

    // ─── Auto-reconnect with exponential backoff (§17.12) ────────────────────

    /**
     * Attempts to reconnect to all paired printers.
     *
     * §17.12: Uses exponential backoff — first attempt immediate, subsequent
     * retries at 1s, 2s, 4s, 8s (capped).  Total budget per device is
     * [RECONNECT_BUDGET_MS] (15 s).  Status pills update reactively on each
     * probe so the UI always reflects real-time state.
     *
     * Call from Activity.onResume or ProcessLifecycleOwner.onStart.
     *
     * §17.12: Hardware failure NEVER blocks the UI — this runs on IO and
     * emits status changes; consumers degrade gracefully ("Print skipped,
     * reprint from sales history").
     */
    suspend fun onActivityResume() = withContext(Dispatchers.IO) {
        PrinterRole.entries.forEach { role ->
            val address = getPairedAddress(role) ?: return@forEach
            reconnectWithBackoff(address)
        }
    }

    /**
     * Attempt to reach a single device address with exponential backoff.
     * Emits [PrinterStatus.Connecting] while in progress, then [PrinterStatus.Ready]
     * or [PrinterStatus.NotConnected] when complete.
     *
     * Does NOT throw — all failures are captured in the status StateFlow.
     */
    suspend fun reconnectWithBackoff(address: String) = withContext(Dispatchers.IO) {
        updateStatus(address, PrinterStatus.Connecting)
        var delayMs = 0L
        var attempt = 0
        val startTime = System.currentTimeMillis()
        while (System.currentTimeMillis() - startTime < RECONNECT_BUDGET_MS) {
            if (delayMs > 0) delay(delayMs)
            val reachable = probeSocket(address)
            if (reachable) {
                updateStatus(address, PrinterStatus.Ready)
                Timber.d("PrinterManager: reconnected $address on attempt ${attempt + 1}")
                return@withContext
            }
            attempt++
            delayMs = when (attempt) {
                1 -> 1_000L
                2 -> 2_000L
                3 -> 4_000L
                else -> 8_000L
            }
            Timber.d("PrinterManager: $address not reachable (attempt $attempt), retry in ${delayMs}ms")
        }
        updateStatus(address, PrinterStatus.NotConnected)
        Timber.d("PrinterManager: reconnect budget exhausted for $address")
    }

    companion object {
        /** Total time budget for the exponential-backoff reconnect loop per device. */
        const val RECONNECT_BUDGET_MS = 15_000L
    }

    // ─── Internal helpers ─────────────────────────────────────────────────────

    @SuppressLint("MissingPermission")
    private fun isPrinterDevice(device: BluetoothDevice): Boolean {
        // BluetoothClass.Device.Major.IMAGING covers all imaging devices (printers, scanners).
        // There is no public BluetoothClass.Device.IMAGING_PRINTER constant in the SDK;
        // we rely on name heuristics for the printer sub-class.
        val majorClass = device.bluetoothClass?.majorDeviceClass
        if (majorClass == BluetoothClass.Device.Major.IMAGING) return true
        val name = runCatching { device.name?.lowercase() }.getOrNull() ?: ""
        return name.contains("printer") || name.contains("receipt") ||
            name.contains("thermal") || name.contains("pos") ||
            name.contains("epson") || name.contains("star") ||
            name.contains("bixolon") || name.contains("zebra") ||
            name.contains("brother") || name.contains("rollo")
    }

    @SuppressLint("MissingPermission")
    private fun openSocket(address: String): BluetoothSocket? {
        val btManager = context.getSystemService(BluetoothManager::class.java) ?: return null
        val adapter = btManager.adapter ?: return null
        return runCatching {
            adapter.getRemoteDevice(address)
                .createRfcommSocketToServiceRecord(SPP_UUID)
        }.getOrNull()
    }

    private suspend fun probeSocket(address: String): Boolean = withContext(Dispatchers.IO) {
        val socket = openSocket(address) ?: return@withContext false
        withTimeoutOrNull(2_000L) {
            runCatching { socket.connect(); socket.close(); true }.getOrDefault(false)
        } ?: false
    }

    private fun updateStatus(address: String, status: PrinterStatus) {
        _statusMap.value = _statusMap.value.toMutableMap().also { it[address] = status }
    }
}
