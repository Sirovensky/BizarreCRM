package com.bizarreelectronics.crm.ui.screens.pos

/**
 * Receipt data passed to the thermal printer when finalizing a sale.
 * Decoupled from POS VM state so hardware utilities don't depend on
 * UI layer models.
 */
data class PrintableReceipt(
    val lines: List<PrintableLine>,
    val totalCents: Long,
    val customerName: String? = null,
    val orderId: String? = null,
)

data class PrintableLine(
    val name: String,
    val qty: Int,
    val totalCents: Long,
)

/** Hardware abstraction for the BT/USB cash drawer + thermal printer. */
interface CashDrawerControllerStub {
    suspend fun openDrawer(): Result<Unit>
    /**
     * Role-gated manual open. Only succeeds when [operatorRole] == "admin";
     * returns [Result.failure] with [SecurityException] otherwise.
     * [reason] is written to the sync-queue audit payload.
     */
    suspend fun manualOpen(
        operatorId: String,
        operatorRole: String,
        reason: String,
    ): Result<Unit>
    fun hasPrinter(): Boolean
    suspend fun printReceipt(receipt: PrintableReceipt, giftReceipt: Boolean): Result<Unit>
}
