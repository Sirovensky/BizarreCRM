package com.bizarreelectronics.crm.data.repository

import com.bizarreelectronics.crm.data.remote.api.EnrollMemberRequest
import com.bizarreelectronics.crm.data.remote.api.Membership
import com.bizarreelectronics.crm.data.remote.api.MembershipApi
import com.bizarreelectronics.crm.data.remote.api.MembershipTier
import kotlinx.coroutines.CancellationException
import retrofit2.HttpException
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Repository for memberships / loyalty (§38).
 *
 * All calls degrade gracefully on 404 — callers receive a [Result.failure]
 * wrapping [MembershipRepository.NotAvailableException] when the server does
 * not implement memberships. The ViewModel maps that to
 * [MembershipUiState.NotAvailable].
 */
@Singleton
class MembershipRepository @Inject constructor(
    private val api: MembershipApi,
) {

    class NotAvailableException : Exception("Memberships not available on this server")

    // ── Tiers ────────────────────────────────────────────────────────────────

    suspend fun getTiers(): Result<List<MembershipTier>> = safeCall {
        val resp = api.getTiers()
        resp.data?.tiers ?: emptyList()
    }

    // ── Membership list ───────────────────────────────────────────────────────

    suspend fun getMemberships(): Result<List<Membership>> = safeCall {
        val resp = api.getMemberships()
        resp.data?.memberships ?: emptyList()
    }

    // ── Customer membership ───────────────────────────────────────────────────

    suspend fun getCustomerMembership(customerId: Long): Result<Membership?> = safeCall {
        // BUGHUNT-2026-05-17: runCatching wraps CancellationException via
        // kotlin.Result/Throwable, so a cancelled lookup would be reported as
        // "failure" with a CE message and the safeCall outer recover would
        // bubble it as a real error. Use try/catch so CE propagates and only
        // HttpException(404) degrades to null.
        try {
            api.getCustomerMembership(customerId).data?.membership
        } catch (e: CancellationException) {
            throw e
        } catch (e: HttpException) {
            if (e.code() == 404) null else throw e
        }
    }

    // ── Enroll ────────────────────────────────────────────────────────────────

    suspend fun enroll(
        customerId: Long,
        tierId: Long,
        billing: String,
        paymentMethod: String,
    ): Result<Membership> = safeCall {
        val resp = api.enroll(
            EnrollMemberRequest(
                customerId = customerId,
                tierId = tierId,
                billing = billing,
                paymentMethod = paymentMethod,
            )
        )
        resp.data?.membership ?: error("Enroll returned empty data")
    }

    // ── Cancel ────────────────────────────────────────────────────────────────

    /**
     * Cancel a membership. [immediate] = true cancels now; false = cancel at period end.
     *
     * Maps to `POST /memberships/:id/cancel`.
     */
    suspend fun cancel(membershipId: Long, immediate: Boolean = false): Result<Unit> = safeCall {
        api.cancel(membershipId, mapOf("immediate" to immediate))
        Unit
    }

    // ── Renew ────────────────────────────────────────────────────────────────

    suspend fun renew(membershipId: Long): Result<Membership> = safeCall {
        val resp = api.renew(membershipId)
        resp.data?.membership ?: error("Renew returned empty data")
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    // BUGHUNT-2026-05-17: runCatching wraps Throwable — including
    // CancellationException — so a cancelled enroll/cancel/renew call would
    // surface to the ViewModel as Result.failure with a CE message. The user
    // would then see a "failed" toast and likely tap retry, which would
    // re-issue an enroll/payment and double-charge. Catch CE first and
    // re-throw so structured concurrency unwinds the upstream scope instead.
    private suspend fun <T> safeCall(block: suspend () -> T): Result<T> = try {
        Result.success(block())
    } catch (e: CancellationException) {
        throw e
    } catch (e: HttpException) {
        Timber.w(e, "MembershipRepository.safeCall http")
        if (e.code() == 404) Result.failure(NotAvailableException()) else Result.failure(e)
    } catch (e: Exception) {
        Timber.w(e, "MembershipRepository.safeCall")
        Result.failure(e)
    }
}
