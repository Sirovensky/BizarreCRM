package com.bizarreelectronics.crm.data.remote.interceptors

import com.bizarreelectronics.crm.util.ServerReachabilityMonitor
import dagger.Lazy
import okhttp3.Interceptor
import okhttp3.Response
import java.io.IOException
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Reports real API traffic outcomes to [ServerReachabilityMonitor] so the
 * offline banner reacts instantly — without waiting for the next heartbeat.
 *
 * - Any HTTP response (even 500) means the server was reachable → reportSuccess
 * - A network-level IOException means it wasn't → reportFailure
 *
 * Uses [Lazy] injection to break the circular dependency:
 * OkHttpClient → this interceptor → ServerReachabilityMonitor → OkHttpClient (ping client)
 */
@Singleton
class ReachabilityReportingInterceptor @Inject constructor(
    private val monitor: Lazy<ServerReachabilityMonitor>,
) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        return try {
            val response = chain.proceed(chain.request())
            // Any HTTP response means the server was reachable — even 4xx/5xx.
            // The server responded with an error, but the server is UP.
            monitor.get().reportSuccess()
            response
        } catch (e: IOException) {
            // Network-level failure: DNS, connection refused, timeout, etc.
            monitor.get().reportFailure()
            throw e
        }
    }
}
