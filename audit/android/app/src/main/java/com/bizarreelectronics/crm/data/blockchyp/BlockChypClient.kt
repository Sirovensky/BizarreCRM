package com.bizarreelectronics.crm.data.blockchyp

import android.content.SharedPreferences
import com.bizarreelectronics.crm.data.remote.api.BlockChypApi
import com.bizarreelectronics.crm.data.remote.api.BlockChypAdjustTipRequest
import com.bizarreelectronics.crm.data.remote.api.BlockChypCaptureSignatureRequest
import com.bizarreelectronics.crm.data.remote.api.BlockChypChargeData
import com.bizarreelectronics.crm.data.remote.api.BlockChypProcessPaymentRequest
import com.bizarreelectronics.crm.data.remote.api.BlockChypStatusData
import com.bizarreelectronics.crm.data.remote.api.BlockChypTestConnectionRequest
import com.bizarreelectronics.crm.data.remote.api.BlockChypVoidRequest
import retrofit2.HttpException
import timber.log.Timber
import java.io.IOException
import java.net.SocketTimeoutException
import javax.inject.Inject
import javax.inject.Named
import javax.inject.Singleton

// ─── Public data types ────────────────────────────────────────────────────────

/**
 * A successfully captured signature.
 * [base64DataUrl] is in `data:image/png;base64,…` format matching the server
 * validator at `ticketSignatures.routes.ts:39-42`.
 */
data class SignatureCapture(val base64DataUrl: String)

/**
 * Subset of server status data surfaced to callers.
 * [online] is set when [BlockChypApi.testConnection] succeeds AND the server
 * reports the terminal is reachable. [firmwareVersion] is null when the status
 * endpoint does not include it.
 */
data class BlockChypStatus(
    val enabled: Boolean,
    val online: Boolean,
    val terminalName: String?,
    val tcEnabled: Boolean,
    val firmwareVersion: String?,
)

/**
 * A successful card charge.
 * Amounts are in the server's native unit (dollar float), mirroring the
 * server API. The POS layer converts from cents before calling [charge].
 */
data class ChargeReceipt(
    val transactionId: String?,
    val authCode: String?,
    val cardType: String?,
    val lastFour: String?,
    val amountDollars: Double?,
    val replayed: Boolean,
)

// ─── Error types ─────────────────────────────────────────────────────────────

/**
 * Typed error cases for BlockChyp operations.
 *
 * [Conflict] is returned for 409 idempotency collisions — the caller should
 * surface "payment already in progress" UI rather than retrying immediately.
 * [Indeterminate] wraps the server's 202 pending_reconciliation response —
 * outcome unknown, operator must verify.
 */
sealed class ChargeError : Exception() {
    data class TerminalUnavailable(override val message: String) : ChargeError()
    data class Timeout(override val message: String = "Terminal did not respond within 30s") : ChargeError()
    data class NetworkError(override val message: String, val cause_: Throwable? = null) : ChargeError()
    data class NotPaired(override val message: String = "No terminal paired — configure in Hardware Settings") : ChargeError()
    data class Conflict(override val message: String) : ChargeError()
    data class Indeterminate(override val message: String, val transactionRef: String?) : ChargeError()
    data class ServerError(override val message: String, val httpCode: Int) : ChargeError()
    data class Unknown(override val message: String, val cause_: Throwable? = null) : ChargeError()
}

// ─── Client ──────────────────────────────────────────────────────────────────

private const val PREF_TERMINAL_IP = "blockchyp_terminal_ip"
private const val PREF_TERMINAL_NAME = "blockchyp_terminal_name"
private const val PREF_PAIRED = "blockchyp_paired"

/**
 * Thin client that proxies all BlockChyp operations through the CRM server.
 *
 * NOTE: No direct communication with BlockChyp hardware — the server holds
 * the SDK credentials. This class is purely a typed wrapper over [BlockChypApi]
 * with structured error mapping.
 *
 * Pairing state is persisted in [SharedPreferences] (the "blockchyp" named
 * prefs). The pairing flag is set when the operator saves a terminal IP in
 * HardwareSettingsScreen; the client itself does not write to hardware.
 *
 * Idempotency keys for [charge] must be stable per-attempt tokens (UUID v4 or
 * ULID) supplied by the caller. The server collapses duplicate keys into a
 * single charge and returns [ChargeError.Conflict] for in-flight duplicates.
 */
@Singleton
class BlockChypClient @Inject constructor(
    private val api: BlockChypApi,
    @Named("blockchyp") private val prefs: SharedPreferences,
) {

    // ── Pairing state ────────────────────────────────────────────────────────

    fun isPaired(): Boolean = prefs.getBoolean(PREF_PAIRED, false)

    fun savePairing(terminalIp: String, terminalName: String = "") {
        prefs.edit()
            .putString(PREF_TERMINAL_IP, terminalIp)
            .putString(PREF_TERMINAL_NAME, terminalName)
            .putBoolean(PREF_PAIRED, terminalIp.isNotBlank())
            .apply()
    }

    fun clearPairing() {
        prefs.edit()
            .remove(PREF_TERMINAL_IP)
            .remove(PREF_TERMINAL_NAME)
            .putBoolean(PREF_PAIRED, false)
            .apply()
    }

    fun pairedTerminalName(): String? = prefs.getString(PREF_TERMINAL_NAME, null)

    // ── Public API ───────────────────────────────────────────────────────────

    /**
     * Verify that the server can reach the terminal.
     * Updates [isPaired] to true on success.
     */
    suspend fun testConnection(terminalId: String): Result<Unit> = runCatching {
        val resp = api.testConnection(BlockChypTestConnectionRequest(terminalName = terminalId))
        if (!resp.success || resp.data?.success == false) {
            throw ChargeError.TerminalUnavailable(
                resp.message ?: "Terminal connection test failed",
            )
        }
    }.mapApiErrors()

    /**
     * Charge the customer's card via the paired terminal.
     *
     * [amountCents] is converted to dollars before transmission.
     * [orderId] is used as the invoice reference on the server — must match
     * an existing invoice so the server can record the payment.
     * [idempotencyKey] MUST be a stable per-attempt token; see server docs.
     */
    suspend fun charge(
        amountCents: Long,
        orderId: String,
        tipCents: Long = 0L,
        idempotencyKey: String,
    ): Result<ChargeReceipt> = runCatching {
        val amountDollars = amountCents / 100.0
        val tipDollars = if (tipCents > 0) tipCents / 100.0 else null

        // orderId is the invoice id on the server — parse it
        val invoiceId = orderId.toLongOrNull()
            ?: throw ChargeError.Unknown("orderId must be numeric invoice ID, got: $orderId")

        val resp = api.processPayment(
            idempotencyKey = idempotencyKey,
            request = BlockChypProcessPaymentRequest(
                invoiceId = invoiceId,
                tip = tipDollars,
                idempotencyKey = idempotencyKey,
            ),
        )

        val data = resp.data ?: throw ChargeError.ServerError(
            resp.message ?: "Empty charge response",
            httpCode = 500,
        )

        // 202 pending_reconciliation — server could not confirm outcome
        if (data.status == "pending_reconciliation") {
            throw ChargeError.Indeterminate(
                data.message ?: "Terminal charge outcome unknown",
                transactionRef = null,
            )
        }

        if (!resp.success) {
            throw ChargeError.TerminalUnavailable(resp.message ?: "Charge failed")
        }

        ChargeReceipt(
            transactionId = data.transactionId,
            authCode = data.authCode,
            cardType = data.cardType,
            lastFour = data.last4,
            amountDollars = amountDollars,
            replayed = data.replayed,
        )
    }.mapApiErrors()

    suspend fun voidTransaction(transactionId: String): Result<Unit> = runCatching {
        val resp = api.voidPayment(BlockChypVoidRequest(paymentId = transactionId))
        if (!resp.success) {
            throw ChargeError.ServerError(
                resp.message ?: "Void failed",
                httpCode = 400,
            )
        }
    }.mapApiErrors()

    suspend fun adjustTip(transactionId: String, newTipCents: Long): Result<Unit> = runCatching {
        val resp = api.adjustTip(
            BlockChypAdjustTipRequest(
                transactionId = transactionId,
                newTip = newTipCents / 100.0,
            ),
        )
        if (!resp.success) {
            Timber.w("adjustTip returned !success: code=${resp.data?.code} msg=${resp.message}")
            throw ChargeError.ServerError(
                resp.data?.message ?: resp.message ?: "Tip adjust not supported",
                httpCode = 200,
            )
        }
    }.mapApiErrors()

    /**
     * Capture a signature on the terminal before a ticket is created.
     * Returns a [SignatureCapture] whose [base64DataUrl] is in the
     * `data:image/png;base64,…` format expected by the server signature endpoint.
     */
    suspend fun captureCheckInSignature(ticketId: Long): Result<SignatureCapture> = runCatching {
        val resp = api.captureCheckInSignature()
        val dataUrl = resp.data?.base64DataUrl
        if (!resp.success || dataUrl.isNullOrBlank()) {
            throw ChargeError.TerminalUnavailable(
                resp.message ?: "Signature capture failed or returned empty data",
            )
        }
        SignatureCapture(base64DataUrl = dataUrl)
    }.mapApiErrors()

    /**
     * Capture a signature on the terminal for an existing invoice/ticket.
     */
    suspend fun captureSignature(invoiceId: Long): Result<SignatureCapture> = runCatching {
        val resp = api.captureSignature(BlockChypCaptureSignatureRequest(ticketId = invoiceId))
        val dataUrl = resp.data?.base64DataUrl
        if (!resp.success || dataUrl.isNullOrBlank()) {
            throw ChargeError.TerminalUnavailable(
                resp.message ?: "Signature capture failed or returned empty data",
            )
        }
        SignatureCapture(base64DataUrl = dataUrl)
    }.mapApiErrors()

    /**
     * Fetch terminal/gateway status from the server.
     * Does NOT throw — returns a safe offline [BlockChypStatus] on any error.
     */
    suspend fun status(): BlockChypStatus {
        return try {
            val resp = api.getStatus()
            val d = resp.data ?: return offlineStatus()
            BlockChypStatus(
                enabled = d.enabled,
                online = d.enabled,
                terminalName = d.terminalName,
                tcEnabled = d.tcEnabled,
                firmwareVersion = d.firmwareVersion,
            )
        } catch (e: Exception) {
            Timber.w(e, "BlockChyp status check failed")
            offlineStatus()
        }
    }

    // ── Cart helper (called by PosTenderViewModel "Card reader" tile) ────────

    /**
     * Top-level helper for PosTenderViewModel.
     * [cartTotalCents] comes from the live cart state; [orderId] is the
     * invoice ID string that the POS cart assigns before tendering.
     */
    suspend fun chargeForCart(
        cartTotalCents: Long,
        orderId: String,
        idempotencyKey: String,
        tipCents: Long = 0L,
    ): Result<ChargeReceipt> = charge(
        amountCents = cartTotalCents,
        orderId = orderId,
        tipCents = tipCents,
        idempotencyKey = idempotencyKey,
    )

    // ── Private helpers ───────────────────────────────────────────────────────

    private fun offlineStatus() = BlockChypStatus(
        enabled = false,
        online = false,
        terminalName = pairedTerminalName(),
        tcEnabled = false,
        firmwareVersion = null,
    )
}

/**
 * Maps OkHttp / Retrofit exceptions to typed [ChargeError]s.
 * Applied after every API call so error handling is consistent.
 */
private fun <T> Result<T>.mapApiErrors(): Result<T> = onFailure { e ->
    when (e) {
        is ChargeError -> return this // already typed — pass through
        is SocketTimeoutException -> return Result.failure(ChargeError.Timeout())
        is HttpException -> {
            val body = runCatching { e.response()?.errorBody()?.string() }.getOrNull()
            return when (e.code()) {
                401 -> Result.failure(ChargeError.NotPaired())
                409 -> Result.failure(ChargeError.Conflict(body ?: "Idempotency conflict"))
                else -> Result.failure(ChargeError.ServerError(body ?: e.message(), e.code()))
            }
        }
        is IOException -> return Result.failure(ChargeError.NetworkError(e.message ?: "Network error", e))
    }
}
