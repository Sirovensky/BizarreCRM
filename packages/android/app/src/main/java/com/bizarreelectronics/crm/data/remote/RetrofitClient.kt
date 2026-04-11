package com.bizarreelectronics.crm.data.remote

import android.util.Log
import com.bizarreelectronics.crm.BuildConfig
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.*
import com.bizarreelectronics.crm.data.remote.interceptors.AuthInterceptor
import com.bizarreelectronics.crm.data.remote.interceptors.ReachabilityReportingInterceptor
import com.google.gson.Gson
import com.google.gson.GsonBuilder
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import okhttp3.CertificatePinner
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.io.IOException
import java.net.Inet4Address
import java.net.InetAddress
import java.security.SecureRandom
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.inject.Qualifier
import javax.inject.Singleton
import javax.net.ssl.HostnameVerifier
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

/**
 * Qualifier used to inject the longer-timeout OkHttpClient/Retrofit reserved
 * for large paginated sync operations. Normal requests keep the shorter
 * timeouts so that UI calls fail fast.
 */
@Qualifier
@Retention(AnnotationRetention.BINARY)
annotation class SyncHttp

// ============================================================================
// CERTIFICATE PINNING — REPLACE BEFORE RELEASE
// ============================================================================
// CERT_PIN_SHA256_HASHES
//
// These pins MUST be replaced with the real production certificate SPKI hashes
// before cutting a release build. Both a primary pin AND a backup pin are
// required so that cert rotation does not brick every installed app.
//
// How to generate pins from the live production cert:
//
//   openssl s_client -servername bizarrecrm.com -connect bizarrecrm.com:443 \
//     </dev/null 2>/dev/null \
//     | openssl x509 -pubkey -noout \
//     | openssl pkey -pubin -outform der \
//     | openssl dgst -sha256 -binary \
//     | openssl enc -base64
//
// Then format as: "sha256/<BASE64_HASH>".
//
// The backup pin should be for a pre-generated but not-yet-deployed cert, or
// for the intermediate CA as a coarser fallback. Never ship with only one pin.
//
// Until real pins are filled in, `ENABLE_CERT_PINNING` stays false in release
// builds to avoid bricking the app — but this MUST be flipped to true and the
// stub pins replaced before going to production.
// ============================================================================
private const val ENABLE_CERT_PINNING: Boolean = false
private val CERT_PIN_SHA256_HASHES: List<String> = listOf(
    // TODO(release): replace with real primary pin
    "sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
    // TODO(release): replace with real backup pin
    "sha256/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=",
)

/** The production hostname the release client is expected to talk to. */
private const val PRODUCTION_HOST: String = "bizarrecrm.com"

/**
 * Hosts that are allowed to bypass real TLS validation in DEBUG builds.
 * Anything else must still go through the platform trust manager.
 */
private val DEBUG_TRUSTED_LITERAL_HOSTS: Set<String> = setOf(
    "localhost",
    "10.0.2.2",      // Android emulator → host loopback
    "10.0.3.2",      // Genymotion → host loopback
    "127.0.0.1",
    "::1",
)

/**
 * Returns true when the supplied hostname is a safe target for the debug
 * trust-all trust manager: either a well-known loopback literal, or an
 * RFC1918 private IPv4 address (10.x, 172.16-31.x, 192.168.x) used for LAN
 * dev servers with self-signed certs.
 */
private fun isDebugTrustedHost(hostname: String?): Boolean {
    if (hostname.isNullOrBlank()) return false
    val normalized = hostname.lowercase()
    if (normalized in DEBUG_TRUSTED_LITERAL_HOSTS) return true
    return isRfc1918Ipv4(normalized)
}

private fun isRfc1918Ipv4(host: String): Boolean {
    return try {
        val addr: InetAddress = InetAddress.getByName(host)
        if (addr !is Inet4Address) return false
        val bytes = addr.address
        val b0 = bytes[0].toInt() and 0xff
        val b1 = bytes[1].toInt() and 0xff
        when {
            b0 == 10 -> true
            b0 == 172 && b1 in 16..31 -> true
            b0 == 192 && b1 == 168 -> true
            else -> false
        }
    } catch (_: Exception) {
        false
    }
}

/**
 * X509TrustManager that trusts any cert for hosts on the RFC1918 / loopback
 * allow-list, and delegates to the platform default trust manager for
 * everything else. Used only in DEBUG builds so developers can point at a
 * self-signed LAN server without disabling TLS validation globally.
 */
private class HostnameRestrictedTrustManager(
    private val delegate: X509TrustManager,
) : X509TrustManager {

    @Volatile
    var currentHostname: String? = null

    override fun checkClientTrusted(chain: Array<out X509Certificate>, authType: String) {
        delegate.checkClientTrusted(chain, authType)
    }

    override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String) {
        if (isDebugTrustedHost(currentHostname)) {
            // Trusted LAN host — skip validation so self-signed certs work in DEBUG.
            return
        }
        delegate.checkServerTrusted(chain, authType)
    }

    override fun getAcceptedIssuers(): Array<X509Certificate> = delegate.acceptedIssuers
}

/**
 * HostnameVerifier counterpart of [HostnameRestrictedTrustManager]. Accepts
 * any hostname on the debug allow-list and falls back to the platform default
 * for everything else.
 */
private class HostnameRestrictedVerifier(
    private val trustManager: HostnameRestrictedTrustManager,
) : HostnameVerifier {
    private val default = javax.net.ssl.HttpsURLConnection.getDefaultHostnameVerifier()
    override fun verify(hostname: String?, session: javax.net.ssl.SSLSession?): Boolean {
        trustManager.currentHostname = hostname
        if (isDebugTrustedHost(hostname)) return true
        return default.verify(hostname, session)
    }
}

/**
 * Looks up the platform default X509TrustManager so we can delegate to it
 * for anything outside the debug allow-list.
 */
private fun platformTrustManager(): X509TrustManager {
    val tmf = javax.net.ssl.TrustManagerFactory.getInstance(
        javax.net.ssl.TrustManagerFactory.getDefaultAlgorithm(),
    )
    tmf.init(null as java.security.KeyStore?)
    val tms = tmf.trustManagers
    return tms.filterIsInstance<X509TrustManager>().firstOrNull()
        ?: throw IllegalStateException("No X509TrustManager available from platform")
}

/**
 * Interceptor that dynamically rewrites the base URL on every request based
 * on the server URL stored in AuthPreferences — with strict validation:
 *
 *  - URL must parse and use HTTPS (DEBUG also permits HTTP for LAN dev).
 *  - Host must either match the configured production domain/subdomain, or
 *    be a DEBUG-trusted LAN host (loopback, emulator, RFC1918).
 *  - URL must not contain userinfo, alternate schemes, or injection markers.
 *  - Stored URL is signed with HMAC-SHA256 keyed to a per-install secret;
 *    tampering with the SharedPreferences value invalidates the signature
 *    and the request is rejected.
 *
 * When validation fails the request is rejected with IOException — we fail
 * CLOSED rather than falling through to the placeholder base URL.
 */
class DynamicBaseUrlInterceptor(private val authPreferences: AuthPreferences) : Interceptor {

    companion object {
        private const val TAG = "DynBaseUrl"

        /**
         * Returns true if the stored URL's host is acceptable:
         *   - Production host itself ("bizarrecrm.com")
         *   - Any subdomain of it ("foo.bizarrecrm.com")
         *   - Any *.bizcrm.com tenant host
         *   - In DEBUG, loopback / RFC1918 LAN hosts
         */
        internal fun isHostAllowed(host: String): Boolean {
            val h = host.lowercase()
            if (h == PRODUCTION_HOST || h.endsWith(".$PRODUCTION_HOST")) return true
            if (h == "bizcrm.com" || h.endsWith(".bizcrm.com")) return true
            if (BuildConfig.DEBUG && isDebugTrustedHost(h)) return true
            return false
        }

        /**
         * Validates the raw server URL string and returns a parsed HttpUrl
         * if it is safe to use, otherwise null.
         */
        internal fun validate(rawUrl: String): okhttp3.HttpUrl? {
            // Reject obvious injection attempts before even parsing.
            val lowered = rawUrl.lowercase()
            if ("@" in rawUrl) return null
            if ("javascript:" in lowered || "data:" in lowered || "file:" in lowered) return null
            if (" " in rawUrl || "\n" in rawUrl || "\r" in rawUrl || "\t" in rawUrl) return null

            val parsed = rawUrl.toHttpUrlOrNull() ?: return null

            // Scheme: HTTPS only in release. DEBUG may allow HTTP for LAN dev
            // servers, but only to a DEBUG-trusted host.
            if (parsed.scheme != "https") {
                if (!BuildConfig.DEBUG) return null
                if (parsed.scheme != "http") return null
                if (!isDebugTrustedHost(parsed.host)) return null
            }

            // HttpUrl strips userinfo into its own accessors — reject if present.
            if (parsed.username.isNotEmpty() || parsed.password.isNotEmpty()) return null

            if (!isHostAllowed(parsed.host)) return null

            return parsed
        }
    }

    override fun intercept(chain: Interceptor.Chain): okhttp3.Response {
        val originalRequest = chain.request()
        val serverUrl = authPreferences.serverUrl

        if (serverUrl.isNullOrBlank()) {
            // No override configured — leave the placeholder base URL alone.
            // Retrofit will fail naturally if the placeholder is not reachable.
            return chain.proceed(originalRequest)
        }

        // HMAC integrity check — tampering with SharedPreferences by a malicious
        // app or rooted attacker must not silently redirect traffic.
        if (!authPreferences.verifyServerUrlSignature(serverUrl)) {
            if (BuildConfig.DEBUG) {
                Log.e(TAG, "Server URL HMAC verification FAILED — rejecting request")
            }
            throw IOException("Server URL failed integrity check")
        }

        val newBaseUrl = validate(serverUrl) ?: run {
            if (BuildConfig.DEBUG) {
                Log.e(TAG, "Server URL failed validation — rejecting request")
            }
            throw IOException("Configured server URL is not allowed")
        }

        val rewritten = originalRequest.url.newBuilder()
            .scheme(newBaseUrl.scheme)
            .host(newBaseUrl.host)
            .port(newBaseUrl.port)
            .build()

        val newRequest = originalRequest.newBuilder()
            .url(rewritten)
            .build()

        return chain.proceed(newRequest)
    }
}

@Module
@InstallIn(SingletonComponent::class)
object RetrofitClient {

    // Timeouts for regular (UI-driving) requests — must fail fast so the UI
    // can surface errors instead of spinning forever.
    private const val CONNECT_TIMEOUT_SECONDS = 15L
    private const val NORMAL_READ_TIMEOUT_SECONDS = 30L
    private const val NORMAL_WRITE_TIMEOUT_SECONDS = 30L

    // Timeouts for large paginated sync operations — cellular connections
    // routinely need >30s to pull a full sync page, so we relax to 60s.
    private const val SYNC_READ_TIMEOUT_SECONDS = 60L
    private const val SYNC_WRITE_TIMEOUT_SECONDS = 60L

    @Provides
    @Singleton
    fun provideGson(): Gson = GsonBuilder()
        .setLenient()
        // Don't auto-convert field names — we use @SerializedName explicitly where needed
        // This preserves camelCase Kotlin fields while matching snake_case JSON via annotations
        .create()

    @Provides
    @Singleton
    fun provideAuthInterceptor(
        authPreferences: AuthPreferences,
        gson: Gson,
    ): AuthInterceptor = AuthInterceptor(authPreferences, gson)

    @Provides
    @Singleton
    fun provideDynamicBaseUrlInterceptor(
        authPreferences: AuthPreferences,
    ): DynamicBaseUrlInterceptor = DynamicBaseUrlInterceptor(authPreferences)

    /**
     * HTTP logging interceptor. NEVER use Level.BODY — even in DEBUG — because
     * request bodies can contain passwords, 2FA codes, PII and session tokens,
     * and response bodies contain auth tokens. Level.HEADERS with the
     * Authorization header redacted is the upper bound we accept.
     *
     * In RELEASE builds logging is set to NONE so nothing leaks into logcat.
     */
    @Provides
    @Singleton
    fun provideLoggingInterceptor(): HttpLoggingInterceptor {
        return HttpLoggingInterceptor().apply {
            level = if (BuildConfig.DEBUG) {
                HttpLoggingInterceptor.Level.HEADERS
            } else {
                HttpLoggingInterceptor.Level.NONE
            }
            redactHeader("Authorization")
            redactHeader("Cookie")
            redactHeader("Set-Cookie")
            redactHeader("X-API-Key")
        }
    }

    /**
     * Normal OkHttpClient used by every UI-driving API. Short read/write
     * timeouts so errors surface fast.
     */
    @Provides
    @Singleton
    fun provideOkHttpClient(
        dynamicBaseUrlInterceptor: DynamicBaseUrlInterceptor,
        authInterceptor: AuthInterceptor,
        reachabilityInterceptor: ReachabilityReportingInterceptor,
        loggingInterceptor: HttpLoggingInterceptor,
    ): OkHttpClient = buildOkHttpClient(
        dynamicBaseUrlInterceptor = dynamicBaseUrlInterceptor,
        authInterceptor = authInterceptor,
        reachabilityInterceptor = reachabilityInterceptor,
        loggingInterceptor = loggingInterceptor,
        readTimeoutSeconds = NORMAL_READ_TIMEOUT_SECONDS,
        writeTimeoutSeconds = NORMAL_WRITE_TIMEOUT_SECONDS,
    )

    /**
     * OkHttpClient reserved for large paginated sync pulls on slow cellular.
     * Same interceptors, longer read/write timeouts.
     */
    @Provides
    @Singleton
    @SyncHttp
    fun provideSyncOkHttpClient(
        dynamicBaseUrlInterceptor: DynamicBaseUrlInterceptor,
        authInterceptor: AuthInterceptor,
        reachabilityInterceptor: ReachabilityReportingInterceptor,
        loggingInterceptor: HttpLoggingInterceptor,
    ): OkHttpClient = buildOkHttpClient(
        dynamicBaseUrlInterceptor = dynamicBaseUrlInterceptor,
        authInterceptor = authInterceptor,
        reachabilityInterceptor = reachabilityInterceptor,
        loggingInterceptor = loggingInterceptor,
        readTimeoutSeconds = SYNC_READ_TIMEOUT_SECONDS,
        writeTimeoutSeconds = SYNC_WRITE_TIMEOUT_SECONDS,
    )

    private fun buildOkHttpClient(
        dynamicBaseUrlInterceptor: DynamicBaseUrlInterceptor,
        authInterceptor: AuthInterceptor,
        reachabilityInterceptor: ReachabilityReportingInterceptor,
        loggingInterceptor: HttpLoggingInterceptor,
        readTimeoutSeconds: Long,
        writeTimeoutSeconds: Long,
    ): OkHttpClient {
        val builder = OkHttpClient.Builder()
            .addInterceptor(dynamicBaseUrlInterceptor)
            .addInterceptor(authInterceptor)
            .addInterceptor(reachabilityInterceptor)
            .addInterceptor(loggingInterceptor)
            .connectTimeout(CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .readTimeout(readTimeoutSeconds, TimeUnit.SECONDS)
            .writeTimeout(writeTimeoutSeconds, TimeUnit.SECONDS)

        applyTlsConfiguration(builder)
        return builder.build()
    }

    /**
     * Installs the correct TLS configuration for the current build:
     *
     * - DEBUG: allow self-signed certs ONLY for loopback / RFC1918 / emulator
     *   hosts. Production-looking hostnames still go through the normal
     *   platform trust manager.
     * - RELEASE: enforce cert pinning against [CERT_PIN_SHA256_HASHES]. If
     *   pinning is disabled (because pins haven't been filled in yet) we fall
     *   through to the normal platform trust store — which is still safer
     *   than the old trust-all behaviour.
     *
     * On pin failure OkHttp throws SSLPeerUnverifiedException and the
     * request fails CLOSED — we never silently accept an unpinned cert.
     */
    private fun applyTlsConfiguration(builder: OkHttpClient.Builder) {
        if (BuildConfig.DEBUG) {
            configureDebugTls(builder)
            return
        }

        if (ENABLE_CERT_PINNING) {
            val pinnerBuilder = CertificatePinner.Builder()
            CERT_PIN_SHA256_HASHES.forEach { pin ->
                pinnerBuilder.add(PRODUCTION_HOST, pin)
                pinnerBuilder.add("*.$PRODUCTION_HOST", pin)
            }
            builder.certificatePinner(pinnerBuilder.build())
        }
        // else: fall through to platform trust manager (still safe, just no pinning).
    }

    private fun configureDebugTls(builder: OkHttpClient.Builder) {
        try {
            val platform = platformTrustManager()
            val restricted = HostnameRestrictedTrustManager(platform)
            val sslContext = SSLContext.getInstance("TLS")
            sslContext.init(null, arrayOf<TrustManager>(restricted), SecureRandom())
            builder.sslSocketFactory(sslContext.socketFactory, restricted)
            builder.hostnameVerifier(HostnameRestrictedVerifier(restricted))
        } catch (e: CertificateException) {
            Log.e("RetrofitClient", "Failed to configure debug TLS, falling back to platform", e)
        } catch (e: Exception) {
            Log.e("RetrofitClient", "Unexpected error configuring debug TLS", e)
        }
    }

    @Provides
    @Singleton
    fun provideRetrofit(okHttpClient: OkHttpClient, gson: Gson): Retrofit {
        // Use a placeholder base URL — the DynamicBaseUrlInterceptor rewrites it
        return Retrofit.Builder()
            .baseUrl("https://placeholder.invalid/api/v1/")
            .client(okHttpClient)
            .addConverterFactory(GsonConverterFactory.create(gson))
            .build()
    }

    /**
     * Retrofit instance backed by the long-timeout [SyncHttp] OkHttpClient.
     * Inject with the same [SyncHttp] qualifier.
     */
    @Provides
    @Singleton
    @SyncHttp
    fun provideSyncRetrofit(
        @SyncHttp okHttpClient: OkHttpClient,
        gson: Gson,
    ): Retrofit {
        return Retrofit.Builder()
            .baseUrl("https://placeholder.invalid/api/v1/")
            .client(okHttpClient)
            .addConverterFactory(GsonConverterFactory.create(gson))
            .build()
    }

    // --- API interface providers ---
    @Provides @Singleton fun provideAuthApi(retrofit: Retrofit): AuthApi = retrofit.create(AuthApi::class.java)
    @Provides @Singleton fun provideTicketApi(retrofit: Retrofit): TicketApi = retrofit.create(TicketApi::class.java)
    @Provides @Singleton fun provideCustomerApi(retrofit: Retrofit): CustomerApi = retrofit.create(CustomerApi::class.java)
    @Provides @Singleton fun provideInventoryApi(retrofit: Retrofit): InventoryApi = retrofit.create(InventoryApi::class.java)
    @Provides @Singleton fun provideInvoiceApi(retrofit: Retrofit): InvoiceApi = retrofit.create(InvoiceApi::class.java)
    @Provides @Singleton fun provideSmsApi(retrofit: Retrofit): SmsApi = retrofit.create(SmsApi::class.java)
    @Provides @Singleton fun provideSearchApi(retrofit: Retrofit): SearchApi = retrofit.create(SearchApi::class.java)
    @Provides @Singleton fun provideNotificationApi(retrofit: Retrofit): NotificationApi = retrofit.create(NotificationApi::class.java)
    @Provides @Singleton fun provideReportApi(retrofit: Retrofit): ReportApi = retrofit.create(ReportApi::class.java)
    @Provides @Singleton fun provideSettingsApi(retrofit: Retrofit): SettingsApi = retrofit.create(SettingsApi::class.java)
    @Provides @Singleton fun provideCatalogApi(retrofit: Retrofit): CatalogApi = retrofit.create(CatalogApi::class.java)
    @Provides @Singleton fun provideRepairPricingApi(retrofit: Retrofit): RepairPricingApi = retrofit.create(RepairPricingApi::class.java)
    @Provides @Singleton fun provideLeadApi(retrofit: Retrofit): LeadApi = retrofit.create(LeadApi::class.java)
    @Provides @Singleton fun provideEstimateApi(retrofit: Retrofit): EstimateApi = retrofit.create(EstimateApi::class.java)
    @Provides @Singleton fun provideExpenseApi(retrofit: Retrofit): ExpenseApi = retrofit.create(ExpenseApi::class.java)
}
