package com.bizarreelectronics.crm.util

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Reports whether the device has any network interface at all.
 *
 * IMPORTANT: This does NOT determine whether we can reach the CRM server.
 * It is only used as a hint — "don't bother pinging, there is literally no
 * network available." The actual source of truth for online/offline status
 * is [ServerReachabilityMonitor], which pings the configured server URL
 * directly.
 *
 * We deliberately do NOT require NET_CAPABILITY_VALIDATED here because:
 *   1. That flag depends on Android reaching a third-party probe (typically
 *      connectivitycheck.gstatic.com). If Google is blocked, slow, or down,
 *      the flag is never set and we'd falsely report offline.
 *   2. VPN-only or LAN-only networks (e.g. user VPNs into their local
 *      network where the CRM server lives) often don't validate because
 *      the external probe can't be reached through the VPN tunnel, but
 *      the CRM server itself is perfectly reachable.
 *
 * If ANY interface (wifi, cellular, ethernet, VPN) has NET_CAPABILITY_INTERNET,
 * we report true and let ServerReachabilityMonitor actually probe the server.
 */
@Singleton
class NetworkMonitor @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    val isOnline: Flow<Boolean> = callbackFlow {
        val connectivityManager = context.getSystemService(ConnectivityManager::class.java)
        if (connectivityManager == null) {
            trySend(false)
            close()
            return@callbackFlow
        }

        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                trySend(hasAnyInternet(connectivityManager))
            }

            override fun onLost(network: Network) {
                trySend(hasAnyInternet(connectivityManager))
            }

            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                trySend(hasAnyInternet(connectivityManager))
            }
        }

        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()

        connectivityManager.registerNetworkCallback(request, callback)

        // Emit initial state
        trySend(hasAnyInternet(connectivityManager))

        awaitClose {
            connectivityManager.unregisterNetworkCallback(callback)
        }
    }.distinctUntilChanged()

    fun isCurrentlyOnline(): Boolean {
        val connectivityManager = context.getSystemService(ConnectivityManager::class.java)
            ?: return false
        return hasAnyInternet(connectivityManager)
    }

    /**
     * Returns true if ANY network interface (wifi, cellular, ethernet, VPN)
     * has the INTERNET capability. We deliberately ignore VALIDATED to avoid
     * relying on Google's captive portal probe.
     */
    private fun hasAnyInternet(cm: ConnectivityManager): Boolean {
        val networks = cm.allNetworks
        for (network in networks) {
            val caps = cm.getNetworkCapabilities(network) ?: continue
            if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                return true
            }
        }
        return false
    }
}
