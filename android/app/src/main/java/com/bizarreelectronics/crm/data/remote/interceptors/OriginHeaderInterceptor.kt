package com.bizarreelectronics.crm.data.remote.interceptors

import okhttp3.Interceptor
import okhttp3.Response
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Adds an `Origin` header to every outgoing request derived from the request's
 * own scheme + host + (non-default) port.
 *
 * The server enforces `Origin header required` in production (see
 * `packages/server/src/index.ts`). Native Android clients do not send Origin
 * by default, so requests without this interceptor are rejected with 403.
 *
 * The value matches what a browser would set when loading the same origin —
 * scheme + host, with the port included only if non-standard — so the server
 * does not need a special-case for mobile.
 */
@Singleton
class OriginHeaderInterceptor @Inject constructor() : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        // Only set Origin if the caller hasn't already set one.
        if (request.header("Origin") != null) return chain.proceed(request)

        val url = request.url
        val scheme = url.scheme
        val host = url.host
        val port = url.port
        val isDefaultPort = (scheme == "https" && port == 443) || (scheme == "http" && port == 80)
        val origin = if (isDefaultPort) "$scheme://$host" else "$scheme://$host:$port"

        val withOrigin = request.newBuilder()
            .header("Origin", origin)
            .build()
        return chain.proceed(withOrigin)
    }
}
