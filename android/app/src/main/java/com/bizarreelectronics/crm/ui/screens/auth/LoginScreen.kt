package com.bizarreelectronics.crm.ui.screens.auth

import android.graphics.BitmapFactory
import android.util.Base64
import androidx.compose.animation.*
import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.ui.components.WaveDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandPrimaryButton
import com.bizarreelectronics.crm.ui.theme.BrandMono
import com.bizarreelectronics.crm.ui.theme.LocalExtendedColors
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.data.remote.dto.*
import com.bizarreelectronics.crm.util.NetworkMonitor
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import com.bizarreelectronics.crm.BuildConfig
import java.net.ConnectException
import java.net.Inet4Address
import java.net.InetAddress
import java.net.UnknownHostException
import java.security.SecureRandom
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager

// ─── State ──────────────────────────────────────────────────────────

enum class SetupStep { SERVER, REGISTER, CREDENTIALS, SET_PASSWORD, TWO_FA_SETUP, TWO_FA_VERIFY }

private val CLOUD_DOMAIN = BuildConfig.BASE_DOMAIN.lowercase()

data class LoginUiState(
    val step: SetupStep = SetupStep.SERVER,
    val serverUrl: String = "",
    val shopSlug: String = "",
    val useCustomServer: Boolean = false,
    val storeName: String = "",
    val username: String = "",
    val password: String = "",
    val newPassword: String = "",
    val confirmPassword: String = "",
    val totpCode: String = "",
    val challengeToken: String = "",
    val qrCodeDataUrl: String = "",
    val isLoading: Boolean = false,
    val error: String? = null,
    val serverConnected: Boolean = false,
    val showBackupCodes: List<String>? = null,
    // §2.1 — setup-status probe result. Null = not yet probed or probe skipped.
    // true = server needs first-run setup; false = server is ready for login.
    // Probe failure is non-blocking: login form still renders if null.
    val setupNeeded: Boolean? = null,
    // §2.1 — probe is in flight (transparent overlay)
    val isProbing: Boolean = false,
    // §2.1 — probe error message (inline retry on credentials step)
    val probeError: String? = null,
    // §2.12-L356 — true when a login attempt fails because the host was unreachable
    // (UnknownHostException / ConnectException). Shows inline error + Retry CTA.
    val unreachableHost: Boolean = false,
    // §2.12-L357 — true when the server returned 429 Too Many Requests.
    // rateLimitResetMs is the System.currentTimeMillis() at which the wait expires.
    val rateLimited: Boolean = false,
    val rateLimitResetMs: Long? = null,
    // §2.12-L358 — mirrors NetworkMonitor.isOnline; true when device has no network.
    // Auth is online-only: this banner is informational only, cannot be bypassed.
    val networkOffline: Boolean = false,
    // §2.13-L366 — wall-clock expiry for the challenge token issued by the server.
    // Set to System.currentTimeMillis() + 600_000 when a challengeToken is received.
    // Null on the CREDENTIALS step (no active challenge token yet).
    val challengeTokenExpiresAtMs: Long? = null,
    // §2.13-L366 — true once the LaunchedEffect ticker determines the challenge token
    // has expired. Resets to false when the user restarts login (step → CREDENTIALS).
    val challengeExpired: Boolean = false,
    // Registration fields
    val registerShopName: String = "",
    val registerEmail: String = "",
    val registerPassword: String = "",
    // §2.7-L328 — timezone chosen during registration (pre-filled from device)
    val registerTimezone: String = java.time.ZoneId.systemDefault().id,
    // §2.7-L329 — shop type chosen during registration
    val registerShopType: String = "repair",
)

// ─── ViewModel ──────────────────────────────────────────────────────

@HiltViewModel
class LoginViewModel @Inject constructor(
    private val authPreferences: AuthPreferences,
    private val authApi: AuthApi,
    private val networkMonitor: NetworkMonitor,
) : ViewModel() {

    companion object {
        private fun extractSlugFromUrl(url: String?): String {
            if (url.isNullOrBlank()) return ""
            val host = url.removePrefix("https://").removePrefix("http://").split("/").firstOrNull() ?: return ""
            if (host.endsWith(".$CLOUD_DOMAIN")) return host.removeSuffix(".$CLOUD_DOMAIN")
            return ""
        }

        private fun isCloudUrl(url: String?): Boolean {
            if (url.isNullOrBlank()) return true
            return url.contains(CLOUD_DOMAIN)
        }

        // AUDIT-AND-002: LAN-host predicate mirroring RetrofitClient.isDebugTrustedHost.
        // Returns true only for loopback literals and RFC1918 private IPv4 addresses.
        // Used to gate the debug-only TLS bypass in the server-probe and register clients.
        private val DEBUG_LOOPBACK_HOSTS: Set<String> = setOf(
            "localhost", "10.0.2.2", "10.0.3.2", "127.0.0.1", "::1",
        )

        private fun isLanHost(hostname: String?): Boolean {
            if (hostname.isNullOrBlank()) return false
            val h = hostname.lowercase()
            if (h in DEBUG_LOOPBACK_HOSTS) return true
            return try {
                val addr: InetAddress = InetAddress.getByName(h)
                if (addr !is Inet4Address) false
                else {
                    val b = addr.address
                    val b0 = b[0].toInt() and 0xff
                    val b1 = b[1].toInt() and 0xff
                    b0 == 10 || (b0 == 172 && b1 in 16..31) || (b0 == 192 && b1 == 168)
                }
            } catch (_: Exception) { false }
        }

        /**
         * Builds an OkHttpClient.Builder with TLS configured to match RetrofitClient policy:
         * - DEBUG + LAN host → hostname-restricted trust-all (self-signed cert accepted)
         * - Everything else (release OR public host) → platform default CA + hostname verifier
         *
         * AUDIT-AND-002: replaces the unconditional trust-all used by the server-probe
         * and register-shop clients in LoginScreen. Public cloud hostnames always get
         * proper CA validation even in debug.
         */
        fun buildProbeTlsClient(targetHost: String): OkHttpClient.Builder {
            val builder = OkHttpClient.Builder()
            if (BuildConfig.DEBUG && isLanHost(targetHost)) {
                // LAN dev server with a self-signed cert — permit trust-all for this
                // host only. Cloud hostnames deliberately fall through to the platform
                // trust manager so credentials are never sent over an untrusted chain.
                try {
                    val tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
                    tmf.init(null as java.security.KeyStore?)
                    val platformTm = tmf.trustManagers.filterIsInstance<X509TrustManager>().first()

                    val lanTrustAll = object : X509TrustManager {
                        override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) =
                            platformTm.checkClientTrusted(chain, authType)
                        override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {
                            try { platformTm.checkServerTrusted(chain, authType) }
                            catch (_: CertificateException) { /* accept self-signed on LAN */ }
                        }
                        override fun getAcceptedIssuers(): Array<X509Certificate> = platformTm.acceptedIssuers
                    }
                    val sslCtx = SSLContext.getInstance("TLS")
                    sslCtx.init(null, arrayOf<TrustManager>(lanTrustAll), SecureRandom())
                    builder.sslSocketFactory(sslCtx.socketFactory, lanTrustAll)
                    builder.hostnameVerifier { hn, session ->
                        isLanHost(hn) || HttpsURLConnection.getDefaultHostnameVerifier().verify(hn, session)
                    }
                } catch (_: Exception) { /* fall through to platform defaults */ }
            }
            // else: no sslSocketFactory/hostnameVerifier set → OkHttp uses platform defaults
            return builder
        }
    }

    private val _state = MutableStateFlow(LoginUiState(
        serverUrl = authPreferences.serverUrl ?: "",
        shopSlug = extractSlugFromUrl(authPreferences.serverUrl),
        useCustomServer = !isCloudUrl(authPreferences.serverUrl),
        step = if (authPreferences.serverUrl.isNullOrBlank()) SetupStep.SERVER else SetupStep.CREDENTIALS,
        // §2.17 — pre-fill the username from the last successful login so the
        // user only has to tap the Password field. Never pre-fills the
        // password field (that stays biometric-gated) and never surfaces
        // storage beyond the already-saved `username` in AuthPreferences, so
        // no new persistence keys are introduced.
        username = authPreferences.username.orEmpty(),
    ))
    val state = _state.asStateFlow()

    init {
        // §2.12-L358 — observe device network state and mirror it into uiState.
        // This is purely informational: the offline banner cannot be bypassed
        // because login always requires a real network round-trip.
        viewModelScope.launch {
            networkMonitor.isOnline.collect { online ->
                _state.value = _state.value.copy(networkOffline = !online)
            }
        }
    }

    // AND-033: Cache the probe OkHttpClient per target host so repeated probes
    // (retry, reconnect) to the same server do not allocate a new client each
    // time. A new client is built only when the host changes.
    @Volatile private var _probeClientHost: String = ""
    @Volatile private var _probeClient: OkHttpClient? = null

    /** Returns a cached [OkHttpClient] for [targetHost], rebuilding if the host changed.
     *  Timeouts are set conservatively to cover both the server-probe (10s connect)
     *  and the registration call (15s connect / 30s call). */
    private fun probeClientFor(targetHost: String): OkHttpClient {
        if (_probeClient != null && _probeClientHost == targetHost) {
            return _probeClient!!
        }
        val client = buildProbeTlsClient(targetHost)
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(15, TimeUnit.SECONDS)
            .writeTimeout(15, TimeUnit.SECONDS)
            .callTimeout(30, TimeUnit.SECONDS)
            .build()
        _probeClient?.connectionPool?.evictAll()
        _probeClientHost = targetHost
        _probeClient = client
        return client
    }

    override fun onCleared() {
        super.onCleared()
        _probeClient?.dispatcher?.executorService?.shutdown()
        _probeClient?.connectionPool?.evictAll()
        _probeClient = null
    }

    fun updateServerUrl(value: String) { _state.value = _state.value.copy(serverUrl = value, error = null, serverConnected = false) }
    fun updateShopSlug(value: String) {
        val filtered = value.lowercase().filter { it.isLetterOrDigit() || it == '-' }.take(30)
        _state.value = _state.value.copy(shopSlug = filtered, error = null, serverConnected = false)
    }
    fun toggleCustomServer() { _state.value = _state.value.copy(useCustomServer = !_state.value.useCustomServer, error = null) }
    fun goToRegister() { _state.value = _state.value.copy(step = SetupStep.REGISTER, error = null) }
    fun updateRegisterShopName(value: String) { _state.value = _state.value.copy(registerShopName = value, error = null) }
    fun updateRegisterEmail(value: String) { _state.value = _state.value.copy(registerEmail = value, error = null) }
    fun updateRegisterPassword(value: String) { _state.value = _state.value.copy(registerPassword = value, error = null) }
    fun updateRegisterTimezone(value: String) { _state.value = _state.value.copy(registerTimezone = value, error = null) }
    fun updateRegisterShopType(value: String) { _state.value = _state.value.copy(registerShopType = value, error = null) }
    fun updateUsername(value: String) {
        _state.value = _state.value.copy(username = value, error = null, unreachableHost = false, rateLimited = false)
    }
    fun updatePassword(value: String) {
        _state.value = _state.value.copy(password = value, error = null, unreachableHost = false, rateLimited = false)
    }
    fun updateNewPassword(value: String) { _state.value = _state.value.copy(newPassword = value, error = null) }
    fun updateConfirmPassword(value: String) { _state.value = _state.value.copy(confirmPassword = value, error = null) }
    fun updateTotpCode(value: String) {
        if (value.length <= 6 && value.all { it.isDigit() }) {
            _state.value = _state.value.copy(totpCode = value, error = null)
        }
    }

    fun goBack() {
        val current = _state.value
        _state.value = current.copy(
            error = null,
            step = when (current.step) {
                SetupStep.REGISTER -> SetupStep.SERVER
                SetupStep.CREDENTIALS -> SetupStep.SERVER
                SetupStep.SET_PASSWORD -> SetupStep.CREDENTIALS
                SetupStep.TWO_FA_SETUP -> SetupStep.CREDENTIALS
                SetupStep.TWO_FA_VERIFY -> SetupStep.CREDENTIALS
                else -> current.step
            },
        )
    }

    /** Step 1: Test connection to server */
    fun connectToServer() {
        val s = _state.value
        val url: String

        if (s.useCustomServer) {
            url = s.serverUrl.trimEnd('/')
            if (url.isBlank()) { _state.value = s.copy(error = "Server URL is required"); return }
        } else {
            val slug = s.shopSlug.trim()
            if (slug.isBlank()) { _state.value = s.copy(error = "Enter your shop name"); return }
            if (slug.length < 3) { _state.value = s.copy(error = "Shop name must be at least 3 characters"); return }
            url = "https://${slug}.$CLOUD_DOMAIN"
        }

        _state.value = s.copy(isLoading = true, error = null)
        viewModelScope.launch {
            try {
                val result = withContext(Dispatchers.IO) {
                    // AUDIT-AND-002: use hostname-restricted TLS — trust-all only for LAN
                    // hosts in DEBUG; cloud/public hostnames always use platform CA + verifier.
                    // AND-033: reuse cached probe client via probeClientFor() to avoid
                    // allocating a new OkHttpClient on every probe call.
                    val targetHost = url.removePrefix("https://").removePrefix("http://")
                        .split("/").first().split(":").first()
                    val client = probeClientFor(targetHost)
                    val request = Request.Builder()
                        .url("$url/api/v1/portal/embed/config")
                        .header("Origin", url)
                        .build()
                    val response = client.newCall(request).execute()
                    // SEC-M19 interplay: /portal/embed/config returns 404 when
                    // the tenant hasn't opted into widget mode (or doesn't
                    // exist). Either way, a 404 from this path ALSO means the
                    // server is reachable and responding with JSON — which is
                    // all the connect-probe needs. Treat 404 as a reachable-
                    // but-nameless state so login isn't blocked on tenants
                    // that correctly disable portal_embed_enabled by default.
                    // Other failures (5xx, timeout, HTML from a wrong host)
                    // still propagate so the user sees a real error.
                    val storeName: String = when {
                        response.isSuccessful -> {
                            val body = response.body?.string() ?: throw Exception("Empty response")
                            val json = JSONObject(body)
                            json.optJSONObject("data")?.optString("name") ?: "CRM Server"
                        }
                        response.code == 404 -> "CRM Server"
                        else -> throw Exception("Server returned ${response.code}")
                    }
                    storeName
                }

                // AUDIT-AND-008: do NOT persist serverUrl/storeName here.
                // The probe only confirms the host is a CRM server; credentials
                // have not been verified yet. Persistence happens in login() and
                // verify2FA() once credentials are confirmed.

                _state.value = _state.value.copy(
                    isLoading = false,
                    serverConnected = true,
                    serverUrl = url,
                    storeName = result,
                    step = SetupStep.CREDENTIALS,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = if (_state.value.useCustomServer) "Could not connect: ${e.message}"
                            else "Shop not found. Check the name and try again.",
                )
            }
        }
    }

    /** Register a new shop on BizarreCRM cloud */
    fun registerShop() {
        val s = _state.value
        val slug = s.shopSlug.trim()
        if (slug.isBlank() || slug.length < 3) { _state.value = s.copy(error = "Shop URL must be at least 3 characters"); return }
        if (s.registerShopName.isBlank()) { _state.value = s.copy(error = "Shop name is required"); return }
        if (s.registerEmail.isBlank()) { _state.value = s.copy(error = "Email is required"); return }
        if (s.registerPassword.length < 8) { _state.value = s.copy(error = "Password must be at least 8 characters"); return }

        _state.value = s.copy(isLoading = true, error = null)
        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    // AUDIT-AND-002: registration always targets the cloud domain (public host);
                    // buildProbeTlsClient returns platform defaults for any non-LAN hostname,
                    // so user credentials are always sent over a properly verified TLS channel.
                    // AND-033: reuse cached probe client; CLOUD_DOMAIN host is constant here.
                    val client = probeClientFor(CLOUD_DOMAIN)
                    val json = JSONObject().apply {
                        put("slug", slug)
                        put("shop_name", s.registerShopName.trim())
                        put("admin_email", s.registerEmail.trim())
                        put("admin_password", s.registerPassword)
                        // §2.7-L328 — timezone (optional; server ignores unknown fields)
                        put("timezone", s.registerTimezone)
                        // §2.7-L329 — shop type (optional)
                        put("shop_type", s.registerShopType)
                    }
                    val requestBody = json.toString().toRequestBody("application/json".toMediaType())
                    val request = Request.Builder()
                        .url("https://$CLOUD_DOMAIN/api/v1/signup")
                        .header("Origin", "https://$CLOUD_DOMAIN")
                        .post(requestBody)
                        .build()
                    val response = client.newCall(request).execute()
                    val body = response.body?.string() ?: throw Exception("Empty response")
                    val responseJson = JSONObject(body)

                    if (!response.isSuccessful || !responseJson.optBoolean("success", false)) {
                        throw Exception(responseJson.optString("message", "Registration failed"))
                    }
                }

                // Registration successful — auto-connect to the new shop
                val newUrl = "https://${slug}.$CLOUD_DOMAIN"
                authPreferences.serverUrl = newUrl
                authPreferences.storeName = s.registerShopName.trim()

                _state.value = _state.value.copy(
                    isLoading = false,
                    serverConnected = true,
                    storeName = s.registerShopName.trim(),
                    step = SetupStep.CREDENTIALS,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = e.message ?: "Registration failed",
                )
            }
        }
    }

    /**
     * §2.1 — Setup-status probe.
     *
     * Called once when the CREDENTIALS step is first shown (after server connection
     * is established). Fires the GET /auth/setup-status endpoint and updates state:
     *
     *   - needsSetup=true  → sets setupNeeded=true so the UI shows a "server needs
     *                         setup" banner with a "Contact admin" message. The login
     *                         form is NOT blocked — user can still attempt a login if
     *                         they dismiss the banner.
     *   - needsSetup=false → sets setupNeeded=false (normal flow, banner hidden).
     *   - Network/parse failure → clears isProbing, sets probeError with inline retry
     *                             copy. Login form is NOT blocked.
     *
     * isMultiTenant=true is noted in probeError as a TODO since the tenant-picker
     * screen does not exist yet.
     *
     * SAFETY: probe failure is deliberately non-blocking. The user can always try
     * to sign in regardless of probe result (they may be on a degraded network).
     */
    fun probeSetupStatus(forceRetry: Boolean = false) {
        val s = _state.value
        // Skip if already probed this session (unless explicitly retrying after error)
        // or if no server URL yet.
        if ((!forceRetry && s.setupNeeded != null) || s.serverUrl.isBlank()) return
        // Reset prior result/error before starting a new probe so UI shows spinner.
        _state.value = s.copy(isProbing = true, probeError = null, setupNeeded = null)
        viewModelScope.launch {
            try {
                val response = authApi.getSetupStatus()
                val data = response.data
                if (data == null) {
                    // Unexpected null body — treat as non-blocking probe failure
                    _state.value = _state.value.copy(
                        isProbing = false,
                        probeError = null,
                        setupNeeded = false,
                    )
                    return@launch
                }
                // TODO(§2.10): when data.isMultiTenant == true and no tenant is chosen,
                // push the tenant-picker screen. Tenant picker doesn't exist yet.
                _state.value = _state.value.copy(
                    isProbing = false,
                    setupNeeded = data.needsSetup,
                    probeError = null,
                )
            } catch (e: Exception) {
                // Non-blocking: probe failure is silent. The probe's only user-visible
                // purpose is surfacing needsSetup=true (a different banner). A network
                // blip or first-run miss must NOT show an error — the login form is
                // fully functional regardless of probe result.
                timber.log.Timber.w(e, "setup-status probe failed silently (non-blocking)")
                _state.value = _state.value.copy(
                    isProbing = false,
                    probeError = null,
                )
            }
        }
    }

    /** Step 2: Login with credentials */
    fun login() {
        val s = _state.value
        if (s.username.isBlank()) { _state.value = s.copy(error = "Username is required"); return }
        if (s.password.isBlank()) { _state.value = s.copy(error = "Password is required"); return }

        // Clear any stale probe/unreachable state from a previous attempt so
        // a successful login never leaves a misleading error banner visible.
        _state.value = s.copy(isLoading = true, error = null, probeError = null, unreachableHost = false)
        viewModelScope.launch {
            try {
                // AUDIT-AND-008: commit serverUrl only when the user submits credentials,
                // not on probe-success. This is the earliest point at which credentials
                // are being sent, so the URL has been validated as a real CRM host.
                authPreferences.serverUrl = s.serverUrl

                val response = authApi.login(LoginRequest(s.username.trim(), s.password))
                val data = response.data ?: throw Exception(response.message ?: "Login failed")

                val challengeToken = data.challengeToken ?: throw Exception("No challenge token received")

                // §2.13-L366: record expiry deadline at the moment the challenge token
                // is received. The 10-minute window matches the server-side TTL so the
                // client proactively resets the flow before the server returns a silent 401.
                val expiresAt = System.currentTimeMillis() + 600_000L
                when {
                    data.requiresPasswordSetup == true -> {
                        _state.value = _state.value.copy(
                            isLoading = false,
                            challengeToken = challengeToken,
                            challengeTokenExpiresAtMs = expiresAt,
                            challengeExpired = false,
                            step = SetupStep.SET_PASSWORD,
                        )
                    }
                    data.requires2faSetup == true || data.totpEnabled != true -> {
                        // Need to set up 2FA first — setup2FA will update expiresAt when
                        // it receives its own fresh challengeToken from the server.
                        setup2FA(challengeToken, expiresAt)
                    }
                    else -> {
                        // 2FA already set up, just need code
                        _state.value = _state.value.copy(
                            isLoading = false,
                            challengeToken = challengeToken,
                            challengeTokenExpiresAtMs = expiresAt,
                            challengeExpired = false,
                            step = SetupStep.TWO_FA_VERIFY,
                        )
                    }
                }
            } catch (e: Exception) {
                // §2.12-L357: 429 Too Many Requests → rate-limit countdown.
                // Prefer Retry-After header if present; otherwise default to 60s.
                // Avoid touching AuthApi.kt (Wave-7G scope) — no signature change.
                if (e is retrofit2.HttpException && e.code() == 429) {
                    val retryAfterSec: Long = try {
                        e.response()?.headers()?.get("Retry-After")?.toLong() ?: 60L
                    } catch (_: NumberFormatException) { 60L }
                    val resetAt = System.currentTimeMillis() + retryAfterSec * 1000L
                    _state.value = _state.value.copy(
                        isLoading = false,
                        rateLimited = true,
                        rateLimitResetMs = resetAt,
                        error = null,
                    )
                    return@launch
                }
                // §2.12-L356: host unreachable (bad URL / no route to server).
                if (e is UnknownHostException || e is ConnectException ||
                    (e.cause is UnknownHostException) || (e.cause is ConnectException)) {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        unreachableHost = true,
                        error = null,
                    )
                    return@launch
                }
                val errorMsg = extractErrorMessage(e)
                _state.value = _state.value.copy(
                    isLoading = false,
                    unreachableHost = false,
                    rateLimited = false,
                    error = errorMsg,
                )
            }
        }
    }

    /** Step 2b: Set password for first-time users */
    fun setPassword() {
        val s = _state.value
        if (s.newPassword.length < 8) { _state.value = s.copy(error = "Password must be at least 8 characters"); return }
        if (s.newPassword != s.confirmPassword) { _state.value = s.copy(error = "Passwords don't match"); return }

        _state.value = s.copy(isLoading = true, error = null)
        viewModelScope.launch {
            try {
                val response = authApi.setPassword(SetPasswordRequest(s.challengeToken, s.newPassword))
                val data = response.data ?: throw Exception(response.message ?: "Failed to set password")
                val newChallenge = data.challengeToken ?: throw Exception("No challenge token")
                // §2.13-L366: password-set gives us a new challengeToken; start a fresh
                // 10-minute window for the subsequent 2FA setup step.
                val freshExpiresAt = System.currentTimeMillis() + 600_000L

                // Password set, now set up 2FA
                setup2FA(newChallenge, freshExpiresAt)
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false, error = extractErrorMessage(e))
            }
        }
    }

    /**
     * Step 3a: Request 2FA QR code.
     *
     * [inheritedExpiresAt] is the expiry deadline inherited from the calling step.
     * If the server returns a fresh challengeToken we keep the same window (the
     * server still honours the original token's TTL). Pass null to use a fresh
     * 10-minute window from now (e.g. when called from setPassword which already
     * has an updated token).
     */
    private fun setup2FA(challengeToken: String, inheritedExpiresAt: Long? = null) {
        viewModelScope.launch {
            try {
                val response = authApi.setup2FA(mapOf("challengeToken" to challengeToken))
                val data = response.data ?: throw Exception("Failed to set up 2FA")
                // Server returns { qr: "data:image/png;base64,...", secret: "...", challengeToken: "..." }
                val qrCode = data.qrCode ?: data.qr ?: ""
                val newChallenge = data.challengeToken ?: challengeToken
                // §2.13-L366: preserve the expiry window started at login(), or start a
                // fresh one if called without a prior window (e.g. from setPassword path).
                val expiresAt = inheritedExpiresAt ?: (System.currentTimeMillis() + 600_000L)
                _state.value = _state.value.copy(
                    isLoading = false,
                    challengeToken = newChallenge,
                    challengeTokenExpiresAtMs = expiresAt,
                    challengeExpired = false,
                    qrCodeDataUrl = qrCode,
                    step = SetupStep.TWO_FA_SETUP,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false, error = extractErrorMessage(e))
            }
        }
    }

    /** Step 3: Verify TOTP code */
    fun verify2FA(onSuccess: () -> Unit) {
        val s = _state.value
        if (s.totpCode.length != 6) { _state.value = s.copy(error = "Enter a 6-digit code"); return }

        _state.value = s.copy(isLoading = true, error = null)
        viewModelScope.launch {
            try {
                val response = authApi.verify2FA(TwoFactorRequest(s.challengeToken, s.totpCode))
                val data = response.data ?: throw Exception(response.message ?: "Verification failed")

                val user = data.user

                // AUDIT-AND-008: persist storeName only after credentials are fully
                // verified (2FA complete), not during the server probe.
                authPreferences.storeName = _state.value.storeName

                authPreferences.saveUser(
                    token = data.accessToken,
                    refreshToken = data.refreshToken,
                    id = user.id,
                    username = user.username,
                    firstName = user.firstName,
                    lastName = user.lastName,
                    role = user.role,
                )

                val codes = data.backupCodes
                if (!codes.isNullOrEmpty()) {
                    _state.value = _state.value.copy(isLoading = false, showBackupCodes = codes)
                } else {
                    onSuccess()
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    totpCode = "",
                    error = extractErrorMessage(e),
                )
            }
        }
    }

    fun dismissBackupCodes() {
        _state.value = _state.value.copy(showBackupCodes = null)
    }

    /** §2.12-L357 — called by the UI countdown LaunchedEffect when the timer reaches zero. */
    fun clearRateLimit() {
        _state.value = _state.value.copy(rateLimited = false, rateLimitResetMs = null)
    }

    /**
     * §2.13-L366 — called by the UI expiry LaunchedEffect when the 10-minute challenge
     * token window has elapsed. Clears the challenge, marks challengeExpired = true, and
     * resets the step back to CREDENTIALS so the user must restart login.
     * Username is preserved; password is cleared for security.
     */
    fun onChallengeTokenExpired() {
        _state.value = _state.value.copy(
            challengeToken = "",
            challengeTokenExpiresAtMs = null,
            challengeExpired = true,
            step = SetupStep.CREDENTIALS,
            // Clear sensitive mid-flow fields
            totpCode = "",
            newPassword = "",
            confirmPassword = "",
            qrCodeDataUrl = "",
            isLoading = false,
            error = null,
        )
    }

    /**
     * §2.13-L366 — called by the UI when the challengeExpired snackbar/banner is
     * acknowledged (or automatically dismissed). Clears the flag so the banner hides.
     */
    fun clearChallengeExpired() {
        _state.value = _state.value.copy(challengeExpired = false)
    }

    private fun extractErrorMessage(e: Exception): String {
        // Try to extract server error message from Retrofit HttpException
        if (e is retrofit2.HttpException) {
            val body = e.response()?.errorBody()?.string()
            if (body != null) {
                try {
                    return JSONObject(body).optString("message", e.message ?: "Request failed")
                } catch (_: Exception) {}
            }
            return "Server error (${e.code()})"
        }
        return e.message ?: "An error occurred"
    }
}

// ─── UI ─────────────────────────────────────────────────────────────

@Composable
fun LoginScreen(
    onLoginSuccess: () -> Unit,
    // §28.6 — non-null when the previous screen exit was a forced sign-out
    // (refresh-failed, session-revoked). Drives a sticky banner above the
    // form. Pure user-logout passes null so the banner doesn't appear.
    sessionRevokedReason: String? = null,
    onSessionBannerDismissed: () -> Unit = {},
    // §2.8 — shown on the CREDENTIALS step only; routes to ForgotPasswordScreen.
    onForgotPassword: (() -> Unit)? = null,
    // §2.8 L335 — shown on the TWO_FA_VERIFY step; routes to BackupCodeRecoveryScreen.
    onBackupCodeRecovery: (() -> Unit)? = null,
    viewModel: LoginViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    // §2.13-L366 — expiry ticker: runs only while a challenge token is active
    // (challengeTokenExpiresAtMs != null). Ticks every second and fires
    // onChallengeTokenExpired() when the deadline passes. Cancels automatically
    // when challengeTokenExpiresAtMs changes (new token) or becomes null
    // (CREDENTIALS step reset or successful verify2FA which clears the token).
    val expiresAtMs = state.challengeTokenExpiresAtMs
    LaunchedEffect(expiresAtMs) {
        if (expiresAtMs == null) return@LaunchedEffect
        while (true) {
            delay(1_000L)
            if (System.currentTimeMillis() >= expiresAtMs) {
                viewModel.onChallengeTokenExpired()
                break
            }
        }
    }

    // §2.13-L366 — show snackbar when challengeExpired flips to true.
    LaunchedEffect(state.challengeExpired) {
        if (state.challengeExpired) {
            snackbarHostState.showSnackbar(
                message = "Sign-in timed out. Please start over.",
                duration = SnackbarDuration.Short,
            )
            viewModel.clearChallengeExpired()
        }
    }

    // Backup codes dialog — must be dismissed before proceeding to dashboard
    if (state.showBackupCodes != null) {
        AlertDialog(
            onDismissRequest = { /* User must explicitly dismiss */ },
            containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
            title = { Text("Save Your Backup Codes") },
            text = {
                Column {
                    Text(
                        "Write these down and store them safely. Each code can only be used once if you lose access to your authenticator app.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(12.dp))
                    Surface(
                        shape = MaterialTheme.shapes.small,
                        color = MaterialTheme.colorScheme.surfaceVariant,
                        modifier = Modifier
                            .fillMaxWidth()
                            .border(
                                width = 1.dp,
                                color = MaterialTheme.colorScheme.primary.copy(alpha = 0.5f),
                                shape = MaterialTheme.shapes.small,
                            ),
                    ) {
                        Column(modifier = Modifier.padding(12.dp)) {
                            (state.showBackupCodes.orEmpty()).forEachIndexed { index, code ->
                                Text(
                                    "${index + 1}.  $code",
                                    style = MaterialTheme.typography.bodyMedium.copy(
                                        fontFamily = BrandMono.fontFamily,
                                    ),
                                )
                            }
                        }
                    }
                }
            },
            confirmButton = {
                Button(onClick = {
                    viewModel.dismissBackupCodes()
                    onLoginSuccess()
                }) {
                    Text("I've saved these codes")
                }
            },
        )
    }

    // §2.13-L366: Scaffold provides the snackbar host for challenge-expired notification.
    Scaffold(
        snackbarHost = { SnackbarHost(hostState = snackbarHostState) },
        containerColor = MaterialTheme.colorScheme.background,
    ) { innerPadding ->
    Box(
        modifier = Modifier.fillMaxSize().padding(innerPadding).statusBarsPadding().imePadding(),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier
                .widthIn(max = 420.dp)
                .padding(24.dp)
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // Logo / App name
            Spacer(Modifier.height(32.dp))
            Text(
                "Bizarre CRM",
                style = MaterialTheme.typography.headlineLarge,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                "Electronics Repair Management",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            // Sanctioned WaveDivider placement — one branded moment under wordmark
            Spacer(Modifier.height(8.dp))
            WaveDivider()
            Spacer(Modifier.height(24.dp))

            // §28.6 — sticky banner shown when the user landed here because
            // the server killed their session (refresh-failed / revoked).
            if (sessionRevokedReason != null) {
                Surface(
                    color = MaterialTheme.colorScheme.errorContainer,
                    shape = MaterialTheme.shapes.medium,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            Icons.Default.Lock,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onErrorContainer,
                        )
                        Text(
                            text = when (sessionRevokedReason) {
                                "RefreshFailed" -> "You've been signed out. Sign back in to continue."
                                "SessionRevoked" -> "Signed out — your session was ended on another device."
                                else -> "You've been signed out."
                            },
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onErrorContainer,
                            modifier = Modifier.weight(1f),
                        )
                        TextButton(onClick = onSessionBannerDismissed) {
                            Text("Dismiss")
                        }
                    }
                }
                Spacer(Modifier.height(16.dp))
            }

            // Step indicator
            StepIndicator(state.step)
            Spacer(Modifier.height(24.dp))

            // Step content with animation
            AnimatedContent(
                targetState = state.step,
                transitionSpec = {
                    slideInHorizontally { it } + fadeIn() togetherWith
                            slideOutHorizontally { -it } + fadeOut()
                },
                // AND-038: contentKey ensures AnimatedContent remeasures correctly
                // when transitioning between enum values with the same ordinal index.
                // Using ordinal (Int) rather than the enum itself avoids an extra
                // Any-equality check per frame.
                contentKey = { it.ordinal },
                label = "step",
            ) { step ->
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
                    border = androidx.compose.foundation.BorderStroke(
                        width = 1.dp,
                        color = MaterialTheme.colorScheme.outline,
                    ),
                    shape = MaterialTheme.shapes.medium,
                ) {
                    Column(modifier = Modifier.padding(24.dp)) {
                        when (step) {
                            SetupStep.SERVER -> ServerStep(state, viewModel)
                            SetupStep.REGISTER -> RegisterStep(state, viewModel)
                            SetupStep.CREDENTIALS -> CredentialsStep(state, viewModel, onForgotPassword)
                            SetupStep.SET_PASSWORD -> SetPasswordStep(state, viewModel)
                            SetupStep.TWO_FA_SETUP -> TwoFaSetupStep(state, viewModel, onLoginSuccess)
                            SetupStep.TWO_FA_VERIFY -> TwoFaVerifyStep(state, viewModel, onLoginSuccess, onBackupCodeRecovery)
                        }
                    }
                }
            }
        }
    }
    } // end Scaffold
}

@Composable
private fun StepIndicator(currentStep: SetupStep) {
    val steps = listOf(
        "Server" to SetupStep.SERVER,
        "Sign In" to SetupStep.CREDENTIALS,
        "2FA" to SetupStep.TWO_FA_VERIFY,
    )
    val currentIndex = when (currentStep) {
        SetupStep.SERVER, SetupStep.REGISTER -> 0
        SetupStep.CREDENTIALS, SetupStep.SET_PASSWORD -> 1
        SetupStep.TWO_FA_SETUP, SetupStep.TWO_FA_VERIFY -> 2
    }

    // Three thin 2px bar segments — inactive = outline, active = purple, completed = teal
    val primary = MaterialTheme.colorScheme.primary
    val secondary = MaterialTheme.colorScheme.secondary   // teal
    val outline = MaterialTheme.colorScheme.outline
    val onSurfaceVariant = MaterialTheme.colorScheme.onSurfaceVariant

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        steps.forEachIndexed { index, (label, _) ->
            val barColor = when {
                index < currentIndex -> secondary  // completed = teal
                index == currentIndex -> primary   // active = purple
                else -> outline                    // inactive = outline
            }
            Column(
                modifier = Modifier.weight(1f),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                HorizontalDivider(
                    thickness = 2.dp,
                    color = barColor,
                )
                Text(
                    label,
                    style = MaterialTheme.typography.labelSmall,
                    color = if (index <= currentIndex) primary else onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun ErrorMessage(error: String?) {
    if (error != null) {
        Spacer(Modifier.height(12.dp))
        Text(error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
    }
}

/**
 * §2.13-L366 — Countdown timer shown at the bottom of the challenge steps
 * (SET_PASSWORD, TWO_FA_SETUP, TWO_FA_VERIFY). Updates every second.
 * Renders in warning/error color when < 60 s remain.
 *
 * Only rendered when [expiresAtMs] is non-null (i.e. a challenge token is active).
 */
@Composable
private fun ChallengeTokenCountdown(expiresAtMs: Long?) {
    if (expiresAtMs == null) return

    val now = System.currentTimeMillis()
    var remainingMs by remember(expiresAtMs) {
        mutableStateOf((expiresAtMs - now).coerceAtLeast(0L))
    }

    // Tick every second while expiresAtMs is stable.
    LaunchedEffect(expiresAtMs) {
        while (remainingMs > 0L) {
            delay(1_000L)
            remainingMs = (expiresAtMs - System.currentTimeMillis()).coerceAtLeast(0L)
        }
    }

    val totalSec = remainingMs / 1000L
    val minutes = totalSec / 60
    val seconds = totalSec % 60
    val label = "%d:%02d".format(minutes, seconds)

    val warningColor = MaterialTheme.colorScheme.error
    val normalColor = MaterialTheme.colorScheme.onSurfaceVariant
    val textColor = if (remainingMs < 60_000L) warningColor else normalColor

    Spacer(Modifier.height(8.dp))
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            Icons.Default.Timer,
            contentDescription = null,
            modifier = Modifier.size(14.dp),
            tint = textColor,
        )
        Spacer(Modifier.width(4.dp))
        Text(
            "Sign-in expires in $label",
            style = MaterialTheme.typography.labelSmall,
            color = textColor,
        )
    }
}

// ─── Step 1: Server URL ─────────────────────────────────────────────

@Composable
private fun ServerStep(state: LoginUiState, viewModel: LoginViewModel) {
    val extColors = LocalExtendedColors.current  // AND-036
    val focusRequester = remember { FocusRequester() }

    LaunchedEffect(state.useCustomServer) { focusRequester.requestFocus() }

    Text(
        "Connect to Your Shop",
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.SemiBold,
    )
    Spacer(Modifier.height(4.dp))
    Text(
        if (state.useCustomServer) "Enter your self-hosted server address"
        else "Enter your shop name to connect",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Spacer(Modifier.height(16.dp))

    if (state.useCustomServer) {
        // Custom server mode — full URL input (self-hosted)
        OutlinedTextField(
            value = state.serverUrl,
            onValueChange = viewModel::updateServerUrl,
            label = { Text("Server URL") },
            placeholder = { Text("https://192.168.0.240:443") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth().focusRequester(focusRequester),
            leadingIcon = { Icon(Icons.Default.Dns, null) },
            trailingIcon = {
                if (state.serverConnected) {
                    Icon(Icons.Default.CheckCircle, "Connected", tint = extColors.success)
                }
            },
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done, keyboardType = KeyboardType.Uri),
            keyboardActions = KeyboardActions(onDone = { viewModel.connectToServer() }),
        )
    } else {
        // Cloud mode - slug + configured BASE_DOMAIN
        OutlinedTextField(
            value = state.shopSlug,
            onValueChange = viewModel::updateShopSlug,
            label = { Text("Shop Name") },
            placeholder = { Text("myshop") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth().focusRequester(focusRequester),
            leadingIcon = { Icon(Icons.Default.Store, null) },
            suffix = {
                Text(
                    ".$CLOUD_DOMAIN",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.bodyMedium,
                )
            },
            trailingIcon = {
                if (state.serverConnected) {
                    Icon(Icons.Default.CheckCircle, "Connected", tint = extColors.success)
                }
            },
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done, keyboardType = KeyboardType.Uri),
            keyboardActions = KeyboardActions(onDone = { viewModel.connectToServer() }),
        )
    }

    ErrorMessage(state.error)
    Spacer(Modifier.height(16.dp))

    Button(
        onClick = viewModel::connectToServer,
        enabled = if (state.useCustomServer) state.serverUrl.isNotBlank() && !state.isLoading
                  else state.shopSlug.length >= 3 && !state.isLoading,
        modifier = Modifier.fillMaxWidth().height(48.dp),
    ) {
        if (state.isLoading) {
            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
        } else {
            Text("Connect")
        }
    }

    Spacer(Modifier.height(12.dp))

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        TextButton(onClick = viewModel::toggleCustomServer) {
            Text(
                if (state.useCustomServer) "Use BizarreCRM Cloud" else "Self-hosted?",
                style = MaterialTheme.typography.labelSmall,
            )
        }
        if (!state.useCustomServer) {
            TextButton(onClick = viewModel::goToRegister) {
                Text("Register new shop", style = MaterialTheme.typography.labelSmall)
            }
        }
    }
}

// ─── Step 1b: Register ─────────────────────────────────────────────

@Composable
private fun RegisterStep(state: LoginUiState, viewModel: LoginViewModel) {
    var showPassword by remember { mutableStateOf(false) }

    Row(verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = viewModel::goBack) {
            Icon(Icons.Default.ArrowBack, "Back", modifier = Modifier.size(20.dp))
        }
        Spacer(Modifier.width(8.dp))
        Text("Register New Shop", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
    }
    Spacer(Modifier.height(4.dp))
    Text(
        "Create your repair shop on BizarreCRM",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Spacer(Modifier.height(16.dp))

    OutlinedTextField(
        value = state.shopSlug,
        onValueChange = viewModel::updateShopSlug,
        label = { Text("Shop URL") },
        placeholder = { Text("myshop") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
        leadingIcon = { Icon(Icons.Default.Link, null) },
        suffix = {
            Text(
                ".$CLOUD_DOMAIN",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodySmall,
            )
        },
        supportingText = { Text("3\u201330 characters: letters, numbers, hyphens") },
    )
    Spacer(Modifier.height(8.dp))

    OutlinedTextField(
        value = state.registerShopName,
        onValueChange = viewModel::updateRegisterShopName,
        label = { Text("Shop Display Name") },
        placeholder = { Text("My Repair Shop") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
        leadingIcon = { Icon(Icons.Default.Store, null) },
    )
    Spacer(Modifier.height(8.dp))

    OutlinedTextField(
        value = state.registerEmail,
        onValueChange = viewModel::updateRegisterEmail,
        label = { Text("Admin Email") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
        leadingIcon = { Icon(Icons.Default.Email, null) },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
    )
    Spacer(Modifier.height(8.dp))

    OutlinedTextField(
        value = state.registerPassword,
        onValueChange = viewModel::updateRegisterPassword,
        label = { Text("Admin Password") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
        leadingIcon = { Icon(Icons.Default.Lock, null) },
        visualTransformation = if (showPassword) VisualTransformation.None else PasswordVisualTransformation(),
        trailingIcon = {
            IconButton(onClick = { showPassword = !showPassword }) {
                Icon(
                    if (showPassword) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                    "Toggle password",
                )
            }
        },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
        supportingText = { Text("Minimum 8 characters") },
    )

    // §2.7-L328 — Timezone picker
    Spacer(Modifier.height(8.dp))
    TimezoneDropdown(
        selected = state.registerTimezone,
        onSelected = viewModel::updateRegisterTimezone,
        modifier = Modifier.fillMaxWidth(),
    )

    // §2.7-L329 — Shop type selector
    Spacer(Modifier.height(12.dp))
    ShopTypeSelector(
        selected = state.registerShopType,
        onSelected = viewModel::updateRegisterShopType,
        modifier = Modifier.fillMaxWidth(),
    )

    ErrorMessage(state.error)
    Spacer(Modifier.height(16.dp))

    Button(
        onClick = viewModel::registerShop,
        enabled = state.shopSlug.length >= 3 && state.registerShopName.isNotBlank()
                && state.registerEmail.isNotBlank() && state.registerPassword.length >= 8
                && !state.isLoading,
        modifier = Modifier.fillMaxWidth().height(48.dp),
    ) {
        if (state.isLoading) {
            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
        } else {
            Text("Create Shop")
        }
    }
}

// ─── §2.7-L328 — Timezone dropdown ─────────────────────────────────

private val CURATED_TIMEZONES = listOf(
    "US/Pacific",
    "US/Mountain",
    "US/Central",
    "US/Eastern",
    "America/Anchorage",
    "Pacific/Honolulu",
    "UTC",
    "Europe/London",
    "Europe/Paris",
    "Europe/Berlin",
    "Asia/Tokyo",
    "Asia/Shanghai",
    "Asia/Kolkata",
    "Australia/Sydney",
    "America/Toronto",
    "America/Vancouver",
    "America/Chicago",
    "America/Denver",
    "America/Los_Angeles",
    "America/New_York",
    "America/Sao_Paulo",
    "America/Mexico_City",
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TimezoneDropdown(
    selected: String,
    onSelected: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    // Ensure device default is in the list even if not in the curated set
    val options = remember(selected) {
        if (selected in CURATED_TIMEZONES) CURATED_TIMEZONES
        else listOf(selected) + CURATED_TIMEZONES
    }
    var expanded by remember { mutableStateOf(false) }

    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it },
        modifier = modifier,
    ) {
        OutlinedTextField(
            value = selected,
            onValueChange = {},
            readOnly = true,
            label = { Text("Timezone") },
            leadingIcon = { Icon(Icons.Default.Schedule, null) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor(),
            singleLine = true,
        )
        ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
        ) {
            options.forEach { tz ->
                DropdownMenuItem(
                    text = { Text(tz, style = MaterialTheme.typography.bodyMedium) },
                    onClick = {
                        onSelected(tz)
                        expanded = false
                    },
                    contentPadding = ExposedDropdownMenuDefaults.ItemContentPadding,
                )
            }
        }
    }
}

// ─── §2.7-L329 — Shop type selector ────────────────────────────────

private val SHOP_TYPES = listOf("repair", "retail", "hybrid", "other")

@Composable
private fun ShopTypeSelector(
    selected: String,
    onSelected: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier) {
        Text(
            "Shop Type",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(6.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            SHOP_TYPES.forEach { type ->
                val isSelected = type == selected
                FilterChip(
                    selected = isSelected,
                    onClick = { onSelected(type) },
                    label = {
                        Text(
                            type.replaceFirstChar { it.uppercase() },
                            style = MaterialTheme.typography.labelMedium,
                        )
                    },
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

// ─── Step 2: Credentials ────────────────────────────────────────────

@Composable
private fun CredentialsStep(
    state: LoginUiState,
    viewModel: LoginViewModel,
    onForgotPassword: (() -> Unit)? = null,
) {
    val focusManager = LocalFocusManager.current
    var showPassword by remember { mutableStateOf(false) }

    // §2.1 — fire the setup-status probe once on first render of this step.
    // Non-blocking: login form renders immediately; probe result overlays or
    // adds an informational banner when it completes.
    LaunchedEffect(Unit) { viewModel.probeSetupStatus() }

    // §2.1 — transparent probe overlay: ≤400ms loading indicator per spec.
    // Shown while the probe is in flight. Does NOT block the form fields.
    if (state.isProbing) {
        Box(
            modifier = androidx.compose.ui.Modifier.fillMaxWidth().padding(bottom = 8.dp),
            contentAlignment = Alignment.Center,
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                CircularProgressIndicator(modifier = androidx.compose.ui.Modifier.size(16.dp), strokeWidth = 2.dp)
                Text(
                    "Connecting to your server\u2026",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }

    // §2.1 — needs-setup banner: server has no users yet.
    if (state.setupNeeded == true) {
        Surface(
            color = MaterialTheme.colorScheme.secondaryContainer,
            shape = MaterialTheme.shapes.small,
            modifier = androidx.compose.ui.Modifier.fillMaxWidth().padding(bottom = 12.dp),
        ) {
            Row(
                modifier = androidx.compose.ui.Modifier.padding(10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    Icons.Default.Info,
                    contentDescription = null,
                    modifier = androidx.compose.ui.Modifier.size(18.dp),
                    tint = MaterialTheme.colorScheme.onSecondaryContainer,
                )
                Text(
                    "This server needs first-time setup. Contact your administrator.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSecondaryContainer,
                    modifier = androidx.compose.ui.Modifier.weight(1f),
                )
            }
        }
    }

    // §2.12-L358 — offline banner: device has no network.
    // Informational only — user must restore connectivity to sign in.
    if (state.networkOffline) {
        Surface(
            color = MaterialTheme.colorScheme.tertiaryContainer,
            shape = MaterialTheme.shapes.small,
            modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
        ) {
            Row(
                modifier = Modifier.padding(10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    Icons.Default.WifiOff,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                    tint = MaterialTheme.colorScheme.onTertiaryContainer,
                )
                Text(
                    "You're offline. Connect to sign in.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onTertiaryContainer,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }

    // §2.12-L356 — server unreachable banner: bad URL or no route.
    if (state.unreachableHost) {
        Surface(
            color = MaterialTheme.colorScheme.errorContainer,
            shape = MaterialTheme.shapes.small,
            modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    Icons.Default.CloudOff,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                    tint = MaterialTheme.colorScheme.onErrorContainer,
                )
                Text(
                    "Can't reach this server. Check the address.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onErrorContainer,
                    modifier = Modifier.weight(1f),
                )
                TextButton(
                    onClick = viewModel::login,
                    contentPadding = PaddingValues(4.dp),
                ) {
                    Text("Retry", style = MaterialTheme.typography.labelSmall)
                }
            }
        }
    }

    // §2.12-L357 — rate-limit banner with ticking countdown.
    // Countdown runs via LaunchedEffect; button re-enables automatically when timer expires.
    if (state.rateLimited) {
        // Derive remaining seconds from rateLimitResetMs, floor at 0.
        val resetMs = state.rateLimitResetMs ?: (System.currentTimeMillis() + 60_000L)
        var remainingSec by remember(resetMs) {
            mutableStateOf(((resetMs - System.currentTimeMillis()) / 1000L).coerceAtLeast(0L))
        }
        LaunchedEffect(resetMs) {
            while (remainingSec > 0L) {
                delay(1_000L)
                remainingSec = ((resetMs - System.currentTimeMillis()) / 1000L).coerceAtLeast(0L)
            }
            // Countdown expired — clear rate-limit state so button re-enables.
            viewModel.clearRateLimit()
        }
        Surface(
            color = MaterialTheme.colorScheme.secondaryContainer,
            shape = MaterialTheme.shapes.small,
            modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
        ) {
            Row(
                modifier = Modifier.padding(10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    Icons.Default.Timer,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                    tint = MaterialTheme.colorScheme.onSecondaryContainer,
                )
                Text(
                    if (remainingSec > 0L) "Too many attempts. Try again in ${remainingSec}s."
                    else "You can try again now.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSecondaryContainer,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }

    Row(verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = viewModel::goBack) {
            Icon(Icons.Default.ArrowBack, "Back", modifier = Modifier.size(20.dp))
        }
        Spacer(Modifier.width(8.dp))
        Column {
            Text("Sign In", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            if (state.storeName.isNotBlank()) {
                Text(state.storeName, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
    Spacer(Modifier.height(16.dp))

    OutlinedTextField(
        value = state.username,
        onValueChange = viewModel::updateUsername,
        label = { Text("Username") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
        leadingIcon = { Icon(Icons.Default.Person, null) },
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
        // D5-6: IME Next advances focus to the password field instead of sitting
        // inert under the visible "Next" glyph on the native keyboard.
        keyboardActions = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Down) }),
    )
    Spacer(Modifier.height(12.dp))

    OutlinedTextField(
        value = state.password,
        onValueChange = viewModel::updatePassword,
        label = { Text("Password") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
        leadingIcon = { Icon(Icons.Default.Lock, null) },
        visualTransformation = if (showPassword) VisualTransformation.None else PasswordVisualTransformation(),
        trailingIcon = {
            IconButton(onClick = { showPassword = !showPassword }) {
                Icon(if (showPassword) Icons.Default.VisibilityOff else Icons.Default.Visibility, "Toggle password")
            }
        },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done),
        keyboardActions = KeyboardActions(onDone = { focusManager.clearFocus(); viewModel.login() }),
    )

    ErrorMessage(state.error)
    Spacer(Modifier.height(16.dp))

    // CROSS48: Sign In is the single dominant CTA on this step — route
    // through BrandPrimaryButton so every primary button in the app
    // shares the same orange filled / onPrimary text / 12dp theme shape.
    // §2.12-L357/L358: disabled while offline or rate-limited.
    BrandPrimaryButton(
        onClick = viewModel::login,
        enabled = state.username.isNotBlank() && state.password.isNotBlank()
                && !state.isLoading && !state.networkOffline && !state.rateLimited,
        modifier = Modifier.fillMaxWidth().height(48.dp),
    ) {
        if (state.isLoading) {
            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
        } else {
            Text("Sign In")
        }
    }

    // §2.8 — Forgot password link, shown on username step only
    if (onForgotPassword != null) {
        Spacer(Modifier.height(4.dp))
        TextButton(
            onClick = onForgotPassword,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(
                "Forgot password?",
                style = MaterialTheme.typography.labelMedium,
            )
        }
    }
}

// ─── Step 2b: Set Password ──────────────────────────────────────────

@Composable
private fun SetPasswordStep(state: LoginUiState, viewModel: LoginViewModel) {
    // D5-6: local focus manager so IME Next advances from the new password
    // field to the confirm password field.
    val focusManager = LocalFocusManager.current
    Row(verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = viewModel::goBack) {
            Icon(Icons.Default.ArrowBack, "Back", modifier = Modifier.size(20.dp))
        }
        Spacer(Modifier.width(8.dp))
        Text("Set Your Password", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
    }
    Spacer(Modifier.height(4.dp))
    Text("This is your first login. Please set a password.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    Spacer(Modifier.height(16.dp))

    OutlinedTextField(
        value = state.newPassword,
        onValueChange = viewModel::updateNewPassword,
        label = { Text("New Password") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
        visualTransformation = PasswordVisualTransformation(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Next),
        keyboardActions = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Down) }),
    )
    Spacer(Modifier.height(12.dp))
    OutlinedTextField(
        value = state.confirmPassword,
        onValueChange = viewModel::updateConfirmPassword,
        label = { Text("Confirm Password") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
        visualTransformation = PasswordVisualTransformation(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done),
        keyboardActions = KeyboardActions(onDone = { viewModel.setPassword() }),
    )
    Text("Minimum 8 characters", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)

    ErrorMessage(state.error)
    Spacer(Modifier.height(16.dp))

    Button(
        onClick = viewModel::setPassword,
        enabled = state.newPassword.length >= 8 && !state.isLoading,
        modifier = Modifier.fillMaxWidth().height(48.dp),
    ) {
        if (state.isLoading) {
            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
        } else {
            Text("Set Password")
        }
    }

    // §2.13-L366: countdown shown while challenge token is live
    ChallengeTokenCountdown(state.challengeTokenExpiresAtMs)
}

// ─── Step 3a: 2FA Setup (QR Code) ──────────────────────────────────

@Composable
private fun TwoFaSetupStep(state: LoginUiState, viewModel: LoginViewModel, onSuccess: () -> Unit) {
    Text("Set Up Two-Factor Auth", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
    Spacer(Modifier.height(4.dp))
    Text("Scan this QR code with Google Authenticator or any TOTP app", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    Spacer(Modifier.height(16.dp))

    // Render QR code from data URL
    if (state.qrCodeDataUrl.startsWith("data:image")) {
        val qrBitmap = remember(state.qrCodeDataUrl) {
            try {
                val base64 = state.qrCodeDataUrl.substringAfter("base64,")
                val bytes = Base64.decode(base64, Base64.DEFAULT)
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            } catch (_: Exception) {
                null
            }
        }
        if (qrBitmap != null) {
            Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                Image(
                    bitmap = qrBitmap.asImageBitmap(),
                    contentDescription = "2FA QR Code",
                    modifier = Modifier.size(200.dp),
                )
            }
        } else {
            Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                Text(
                    "Failed to load QR code. Please try again.",
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
    } else {
        Box(
            modifier = Modifier.fillMaxWidth().height(200.dp),
            contentAlignment = Alignment.Center,
        ) {
            CircularProgressIndicator()
        }
    }

    Spacer(Modifier.height(16.dp))
    TotpCodeInputContent(state, viewModel, onSuccess)
    // §2.13-L366: countdown shown while challenge token is live
    ChallengeTokenCountdown(state.challengeTokenExpiresAtMs)
}

// ─── Step 3b: 2FA Verify (code only) ────────────────────────────────

@Composable
private fun TwoFaVerifyStep(
    state: LoginUiState,
    viewModel: LoginViewModel,
    onSuccess: () -> Unit,
    onBackupCodeRecovery: (() -> Unit)? = null,
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = viewModel::goBack) {
            Icon(Icons.Default.ArrowBack, "Back", modifier = Modifier.size(20.dp))
        }
        Spacer(Modifier.width(8.dp))
        Text("Two-Factor Authentication", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
    }
    Spacer(Modifier.height(4.dp))
    Text("Enter the 6-digit code from your authenticator app", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    Spacer(Modifier.height(24.dp))

    TotpCodeInputContent(state, viewModel, onSuccess)
    // §2.13-L366: countdown shown while challenge token is live
    ChallengeTokenCountdown(state.challengeTokenExpiresAtMs)

    // §2.8 L335 — recovery escape hatch shown below the verify form
    if (onBackupCodeRecovery != null) {
        Spacer(Modifier.height(4.dp))
        TextButton(
            onClick = onBackupCodeRecovery,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(
                "Lost 2FA access? Use a backup code",
                style = MaterialTheme.typography.labelMedium,
            )
        }
    }
}

// ─── Shared TOTP code input ─────────────────────────────────────────

@Composable
private fun TotpCodeInputContent(state: LoginUiState, viewModel: LoginViewModel, onSuccess: () -> Unit) {
    val focusRequester = remember { FocusRequester() }
    val focusManager = LocalFocusManager.current

    LaunchedEffect(Unit) { focusRequester.requestFocus() }

    OutlinedTextField(
        value = state.totpCode,
        onValueChange = viewModel::updateTotpCode,
        label = { Text("6-digit code") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth().focusRequester(focusRequester),
        textStyle = LocalTextStyle.current.copy(
            fontFamily = BrandMono.fontFamily,
            fontSize = 24.sp,
            letterSpacing = 6.sp,
            textAlign = TextAlign.Center,
            fontWeight = FontWeight.Bold,
        ),
        leadingIcon = { Icon(Icons.Default.Security, null) },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Done),
        keyboardActions = KeyboardActions(onDone = {
            focusManager.clearFocus() // Dismiss keyboard
        }),
    )

    ErrorMessage(state.error)
    Spacer(Modifier.height(16.dp))

    Button(
        onClick = { viewModel.verify2FA(onSuccess) },
        enabled = state.totpCode.length == 6 && !state.isLoading,
        modifier = Modifier.fillMaxWidth().height(48.dp),
    ) {
        if (state.isLoading) {
            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
        } else {
            Text("Continue")
        }
    }
}
