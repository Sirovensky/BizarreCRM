package com.bizarreelectronics.crm.util

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import com.bizarreelectronics.crm.data.local.db.dao.SyncQueueDao
import com.bizarreelectronics.crm.data.local.db.entities.SyncQueueEntity
import com.bizarreelectronics.crm.ui.screens.pos.CashDrawerControllerStub
import com.bizarreelectronics.crm.ui.screens.pos.PrintableReceipt
import com.google.gson.Gson
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.IOException
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §16.10 — Cash drawer controller.
 *
 * Sends an ESC/POS "kick drawer" sequence to the currently-paired Bluetooth
 * receipt printer. Falls back gracefully when no printer is available.
 *
 * [openDrawer] → ESC/POS kick (pin 2: 1B 70 00 19 FA)
 * [manualOpen] → role-gated (admin only); writes an audit entry to sync_queue.
 * [printReceipt] → renders receipt as plain text over the BT socket.
 *
 * All BT operations run on Dispatchers.IO with a 2-second timeout.
 */
@Singleton
class CashDrawerController @Inject constructor(
    @ApplicationContext private val context: Context,
    private val syncQueueDao: SyncQueueDao,
    private val gson: Gson,
) : CashDrawerControllerStub {

    // ESC/POS kick-drawer command (pin 2, 25ms on, 250ms off)
    private val ESC_POS_KICK = byteArrayOf(0x1B, 0x70, 0x00, 0x19.toByte(), 0xFA.toByte())
    private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    // ─── Public API ───────────────────────────────────────────────────────────

    override suspend fun openDrawer(): Result<Unit> = withContext(Dispatchers.IO) {
        val socket = findPrinterSocket()
            ?: return@withContext Result.failure(IOException("No Bluetooth receipt printer paired"))

        withTimeoutOrNull(2_000L) {
            runCatching {
                socket.use { s ->
                    s.connect()
                    s.outputStream.write(ESC_POS_KICK)
                    s.outputStream.flush()
                }
            }
        } ?: Result.failure(IOException("Cash drawer kick timed out (2 s)"))
    }

    override suspend fun manualOpen(
        operatorId: String,
        operatorRole: String,
        reason: String,
    ): Result<Unit> {
        if (operatorRole != "admin") {
            return Result.failure(SecurityException("Cash drawer manual open requires admin role"))
        }
        runCatching {
            syncQueueDao.insert(
                SyncQueueEntity(
                    entityType = "cash_drawer_manual_open",
                    entityId = 0L,
                    operation = "manual_open",
                    payload = gson.toJson(
                        mapOf(
                            "operator" to operatorId,
                            "operator_role" to operatorRole,
                            "reason" to reason,
                            "timestamp" to System.currentTimeMillis(),
                        )
                    ),
                )
            )
        }
        return openDrawer()
    }

    override fun hasPrinter(): Boolean = findPrinterDevice() != null

    override suspend fun printReceipt(receipt: PrintableReceipt, giftReceipt: Boolean): Result<Unit> =
        withContext(Dispatchers.IO) {
            val socket = findPrinterSocket()
                ?: return@withContext Result.failure(IOException("No Bluetooth receipt printer paired"))

            withTimeoutOrNull(5_000L) {
                runCatching {
                    socket.use { s ->
                        s.connect()
                        val out = s.outputStream
                        out.write(byteArrayOf(0x1B, 0x40))
                        val text = buildReceiptText(receipt, giftReceipt)
                        out.write(text.toByteArray(Charsets.US_ASCII))
                        out.write(byteArrayOf(0x0A, 0x0A, 0x0A, 0x1D, 0x56, 0x41, 0x10))
                        out.flush()
                        out.write(ESC_POS_KICK)
                        out.flush()
                    }
                }
            } ?: Result.failure(IOException("Print timed out (5 s)"))
        }

    // ─── Bluetooth helpers ────────────────────────────────────────────────────

    @SuppressLint("MissingPermission")
    private fun findPrinterDevice(): BluetoothDevice? {
        val btManager = context.getSystemService(BluetoothManager::class.java) ?: return null
        val adapter: BluetoothAdapter = btManager.adapter ?: return null
        if (!adapter.isEnabled) return null
        return adapter.bondedDevices.firstOrNull { device ->
            val name = device.name?.lowercase() ?: ""
            name.contains("printer") || name.contains("receipt") ||
                name.contains("pos") || name.contains("thermal") || name.contains("epson") ||
                name.contains("star") || name.contains("bixolon")
        }
    }

    @SuppressLint("MissingPermission")
    private fun findPrinterSocket(): BluetoothSocket? {
        val device = findPrinterDevice() ?: return null
        return runCatching {
            device.createRfcommSocketToServiceRecord(SPP_UUID)
        }.getOrNull()
    }

    private fun buildReceiptText(receipt: PrintableReceipt, giftReceipt: Boolean): String {
        val sb = StringBuilder()
        sb.append("\u001B\u0045\u0001")
        sb.appendLine("Bizarre Electronics")
        sb.append("\u001B\u0045\u0000")
        sb.appendLine("===================")
        for (line in receipt.lines) {
            if (giftReceipt) {
                sb.appendLine("  ${line.name} x${line.qty}")
            } else {
                val price = "${line.totalCents / 100}.${(line.totalCents % 100).toString().padStart(2, '0')}"
                sb.appendLine("  ${line.name.take(20).padEnd(20)} \$$price")
            }
        }
        if (!giftReceipt) {
            sb.appendLine("-------------------")
            val total = "${receipt.totalCents / 100}.${(receipt.totalCents % 100).toString().padStart(2, '0')}"
            sb.appendLine("TOTAL: \$$total")
        }
        sb.appendLine()
        sb.appendLine("Thank you!")
        return sb.toString()
    }
}
