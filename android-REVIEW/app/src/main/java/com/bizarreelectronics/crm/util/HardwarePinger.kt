package com.bizarreelectronics.crm.util

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothSocket
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.io.IOException
import java.net.Socket
import java.util.UUID

/**
 * §36 L587 — Lightweight hardware reachability prober used by the morning-open
 * checklist (step 6: "Power on hardware").
 *
 * Two transport types are supported:
 *  - IPv4 TCP socket connection ([pingIpv4]) — primary for networked devices
 *    (receipt printer, cash drawer controller, POS terminal).
 *  - Bluetooth RFCOMM connect ([pingBluetooth]) — for Bluetooth-paired peripherals
 *    (mobile card readers, Bluetooth receipt printers).
 *
 * Both probes complete within 2 seconds; calls are always made from an IO
 * dispatcher so they never block the main thread.
 *
 * **Permissions**: `BLUETOOTH_CONNECT` is declared in the manifest (commit 9408f0d).
 * [pingBluetooth] requires the caller to hold this permission at the use-site.
 * On API 31+ the caller must request `BLUETOOTH_CONNECT` at runtime before
 * invoking this function.
 */
object HardwarePinger {

    private const val TAG = "HardwarePinger"

    /** Standard SPP UUID for Bluetooth serial-port profile. */
    private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    /**
     * Probe a networked device via a TCP connection attempt.
     *
     * Opens a [Socket] to [host]:[port], checks [Socket.isConnected], then
     * closes immediately.  Times out after 2 000 ms.
     *
     * @param host  Hostname or IPv4 address of the device.
     * @param port  TCP port to probe (e.g. 9100 for ESC/POS printers, 80 for web UI).
     * @return [PingResult.Success] with latency in ms, [PingResult.Timeout] on 2s
     *         timeout, or [PingResult.Failure] on any other IO error.
     */
    suspend fun pingIpv4(host: String, port: Int): PingResult = withContext(Dispatchers.IO) {
        val start = System.currentTimeMillis()
        try {
            withTimeout(2_000L) {
                Socket(host, port).use { socket ->
                    if (socket.isConnected) {
                        PingResult.Success(latencyMs = System.currentTimeMillis() - start)
                    } else {
                        PingResult.Failure(reason = "Socket connected but isConnected=false")
                    }
                }
            }
        } catch (e: kotlinx.coroutines.TimeoutCancellationException) {
            Log.d(TAG, "IPv4 ping $host:$port timed out")
            PingResult.Timeout
        } catch (e: IOException) {
            Log.d(TAG, "IPv4 ping $host:$port failed: ${e.message}")
            PingResult.Failure(reason = e.message ?: "IO error")
        } catch (e: Exception) {
            Log.w(TAG, "IPv4 ping $host:$port unexpected error: ${e.message}")
            PingResult.Failure(reason = e.message ?: "Unknown error")
        }
    }

    /**
     * Probe a Bluetooth-paired device via an RFCOMM socket connection attempt.
     *
     * Resolves the remote device by [macAddress], creates an RFCOMM socket using
     * the standard SPP UUID, attempts to connect within 2 000 ms, and immediately
     * closes the socket.
     *
     * **Permission**: requires `BLUETOOTH_CONNECT` at API 31+.  The caller is
     * responsible for requesting this permission before invoking this function.
     *
     * @param macAddress Colon-separated MAC address, e.g. `"00:11:22:33:AA:BB"`.
     * @return [PingResult.Success] with latency in ms, [PingResult.Timeout] on 2s
     *         timeout, or [PingResult.Failure] on any IO / Bluetooth error.
     */
    @SuppressLint("MissingPermission")
    suspend fun pingBluetooth(macAddress: String): PingResult = withContext(Dispatchers.IO) {
        val adapter = BluetoothAdapter.getDefaultAdapter()
        if (adapter == null || !adapter.isEnabled) {
            return@withContext PingResult.Failure(reason = "Bluetooth not available or disabled")
        }
        val start = System.currentTimeMillis()
        var socket: BluetoothSocket? = null
        try {
            withTimeout(2_000L) {
                val device = adapter.getRemoteDevice(macAddress)
                socket = device.createRfcommSocketToServiceRecord(SPP_UUID)
                socket!!.connect()
                PingResult.Success(latencyMs = System.currentTimeMillis() - start)
            }
        } catch (e: kotlinx.coroutines.TimeoutCancellationException) {
            Log.d(TAG, "Bluetooth ping $macAddress timed out")
            PingResult.Timeout
        } catch (e: IOException) {
            Log.d(TAG, "Bluetooth ping $macAddress failed: ${e.message}")
            PingResult.Failure(reason = e.message ?: "Bluetooth IO error")
        } catch (e: IllegalArgumentException) {
            Log.w(TAG, "Bluetooth ping $macAddress bad MAC: ${e.message}")
            PingResult.Failure(reason = "Invalid MAC address")
        } catch (e: Exception) {
            Log.w(TAG, "Bluetooth ping $macAddress unexpected: ${e.message}")
            PingResult.Failure(reason = e.message ?: "Unknown error")
        } finally {
            runCatching { socket?.close() }
        }
    }
}

/**
 * §36 L587 — Result of a hardware ping probe.
 *
 * UI rendering contract:
 *  - [Success]  → green check icon; latency label optional.
 *  - [Failure]  → red cross icon; tap opens diagnostic dialog with [reason].
 *  - [Timeout]  → amber spinner → after resolution becomes [Success]/[Failure].
 *  - [Pending]  → amber spinner while the probe is in flight.
 */
sealed class PingResult {
    /** Probe completed; [latencyMs] is the round-trip time in milliseconds. */
    data class Success(val latencyMs: Long) : PingResult()

    /** Probe failed before the 2 s deadline; [reason] is a user-facing diagnostic. */
    data class Failure(val reason: String) : PingResult()

    /** Probe did not complete within 2 000 ms. */
    data object Timeout : PingResult()

    /** Probe has not yet started or is in flight (initial state). */
    data object Pending : PingResult()
}
