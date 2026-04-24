package com.bizarreelectronics.crm.util

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

/**
 * L2532 — Play Integrity API client (STUBBED pending dep wire).
 * Real impl uses `com.google.android.play:integrity:1.3.0`; add dep + restore
 * IntegrityManagerFactory-based code from git history when ready.
 */
@Singleton
class PlayIntegrityClient @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    suspend fun requestTokenString(nonce: String): String? {
        Timber.d("Play Integrity stubbed — nonce=%s", nonce.take(8))
        return null
    }
}

data class IntegrityVerdict(
    val passed: Boolean,
    val strict: Boolean = false,
    val reason: String? = null,
)
