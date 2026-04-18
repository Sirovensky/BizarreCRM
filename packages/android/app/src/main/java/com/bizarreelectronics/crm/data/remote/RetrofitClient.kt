package com.bizarreelectronics.crm.data.remote

import android.util.Log
import com.bizarreelectronics.crm.BuildConfig
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.*
import com.bizarreelectronics.crm.data.remote.interceptors.AuthInterceptor
import com.bizarreelectronics.crm.data.remote.interceptors.OriginHeaderInterceptor
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
// CERTIFICATE PINNING — REPLACE PLACEHOLDER PINS BEFORE RELEASE
// ============================================================================
// CERT_PIN_SHA256_HASHES
//
// These pins MUST be replaced with the real production certificate SPKI hashes
// before cutting a release build. Both a primary pin AND a backup pin are
// required so that cert rotation does not brick every installed app.
//
// TODO: replace PRIMARY_LEAF_PIN_REPLACE_ME and BACKUP_LEAF_PIN_REPLACE_ME
// with actual pins from your cert chain before the first production release.
// Use:
//
//   openssl s_client -connect your-domain:443 \
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
// ENABLE_CERT_PINNING is now TRUE — release builds reject any cert that does
// not match one of these pins. Until the placeholder values are replaced with
// real pins, release builds will FAIL to talk to the server (which is the
// correct failure mode — better to notice during release QA than ship with
// pinning silently disabled).
//
// Debug builds bypass this entirely via [applyTlsConfiguration] / BuildConfig.DEBUG
// and keep using the platform trust manager + LAN escape hatch.
// ============================================================================
private const val ENABLE_CERT_PINNING: Boolean = true
private val CERT_PIN_SHA256_HASHES: List<String> = listOf(
    // AUD-20260414-H4: real pins for *.bizarrecrm.com captured 2026-04-17.
    //
    // Primary: SPKI SHA-256 of the current *.bizarrecrm.com leaf cert issued
    // by Let's Encrypt R12. This is the cert the Android app is hitting in
    // production today. When LE rotates the leaf (every ~60 days) this pin
    // will stop matching — at that point the intermediate pin below kicks in
    // and keeps traffic flowing while we refresh this value. Rotation schedule
    // is documented in docs/cert-rotation.md.
    "sha256/Sq2Z/TGcxkzGSGSSB14lHIHz1cAkWSJtRXE21tbddVA=",
    // Backup: SPKI SHA-256 of the Let's Encrypt R12 intermediate. Valid
    // until 2027-03-12. Matches any LE-issued leaf under R12 so the app
    // keeps working across leaf rotations. Add R10/R11/R13 here too once
    // we confirm our ACME client rotates between them.
    "sha256/kZwN96eHtZftBWrOZUsd6cA4es80n3NzSk/XtYz2EqQ=",
)

/** The production hostname the release client is expected to talk to. */
private val PRODUCTION_HOST: String = BuildConfig.BASE_DOMAIN.lowercase()

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
 * X509TrustManager that delegates to the platform default trust manager and
 * only falls back to "trust the chain" if the delegate rejects AND the peer's
 * SNI/CommonName looks like a debug-allowed host.
 *
 * @audit-fixed: Section 33 / D11 — the previous implementation kept a single
 * `@Volatile var currentHostname` that the [HostnameRestrictedVerifier] wrote
 * to before each `checkServerTrusted` call. With multiple in-flight requests
 * to different hosts on the same OkHttpClient, the volatile read/write was a
 * straight-up data race: a request to the production host could land in
 * checkServerTrusted while a sibling request to 192.168.1.10 had just
 * overwritten the field, causing the production cert to be skipped. The new
 * implementation has no shared mutable state. The trust manager always tries
 * the platform check first; only if it throws AND the cert chain is empty or
 * the leaf cert's CN/SAN matches a debug-trusted host does it accept the
 * chain. The hostname comes out of the cert itself, not out of an interceptor
 * field, so concurrent requests cannot influence each other.
 */
private class HostnameRestrictedTrustManager(
    private val delegate: X509TrustManager,
) : X509TrustManager {

    override fun checkClientTrusted(chain: Array<out X509Certificate>, authType: String) {
        delegate.checkClientTrusted(chain, authType)
    }

    override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String) {
        try {
            delegate.checkServerTrusted(chain, authType)
            return
        } catch (e: CertificateException) {
            // Platform rejected the chain. Fall through to the debug-only escape
            // hatch IF the certificate identifies itself as a LAN host. The
            // hostname is read off the leaf certificate (CN + SubjectAltName),
            // not off any interceptor-mutated field, so this is race-free.
            if (chain.isEmpty()) throw e
            val leaf = chain[0]
            val identifiers = certificateHostnames(leaf)
            if (identifiers.any { isDebugTrustedHost(it) }) {
                return
            }
            throw e
        }
    }

    override fun getAcceptedIssuers(): Array<X509Certificate> = delegate.acceptedIssuers

    /**
     * Extracts every hostname-like identifier from a leaf cert: the CN of the
     * subject DN, plus any SubjectAlternativeName entries of type dNSName (2)
     * and iPAddress (7). Used to test the cert against [isDebugTrustedHost]
     * without relying on connection-level state.
     */
    private fun certificateHostnames(cert: X509Certificate): List<String> {
        val out = mutableListOf<String>()
        // Common Name from the subject DN. The format is
        // "CN=foo.example.com, OU=…", so a coarse split is enough for our use.
        val dn = cert.subjectX500Principal.name
        Regex("CN=([^,]+)").find(dn)?.groupValues?.getOrNull(1)?.let { out += it }
        // SubjectAltName entries — type 2 = dNSName, type 7 = iPAddress.
        runCatching {
            cert.subjectAlternativeNames?.forEach { entry ->
                val type = entry.getOrNull(0) as? Int ?: return@forEach
                val value = entry.getOrNull(1) as? String ?: return@forEach
                if (type == 2 || type == 7) out += value
            }
        }
        return out
    }
}

/**
 * HostnameVerifier counterpart of [HostnameRestrictedTrustManager]. Accepts
 * any hostname on the debug allow-list and falls back to the platform default
 * for everything else.
 *
 * @audit-fixed: Section 33 / D11 — the previous version wrote `hostname` into
 * a volatile field on the trust manager before delegating; concurrent requests
 * to different hosts could interleave the writes. The new version is
 * stateless: it just checks the hostname against the allow-list and otherwise
 * delegates to the platform verifier.
 */
private class HostnameRestrictedVerifier : HostnameVerifier {
    private val default = javax.net.ssl.HttpsURLConnection.getDefaultHostnameVerifier()
    override fun verify(hostname: String?, session: javax.net.ssl.SSLSession?): Boolean {
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
         *   - Production host itself
         *   - Any subdomain of it
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
    private const val NORMAL_CALL_TIMEOUT_SECONDS = 45L

    // Timeouts for large paginated sync operations — cellular connections
    // routinely need >30s to pull a full sync page, so we relax to 60s.
    private const val SYNC_READ_TIMEOUT_SECONDS = 60L
    private const val SYNC_WRITE_TIMEOUT_SECONDS = 60L
    private const val SYNC_CALL_TIMEOUT_SECONDS = 90L

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
    fun provideOriginHeaderInterceptor(): OriginHeaderInterceptor = OriginHeaderInterceptor()

    @Provides
    @Singleton
    fun provideOkHttpClient(
        dynamicBaseUrlInterceptor: DynamicBaseUrlInterceptor,
        authInterceptor: AuthInterceptor,
        reachabilityInterceptor: ReachabilityReportingInterceptor,
        originHeaderInterceptor: OriginHeaderInterceptor,
        loggingInterceptor: HttpLoggingInterceptor,
    ): OkHttpClient = buildOkHttpClient(
        dynamicBaseUrlInterceptor = dynamicBaseUrlInterceptor,
        authInterceptor = authInterceptor,
        reachabilityInterceptor = reachabilityInterceptor,
        originHeaderInterceptor = originHeaderInterceptor,
        loggingInterceptor = loggingInterceptor,
        readTimeoutSeconds = NORMAL_READ_TIMEOUT_SECONDS,
        writeTimeoutSeconds = NORMAL_WRITE_TIMEOUT_SECONDS,
        callTimeoutSeconds = NORMAL_CALL_TIMEOUT_SECONDS,
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
        originHeaderInterceptor: OriginHeaderInterceptor,
        loggingInterceptor: HttpLoggingInterceptor,
    ): OkHttpClient = buildOkHttpClient(
        dynamicBaseUrlInterceptor = dynamicBaseUrlInterceptor,
        authInterceptor = authInterceptor,
        reachabilityInterceptor = reachabilityInterceptor,
        originHeaderInterceptor = originHeaderInterceptor,
        loggingInterceptor = loggingInterceptor,
        readTimeoutSeconds = SYNC_READ_TIMEOUT_SECONDS,
        writeTimeoutSeconds = SYNC_WRITE_TIMEOUT_SECONDS,
        callTimeoutSeconds = SYNC_CALL_TIMEOUT_SECONDS,
    )

    private fun buildOkHttpClient(
        dynamicBaseUrlInterceptor: DynamicBaseUrlInterceptor,
        authInterceptor: AuthInterceptor,
        reachabilityInterceptor: ReachabilityReportingInterceptor,
        originHeaderInterceptor: OriginHeaderInterceptor,
        loggingInterceptor: HttpLoggingInterceptor,
        readTimeoutSeconds: Long,
        writeTimeoutSeconds: Long,
        callTimeoutSeconds: Long,
    ): OkHttpClient {
        val builder = OkHttpClient.Builder()
            .addInterceptor(dynamicBaseUrlInterceptor)
            .addInterceptor(originHeaderInterceptor)
            .addInterceptor(authInterceptor)
            .addInterceptor(reachabilityInterceptor)
            .addInterceptor(loggingInterceptor)
            .connectTimeout(CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .readTimeout(readTimeoutSeconds, TimeUnit.SECONDS)
            .writeTimeout(writeTimeoutSeconds, TimeUnit.SECONDS)
            .callTimeout(callTimeoutSeconds, TimeUnit.SECONDS)

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
            // @audit-fixed: D11 — the verifier no longer mutates trust-manager
            // state, so it takes no constructor argument.
            builder.hostnameVerifier(HostnameRestrictedVerifier())
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
