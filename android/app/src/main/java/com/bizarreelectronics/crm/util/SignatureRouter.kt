package com.bizarreelectronics.crm.util

import com.bizarreelectronics.crm.data.blockchyp.BlockChypClient
import com.bizarreelectronics.crm.data.blockchyp.ChargeError
import com.bizarreelectronics.crm.data.blockchyp.SignatureCapture
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

// ─── Public API types ─────────────────────────────────────────────────────────

/** Which surface collected the signature. */
sealed class SignatureSource {
    /** Captured on the paired BlockChyp payment terminal. */
    object TerminalBlockChyp : SignatureSource()
    /** Drawn by the customer on the phone screen. */
    object OnPhonePad : SignatureSource()
}

enum class SignatureReason {
    /** Before ticket is created (pre-ticket check-in sign). */
    CHECK_IN,
    /** After ticket is created (post-repair checkout sign). */
    CHECKOUT,
    /** Waiver / terms acknowledgement. */
    WAIVER,
    /** Payment signature (tender flow). */
    PAYMENT,
}

/**
 * Returned by [SignatureRouter.capture].
 * [base64DataUrl] is always in `data:image/png;base64,…` format matching the
 * server validator at `ticketSignatures.routes.ts:39-42`.
 */
data class SignatureResult(
    val source: SignatureSource,
    val base64DataUrl: String,
)

/**
 * Implemented by the UI layer (MainActivity / navigation coordinator) to present
 * the on-phone [com.bizarreelectronics.crm.ui.components.SignaturePad] full-screen
 * when the terminal path is unavailable.
 *
 * [showSignaturePad] is called on the main thread. It must call [onResult] exactly
 * once with a non-null data-URL when the user accepts, or with null to indicate
 * cancellation. The coroutine awaiting [SignatureRouter.capture] resumes after
 * [onResult] is invoked.
 */
interface SignaturePromptHost {
    fun showSignaturePad(reason: SignatureReason, onResult: (String?) -> Unit)
}

// ─── Router ───────────────────────────────────────────────────────────────────

/**
 * Single entry-point for all signature capture in the Android app.
 *
 * Routing logic:
 * 1. If [BlockChypClient.isPaired] **and** status is online → try terminal.
 * 2. If the terminal call fails (unavailable, timeout, network) → fall back to
 *    the on-phone [SignaturePromptHost].
 * 3. If not paired or offline → go straight to phone pad.
 *
 * Callers never choose the path — they await [capture] and receive a
 * [SignatureResult] regardless of which surface collected the signature.
 * Cancellation (user taps "Cancel" on the phone pad) returns a [CancelledException].
 */
@Singleton
class SignatureRouter @Inject constructor(
    private val blockChypClient: BlockChypClient,
    private val host: SignaturePromptHost,
) {

    /**
     * @param reason Why the signature is being collected (affects terminal prompt text).
     * @param ticketId Required for [SignatureReason.CHECK_IN] terminal path.
     * @param invoiceId Required for [SignatureReason.PAYMENT] / [SignatureReason.CHECKOUT] terminal path.
     * @throws CancelledException if the user dismisses the phone pad without signing.
     */
    suspend fun capture(
        reason: SignatureReason,
        ticketId: Long? = null,
        invoiceId: Long? = null,
    ): Result<SignatureResult> {
        val paired = blockChypClient.isPaired()
        if (paired) {
            val terminalResult = tryTerminal(reason, ticketId, invoiceId)
            if (terminalResult != null) return terminalResult
        }
        return captureOnPhone(reason)
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    /**
     * Attempts to collect the signature on the BlockChyp terminal.
     * Returns null when the caller should fall back to the phone pad.
     * Returns a [Result.failure] only for non-fallback errors (none currently).
     */
    private suspend fun tryTerminal(
        reason: SignatureReason,
        ticketId: Long?,
        invoiceId: Long?,
    ): Result<SignatureResult>? {
        val statusOnline = try {
            blockChypClient.status().online
        } catch (e: Exception) {
            Timber.w(e, "SignatureRouter: status check threw, treating as offline")
            false
        }

        if (!statusOnline) {
            Timber.d("SignatureRouter: terminal offline, falling back to phone pad")
            return null
        }

        val captureResult: Result<SignatureCapture> = when (reason) {
            SignatureReason.CHECK_IN, SignatureReason.WAIVER ->
                blockChypClient.captureCheckInSignature(ticketId ?: 0L)
            SignatureReason.CHECKOUT, SignatureReason.PAYMENT ->
                blockChypClient.captureSignature(invoiceId ?: ticketId ?: 0L)
        }

        return captureResult.fold(
            onSuccess = { sig ->
                Result.success(
                    SignatureResult(
                        source = SignatureSource.TerminalBlockChyp,
                        base64DataUrl = sig.base64DataUrl,
                    ),
                )
            },
            onFailure = { err ->
                when (err) {
                    is ChargeError.TerminalUnavailable,
                    is ChargeError.Timeout,
                    is ChargeError.NetworkError -> {
                        Timber.w(err, "SignatureRouter: terminal capture failed, falling back to phone pad")
                        null // triggers phone pad fallback
                    }
                    else -> {
                        Timber.w(err, "SignatureRouter: terminal capture non-fallback error")
                        null // still fall back; don't surface error to UX
                    }
                }
            },
        )
    }

    /**
     * Presents the on-phone [SignaturePad] via [SignaturePromptHost] and suspends
     * until the user accepts or cancels.
     */
    private suspend fun captureOnPhone(reason: SignatureReason): Result<SignatureResult> =
        suspendCancellableCoroutine { cont ->
            host.showSignaturePad(reason) { dataUrl ->
                if (!cont.isActive) return@showSignaturePad
                if (dataUrl.isNullOrBlank()) {
                    cont.resume(Result.failure(CancelledException("User cancelled signature")))
                } else {
                    cont.resume(
                        Result.success(
                            SignatureResult(
                                source = SignatureSource.OnPhonePad,
                                base64DataUrl = dataUrl,
                            ),
                        ),
                    )
                }
            }
        }

    class CancelledException(message: String) : Exception(message)
}
