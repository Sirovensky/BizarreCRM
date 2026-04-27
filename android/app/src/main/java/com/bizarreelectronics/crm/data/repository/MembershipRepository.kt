package com.bizarreelectronics.crm.data.repository

import com.bizarreelectronics.crm.data.remote.api.EnrollMemberRequest
import com.bizarreelectronics.crm.data.remote.api.Membership
import com.bizarreelectronics.crm.data.remote.api.MembershipApi
import com.bizarreelectronics.crm.data.remote.api.MembershipTier
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
        runCatching { api.getCustomerMembership(customerId) }
            .getOrElse { e ->
                if (e is HttpException && e.code() == 404) return@safeCall null
                throw e
            }
            .data?.membership
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

    private suspend fun <T> safeCall(block: suspend () -> T): Result<T> =
        runCatching { block() }
            .recoverCatching { e ->
                Timber.w(e, "MembershipRepository.safeCall")
                when {
                    e is HttpException && e.code() == 404 -> throw NotAvailableException()
                    else -> throw e
                }
            }
}
