package com.bizarreelectronics.crm.ui.screens.auth

import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Base64
import androidx.compose.animation.*
import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.text.selection.SelectionContainer
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
import androidx.compose.ui.platform.LocalContext
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
import com.bizarreelectronics.crm.ui.components.auth.PasswordStrengthMeter
import com.bizarreelectronics.crm.ui.components.shared.BrandPrimaryButton
import com.bizarreelectronics.crm.util.PasswordStrength
import com.bizarreelectronics.crm.ui.theme.BrandMono
import com.bizarreelectronics.crm.ui.theme.LocalExtendedColors
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.data.remote.dto.*
import android.app.Activity
import androidx.fragment.app.FragmentActivity
import com.bizarreelectronics.crm.data.local.prefs.BiometricCredentialStore
import com.bizarreelectronics.crm.ui.auth.BiometricAuth
import com.bizarreelectronics.crm.util.ClipboardUtil
import com.bizarreelectronics.crm.util.NetworkMonitor
import com.bizarreelectronics.crm.util.QrCodeGenerator
import com.bizarreelectronics.crm.util.SmsOtpBus
import com.bizarreelectronics.crm.util.SmsRetrieverHelper
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

/**
 * §2.7-L326 — Sub-steps within the REGISTER top-level step.
 *
 * Ordered list drives [LinearProgressIndicator] fraction = (index+1)/4.
 * Navigation: Back/Next chips per sub-step; "Create account" CTA on [Confirm].
 *
 *  Company    — store name, timezone, shop type
 *  Owner      — first name, last name, email, password + strength meter
 *  ServerUrl  — self-hosted vs managed toggle + URL entry
 *  Confirm    — read-only summary + "Create account" CTA
 */
enum class RegisterSubStep { Company, Owner, ServerUrl, Confirm }

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
    // §2.4 L298 — raw TOTP secret returned by /auth/login/2fa-setup (copyable)
    val twoFaSecret: String = "",
    // §2.4 L298 — formatted manual-entry key (space-grouped base32, e.g. "ABCD EFGH …")
    val twoFaManualEntry: String = "",
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
    // rateLimitScope: "ip" | "username" | null (null = unknown, use generic copy).
    val rateLimited: Boolean = false,
    val rateLimitResetMs: Long? = null,
    val rateLimitScope: String? = null,
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
    // §2.7-L330 — setup invite token delivered via App Link bizarrecrm.com/setup/:token.
    // Null = normal registration flow. Non-null = pre-linked invite; sent as
    // `setup_token` in the POST /api/v1/signup body so the server can associate
    // the new shop with the pending invite. Server ignores the field if no invite exists.
    val registerSetupToken: String? = null,
    // §2.7-L326 — multi-step register sub-step tracker.
    val registerSubStep: RegisterSubStep = RegisterSubStep.Company,
    // §2.7-L326 — owner identity fields collected on the Owner sub-step.
    val registerFirstName: String = "",
    val registerLastName: String = "",
    val registerUsername: String = "",
    // §2.17-L407 — remember-me + biometric stash toggles on the CREDENTIALS step.
    // rememberMeChecked defaults to false; LoginScreen sets it to true on first
    // composition when rememberMeDefaultForA11y (TalkBack) is active (L414).
    val rememberMeChecked: Boolean = false,
    val biometricEnabled: Boolean = false,
    // §2.17-L409 — device-changed banner: shown when BiometricCredentialStore.retrieve()
    // returns DeviceChanged. Cleared when dismissed or re-enabled by the user.
    val deviceChangedBanner: Boolean = false,
    // §2.17-L413 — server-revoke banner: shown when GET /auth/me returns 401/403.
    val serverRevokeBanner: Boolean = false,
    // §2.17 — true while the auto-login biometric prompt is in flight on first launch.
    val isBiometricAutoLoginInFlight: Boolean = false,
    // §2.17-L407 — set to true after verify2FA when rememberMe + biometric are enabled.
    // LoginScreen reacts to this flag by launching the biometric stash prompt, then
    // calls viewModel.clearPendingBiometricStash() + navigates to dashboard.
    val pendingBiometricStash: Boolean = false,
    // Carries the credentials to stash — cleared immediately after the prompt.
    val pendingStashUsername: String = "",
    val pendingStashPassword: String = "",
)

// ─── ViewModel ──────────────────────────────────────────────────────

@HiltViewModel
class LoginViewModel @Inject constructor(
    private val authPreferences: AuthPreferences,
    private val authApi: AuthApi,
    private val networkMonitor: NetworkMonitor,
    private val biometricCredentialStore: BiometricCredentialStore,
    private val biometricAuth: BiometricAuth,
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
        // §2.17-L407/L408 — restore biometric stash preferences from prefs.
        biometricEnabled = authPreferences.biometricCredentialsEnabled,
        // §2.17-L414 — default remember-me to true when TalkBack is active.
        rememberMeChecked = authPreferences.biometricCredentialsEnabled
            || authPreferences.rememberMeDefaultForA11y,
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
    fun goToRegister() {
        _state.value = _state.value.copy(
            step = SetupStep.REGISTER,
            registerSubStep = RegisterSubStep.Company,
            error = null,
        )
    }
    fun updateRegisterShopName(value: String) { _state.value = _state.value.copy(registerShopName = value, error = null) }
    fun updateRegisterEmail(value: String) { _state.value = _state.value.copy(registerEmail = value, error = null) }
    fun updateRegisterPassword(value: String) { _state.value = _state.value.copy(registerPassword = value, error = null) }
    fun updateRegisterTimezone(value: String) { _state.value = _state.value.copy(registerTimezone = value, error = null) }
    fun updateRegisterShopType(value: String) { _state.value = _state.value.copy(registerShopType = value, error = null) }
    // §2.7-L326 — owner identity field updaters
    fun updateRegisterFirstName(value: String) { _state.value = _state.value.copy(registerFirstName = value, error = null) }
    fun updateRegisterLastName(value: String) { _state.value = _state.value.copy(registerLastName = value, error = null) }
    fun updateRegisterUsername(value: String) { _state.value = _state.value.copy(registerUsername = value, error = null) }
    // §2.7-L330 — called by LoginScreen when a setup token arrives via deep link.
    fun applySetupToken(token: String?) { _state.value = _state.value.copy(registerSetupToken = token) }

    // §2.7-L326 — sub-step navigation within REGISTER.
    fun registerNextSubStep() {
        val s = _state.value
        val next = when (s.registerSubStep) {
            RegisterSubStep.Company -> {
                if (s.registerShopName.isBlank()) {
                    _state.value = s.copy(error = "Shop display name is required")
                    return
                }
                RegisterSubStep.Owner
            }
            RegisterSubStep.Owner -> {
                val emailRegex = Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")
                when {
                    s.registerFirstName.isBlank() -> {
                        _state.value = s.copy(error = "First name is required"); return
                    }
                    s.registerLastName.isBlank() -> {
                        _state.value = s.copy(error = "Last name is required"); return
                    }
                    s.registerEmail.isBlank() || !emailRegex.matches(s.registerEmail.trim()) -> {
                        _state.value = s.copy(error = "Valid email is required"); return
                    }
                    s.registerPassword.length < 8 -> {
                        _state.value = s.copy(error = "Password must be at least 8 characters"); return
                    }
                    PasswordStrength.evaluate(s.registerPassword).level < PasswordStrength.Level.FAIR -> {
                        _state.value = s.copy(error = "Password is too weak — aim for at least Fair strength"); return
                    }
                    else -> RegisterSubStep.ServerUrl
                }
            }
            RegisterSubStep.ServerUrl -> RegisterSubStep.Confirm
            RegisterSubStep.Confirm -> { registerShop(); return }
        }
        _state.value = s.copy(registerSubStep = next, error = null)
    }

    fun registerPrevSubStep() {
        val s = _state.value
        val prev = when (s.registerSubStep) {
            RegisterSubStep.Company -> { goBack(); return }
            RegisterSubStep.Owner -> RegisterSubStep.Company
            RegisterSubStep.ServerUrl -> RegisterSubStep.Owner
            RegisterSubStep.Confirm -> RegisterSubStep.ServerUrl
        }
        _state.value = s.copy(registerSubStep = prev, error = null)
    }
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
            // Reset sub-step when leaving REGISTER entirely
            registerSubStep = if (current.step == SetupStep.REGISTER) RegisterSubStep.Company else current.registerSubStep,
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

    /**
     * Register a new shop on BizarreCRM cloud.
     *
     * §2.7-L327 — Auto-login contract (server-side TODO: SIGNUP-AUTO-LOGIN-TOKENS):
     *   When the signup response contains accessToken, the server has already issued
     *   a session for the newly-created admin account. Android stores the token via
     *   [AuthPreferences.saveUser] and invokes [onAutoLogin] to skip CREDENTIALS.
     *
     *   When accessToken is null (server predates the feature or flag is off), we
     *   fall back to CREDENTIALS with the email pre-filled as the username.
     */
    fun registerShop(onAutoLogin: (() -> Unit)? = null) {
        val s = _state.value
        val slug = s.shopSlug.trim()
        if (slug.isBlank() || slug.length < 3) { _state.value = s.copy(error = "Shop URL must be at least 3 characters"); return }
        if (s.registerShopName.isBlank()) { _state.value = s.copy(error = "Shop name is required"); return }
        if (s.registerEmail.isBlank()) { _state.value = s.copy(error = "Email is required"); return }
        if (s.registerPassword.length < 8) { _state.value = s.copy(error = "Password must be at least 8 characters"); return }

        _state.value = s.copy(isLoading = true, error = null)
        viewModelScope.launch {
            try {
                val responseJson = withContext(Dispatchers.IO) {
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
                        // Owner identity fields — server maps these to the admin user record
                        if (s.registerFirstName.isNotBlank()) put("first_name", s.registerFirstName.trim())
                        if (s.registerLastName.isNotBlank()) put("last_name", s.registerLastName.trim())
                        // §2.7-L328 — timezone (optional; server ignores unknown fields)
                        put("timezone", s.registerTimezone)
                        // §2.7-L329 — shop type (optional)
                        put("shop_type", s.registerShopType)
                        // §2.7-L330 — invite token (optional; server ignores if absent or unknown)
                        s.registerSetupToken?.let { put("setup_token", it) }
                    }
                    val requestBody = json.toString().toRequestBody("application/json".toMediaType())
                    val request = Request.Builder()
                        .url("https://$CLOUD_DOMAIN/api/v1/signup")
                        .header("Origin", "https://$CLOUD_DOMAIN")
                        .post(requestBody)
                        .build()
                    val response = client.newCall(request).execute()
                    val body = response.body?.string() ?: throw Exception("Empty response")
                    val rJson = JSONObject(body)
                    if (!response.isSuccessful || !rJson.optBoolean("success", false)) {
                        throw Exception(rJson.optString("message", "Registration failed"))
                    }
                    rJson
                }

                // Registration successful — persist shop URL
                val newUrl = "https://${slug}.$CLOUD_DOMAIN"
                authPreferences.serverUrl = newUrl
                authPreferences.storeName = s.registerShopName.trim()

                // §2.7-L327 — Auto-login: extract token from response data object if present
                val dataObj = responseJson.optJSONObject("data")
                val accessToken = dataObj?.optString("accessToken", null)
                    ?.takeIf { it.isNotBlank() }
                val refreshToken = dataObj?.optString("refreshToken", null)
                    ?.takeIf { it.isNotBlank() }

                if (accessToken != null) {
                    // Server issued a session immediately — store tokens and navigate to dashboard
                    authPreferences.accessToken = accessToken
                    if (refreshToken != null) authPreferences.refreshToken = refreshToken
                    // Fetch /auth/me to populate user identity (best-effort; failure is non-blocking)
                    try {
                        val meResponse = authApi.getMe()
                        val user = meResponse.data
                        if (user != null) {
                            authPreferences.saveUser(
                                token = accessToken,
                                refreshToken = refreshToken,
                                id = user.id,
                                username = user.username,
                                firstName = user.firstName,
                                lastName = user.lastName,
                                role = user.role,
                            )
                        }
                    } catch (_: Exception) {
                        // /auth/me failure is non-blocking; tokens are already persisted above
                    }
                    _state.value = _state.value.copy(isLoading = false, registerSubStep = RegisterSubStep.Company)
                    onAutoLogin?.invoke()
                } else {
                    // Fallback: no token in response — push to CREDENTIALS with email pre-filled
                    _state.value = _state.value.copy(
                        isLoading = false,
                        serverConnected = true,
                        storeName = s.registerShopName.trim(),
                        // Pre-fill username from email so user only needs the password
                        username = s.registerEmail.trim(),
                        step = SetupStep.CREDENTIALS,
                        registerSubStep = RegisterSubStep.Company,
                    )
                }
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
                // §2.12-L357/L289: 429 Too Many Requests → rate-limit countdown.
                // Priority order for retry delay:
                //   1. Body JSON { retry_in_seconds: N } — most accurate (per-rule)
                //   2. Retry-After header (seconds) — standard HTTP
                //   3. Fallback 60s
                // Body JSON may also carry { scope: "ip" | "username" } to tailor banner copy.
                // Avoid touching AuthApi.kt (Wave-7G scope) — no signature change.
                if (e is retrofit2.HttpException && e.code() == 429) {
                    val errorBody = try { e.response()?.errorBody()?.string() } catch (_: Exception) { null }
                    val bodyJson = try { if (errorBody != null) JSONObject(errorBody) else null } catch (_: Exception) { null }
                    val bodyRetrySec = bodyJson?.optLong("retry_in_seconds", -1L).let { if (it == -1L) null else it }
                    val scope = bodyJson?.optString("scope")?.takeIf { it.isNotBlank() }
                    val retryAfterSec: Long = bodyRetrySec
                        ?: try { e.response()?.headers()?.get("Retry-After")?.toLong() ?: 60L }
                           catch (_: NumberFormatException) { 60L }
                    val resetAt = System.currentTimeMillis() + retryAfterSec * 1000L
                    _state.value = _state.value.copy(
                        isLoading = false,
                        rateLimited = true,
                        rateLimitResetMs = resetAt,
                        rateLimitScope = scope,
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
                // Server returns { qr, secret, manualEntry, challengeToken }
                val qrCode = data.qr ?: data.qrCode ?: ""
                val secret = data.secret.orEmpty()
                val manualEntry = data.manualEntry.orEmpty()
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
                    // §2.4 L298 — store secret + manualEntry for enroll step display
                    twoFaSecret = secret,
                    twoFaManualEntry = manualEntry,
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
                // §2.17-L407 — if remember-me + biometric enabled, set pendingBiometricStash
                // so the LoginScreen composable can trigger the biometric prompt with an Activity
                // reference before navigating to the dashboard.
                val s2 = _state.value
                val shouldStash = s2.rememberMeChecked && s2.biometricEnabled
                if (!codes.isNullOrEmpty()) {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        showBackupCodes = codes,
                        pendingBiometricStash = shouldStash,
                        pendingStashUsername = if (shouldStash) s2.username.trim() else "",
                        pendingStashPassword = if (shouldStash) s2.password else "",
                    )
                } else if (shouldStash) {
                    _state.value = _state.value.copy(
                        isLoading = false,
                        pendingBiometricStash = true,
                        pendingStashUsername = s2.username.trim(),
                        pendingStashPassword = s2.password,
                    )
                    // onSuccess is called by LoginScreen after the stash prompt resolves.
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
        _state.value = _state.value.copy(rateLimited = false, rateLimitResetMs = null, rateLimitScope = null)
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
            twoFaSecret = "",
            twoFaManualEntry = "",
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

    // region — §2.17 Remember-me / biometric stash

    /** Toggles the "Remember me" checkbox on the CREDENTIALS step. */
    fun toggleRememberMe() {
        _state.value = _state.value.copy(rememberMeChecked = !_state.value.rememberMeChecked)
    }

    /**
     * §2.17-L407 — called by the UI after the biometric stash prompt is resolved
     * (success or cancelled). Clears the pending stash flag and any sensitive field.
     */
    fun clearPendingBiometricStash() {
        _state.value = _state.value.copy(
            pendingBiometricStash = false,
            pendingStashUsername = "",
            pendingStashPassword = "",
        )
    }

    /** Toggles the "Use biometrics" option on the CREDENTIALS step. */
    fun toggleBiometricEnabled() {
        val newValue = !_state.value.biometricEnabled
        authPreferences.biometricCredentialsEnabled = newValue
        _state.value = _state.value.copy(biometricEnabled = newValue)
    }

    /**
     * §2.17-L409 — dismisses the device-changed banner and ensures biometric login is
     * disabled so the user is not confused by a stale toggle state.
     */
    fun dismissDeviceChangedBanner() {
        _state.value = _state.value.copy(deviceChangedBanner = false)
    }

    /**
     * §2.17-L413 — dismisses the server-revoke banner (user acknowledged the sign-out).
     */
    fun dismissServerRevokeBanner() {
        _state.value = _state.value.copy(serverRevokeBanner = false)
    }

    /**
     * §2.17-L407 — called after a successful `verify2FA` if the user has opted into
     * biometric-gated credential storage. Launches a BiometricPrompt to encrypt the
     * credentials and stores them via [BiometricCredentialStore].
     *
     * The IV returned by the Cipher after encryption is persisted via
     * [AuthPreferences.setStoredCredentialsIv] so [attemptBiometricAutoLogin] can
     * reconstruct the decrypt cipher on next launch.
     *
     * No password is ever written to Logcat. Failure is silent — the user simply
     * falls back to password login next time.
     */
    fun stashCredentialsBiometric(activity: FragmentActivity, username: String, password: String) {
        viewModelScope.launch {
            runCatching {
                val encryptCipher = biometricCredentialStore.createEncryptCipher()
                val authenticatedCipher = biometricAuth.encryptWithBiometric(activity, encryptCipher)
                    ?: return@launch // user cancelled — no-op
                val stored = biometricCredentialStore.store(username, password, authenticatedCipher)
                if (stored) {
                    authPreferences.setStoredCredentialsIv(authenticatedCipher.iv)
                    authPreferences.biometricCredentialsEnabled = true
                    _state.value = _state.value.copy(biometricEnabled = true)
                }
            }
            // Swallow any Keystore/crypto errors — biometric stash is best-effort.
        }
    }

    /**
     * §2.17-L407 — attempts biometric auto-login on first launch when stored credentials
     * are available and the user has enabled biometric login. Triggers BiometricPrompt; on
     * success decrypts + replays the stored credentials via the normal login flow.
     *
     * Handles [BiometricCredentialStore.RetrieveResult.DeviceChanged] and [Invalidated]:
     * clears the credential stash, disables biometric login, and surfaces the appropriate
     * banner so the user re-enables it after a password login (§2.17-L409).
     *
     * On [RetrieveResult.DeviceChanged] the banner text is:
     * "Biometric sign-in was disabled because this device changed. Sign in with your
     *  password to re-enable."
     */
    fun attemptBiometricAutoLogin(activity: FragmentActivity, onSuccess: () -> Unit) {
        if (!authPreferences.biometricCredentialsEnabled) return
        val iv = authPreferences.getStoredCredentialsIv() ?: return
        if (!biometricCredentialStore.hasStoredCredentials) return

        _state.value = _state.value.copy(isBiometricAutoLoginInFlight = true)
        viewModelScope.launch {
            runCatching {
                val decryptCipher = biometricCredentialStore.createDecryptCipher(iv)
                val authenticatedCipher = biometricAuth.decryptWithBiometric(activity, decryptCipher, iv)
                if (authenticatedCipher == null) {
                    // User cancelled — fall back to password form.
                    _state.value = _state.value.copy(isBiometricAutoLoginInFlight = false)
                    return@launch
                }
                when (val result = biometricCredentialStore.retrieve(authenticatedCipher)) {
                    is BiometricCredentialStore.RetrieveResult.Success -> {
                        // Replay login with decrypted credentials — full 2FA flow
                        val creds = result.credentials
                        _state.value = _state.value.copy(
                            username = creds.username,
                            password = creds.password,
                            isBiometricAutoLoginInFlight = false,
                        )
                        login() // kicks off the normal password → 2FA → verify flow
                    }
                    BiometricCredentialStore.RetrieveResult.DeviceChanged,
                    BiometricCredentialStore.RetrieveResult.Invalidated -> {
                        // Wipe stash and disable biometric login.
                        biometricCredentialStore.clear()
                        authPreferences.biometricCredentialsEnabled = false
                        authPreferences.setStoredCredentialsIv(null)
                        _state.value = _state.value.copy(
                            biometricEnabled = false,
                            deviceChangedBanner = result == BiometricCredentialStore.RetrieveResult.DeviceChanged,
                            isBiometricAutoLoginInFlight = false,
                        )
                    }
                    else -> {
                        _state.value = _state.value.copy(isBiometricAutoLoginInFlight = false)
                    }
                }
            }.onFailure {
                _state.value = _state.value.copy(isBiometricAutoLoginInFlight = false)
            }
        }
    }

    /**
     * §2.17-L413 — called when GET /auth/me returns 401 or 403 (server-side revoke).
     * Wipes the biometric credential stash, clears the session, and surfaces the
     * "Signed out on another device" banner. The [AuthPreferences.clear] call with
     * [ClearReason.SessionRevoked] propagates to [BiometricCredentialStore.clear] via
     * the registered [AuthPreferences.setBiometricClearCallback].
     */
    fun handleServerRevoke() {
        authPreferences.clear(AuthPreferences.ClearReason.SessionRevoked)
        _state.value = _state.value.copy(
            serverRevokeBanner = true,
            biometricEnabled = false,
            step = SetupStep.CREDENTIALS,
        )
    }

    // endregion

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
    // §2.7 L330 — setup invite token delivered from App Link bizarrecrm.com/setup/:token.
    // When non-null the screen immediately advances to the Register step and stores
    // the token in the ViewModel so registerShop() includes it in the POST body.
    setupToken: String? = null,
    viewModel: LoginViewModel = hiltViewModel(),
) {
    val context = LocalContext.current
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    // §2.7 L330 — when an invite token arrives via deep link, jump to the
    // Register step and store the token once. Keyed on setupToken identity so
    // config changes don't re-fire unless the token itself changes.
    LaunchedEffect(setupToken) {
        if (!setupToken.isNullOrBlank()) {
            viewModel.applySetupToken(setupToken)
            viewModel.goToRegister()
        }
    }

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

    // §2.17-L407 — biometric stash: launch the encrypt prompt once verify2FA sets the flag.
    val pendingStash = state.pendingBiometricStash
    LaunchedEffect(pendingStash) {
        if (pendingStash) {
            val activity = (context as? FragmentActivity)
            if (activity != null) {
                viewModel.stashCredentialsBiometric(
                    activity = activity,
                    username = state.pendingStashUsername,
                    password = state.pendingStashPassword,
                )
            }
            viewModel.clearPendingBiometricStash()
            onLoginSuccess()
        }
    }

    // §2.17-L407 — biometric auto-login: attempt on first composition when stored creds exist.
    LaunchedEffect(Unit) {
        val activity = (context as? FragmentActivity)
        if (activity != null) {
            viewModel.attemptBiometricAutoLogin(activity, onLoginSuccess)
        }
    }

    // §2.4 L301 — Backup codes display after enrollment success.
    // BackupCodesDisplay handles its own checkbox-gate; onDismiss is called only
    // when the user confirms they have saved the codes, then navigates to dashboard.
    if (state.showBackupCodes != null) {
        BackupCodesDisplay(
            codes = state.showBackupCodes.orEmpty(),
            onDismiss = {
                viewModel.dismissBackupCodes()
                onLoginSuccess()
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

            // §2.17-L409 — device-changed banner: biometric login disabled after device change.
            if (state.deviceChangedBanner) {
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
                            Icons.Default.PhonelinkErase,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onErrorContainer,
                        )
                        Text(
                            text = "Biometric sign-in was disabled because this device changed. Sign in with your password to re-enable.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onErrorContainer,
                            modifier = Modifier.weight(1f),
                        )
                        TextButton(onClick = viewModel::dismissDeviceChangedBanner) {
                            Text("OK")
                        }
                    }
                }
                Spacer(Modifier.height(16.dp))
            }

            // §2.17-L413 — server-revoke banner.
            if (state.serverRevokeBanner) {
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
                            text = "Signed out on another device.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onErrorContainer,
                            modifier = Modifier.weight(1f),
                        )
                        TextButton(onClick = viewModel::dismissServerRevokeBanner) {
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
                            SetupStep.REGISTER -> RegisterStep(state, viewModel, onLoginSuccess)
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

// ─── Step 1b: Register (multi-step) ────────────────────────────────
//
// §2.7-L326 — four sub-steps tracked by RegisterSubStep enum.
// Progress bar at top; AnimatedContent slides horizontally between sub-steps.
// Validation fires on Next; Create Account on Confirm submits registerShop().

private val REGISTER_SUB_STEPS = RegisterSubStep.values().toList()

@Composable
private fun RegisterStep(state: LoginUiState, viewModel: LoginViewModel, onLoginSuccess: () -> Unit) {
    val subStepIndex = REGISTER_SUB_STEPS.indexOf(state.registerSubStep)
    val context = androidx.compose.ui.platform.LocalContext.current
    val reduceMotion = remember {
        android.provider.Settings.Global.getFloat(
            context.contentResolver,
            android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f
        ) == 0f
    }

    // §2.7-L326 — progress indicator: fraction = (index + 1) / total
    LinearProgressIndicator(
        progress = { (subStepIndex + 1).toFloat() / REGISTER_SUB_STEPS.size.toFloat() },
        modifier = Modifier.fillMaxWidth(),
    )
    Spacer(Modifier.height(12.dp))

    // Header row with back arrow
    Row(verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = viewModel::registerPrevSubStep) {
            Icon(Icons.Default.ArrowBack, "Back", modifier = Modifier.size(20.dp))
        }
        Spacer(Modifier.width(4.dp))
        Column {
            Text(
                text = when (state.registerSubStep) {
                    RegisterSubStep.Company -> "Your Shop"
                    RegisterSubStep.Owner -> "Account Owner"
                    RegisterSubStep.ServerUrl -> "Server"
                    RegisterSubStep.Confirm -> "Review & Create"
                },
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = "Step ${subStepIndex + 1} of ${REGISTER_SUB_STEPS.size}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
    Spacer(Modifier.height(8.dp))

    // §2.7-L326 — animated horizontal slide; skip animation when ReduceMotion
    AnimatedContent(
        targetState = state.registerSubStep,
        transitionSpec = {
            if (reduceMotion) {
                fadeIn() togetherWith fadeOut()
            } else {
                val forward = initialState.ordinal < targetState.ordinal
                slideInHorizontally { if (forward) it else -it } + fadeIn() togetherWith
                    slideOutHorizontally { if (forward) -it else it } + fadeOut()
            }
        },
        contentKey = { it.ordinal },
        label = "registerSubStep",
    ) { subStep ->
        Column(modifier = Modifier.fillMaxWidth()) {
            when (subStep) {
                RegisterSubStep.Company -> RegisterCompanySubStep(state, viewModel)
                RegisterSubStep.Owner -> RegisterOwnerSubStep(state, viewModel)
                RegisterSubStep.ServerUrl -> RegisterServerUrlSubStep(state, viewModel)
                RegisterSubStep.Confirm -> RegisterConfirmSubStep(state, viewModel, onLoginSuccess)
            }
        }
    }
}

// ── Sub-step: Company ──────────────────────────────

@Composable
private fun RegisterCompanySubStep(state: LoginUiState, viewModel: LoginViewModel) {
    Text(
        "Tell us about your shop",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Spacer(Modifier.height(12.dp))

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
        supportingText = { Text("3–30 characters: letters, numbers, hyphens") },
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
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
    )
    Spacer(Modifier.height(8.dp))

    // §2.7-L328 — Timezone picker
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
        onClick = viewModel::registerNextSubStep,
        enabled = state.shopSlug.length >= 3 && state.registerShopName.isNotBlank() && !state.isLoading,
        modifier = Modifier.fillMaxWidth().height(48.dp),
    ) {
        Text("Next")
    }
}

// ── Sub-step: Owner ───────────────────────────────────

@Composable
private fun RegisterOwnerSubStep(state: LoginUiState, viewModel: LoginViewModel) {
    val focusManager = LocalFocusManager.current
    var showPassword by remember { mutableStateOf(false) }

    Text(
        "Create your admin account",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Spacer(Modifier.height(12.dp))

    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedTextField(
            value = state.registerFirstName,
            onValueChange = viewModel::updateRegisterFirstName,
            label = { Text("First Name") },
            singleLine = true,
            modifier = Modifier.weight(1f),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
            keyboardActions = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Right) }),
        )
        OutlinedTextField(
            value = state.registerLastName,
            onValueChange = viewModel::updateRegisterLastName,
            label = { Text("Last Name") },
            singleLine = true,
            modifier = Modifier.weight(1f),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
            keyboardActions = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Down) }),
        )
    }
    Spacer(Modifier.height(8.dp))

    OutlinedTextField(
        value = state.registerEmail,
        onValueChange = viewModel::updateRegisterEmail,
        label = { Text("Email") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth(),
        leadingIcon = { Icon(Icons.Default.Email, null) },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email, imeAction = ImeAction.Next),
        keyboardActions = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Down) }),
    )
    Spacer(Modifier.height(8.dp))

    OutlinedTextField(
        value = state.registerPassword,
        onValueChange = viewModel::updateRegisterPassword,
        label = { Text("Password") },
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
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done),
        keyboardActions = KeyboardActions(onDone = { focusManager.clearFocus() }),
        supportingText = { Text("Minimum 8 characters") },
    )
    if (state.registerPassword.isNotEmpty()) {
        Spacer(Modifier.height(8.dp))
        PasswordStrengthMeter(password = state.registerPassword)
    }

    ErrorMessage(state.error)
    Spacer(Modifier.height(16.dp))

    val passStrength = PasswordStrength.evaluate(state.registerPassword).level
    Button(
        onClick = viewModel::registerNextSubStep,
        enabled = state.registerFirstName.isNotBlank() && state.registerLastName.isNotBlank()
                && state.registerEmail.isNotBlank()
                && passStrength >= PasswordStrength.Level.FAIR
                && !state.isLoading,
        modifier = Modifier.fillMaxWidth().height(48.dp),
    ) {
        Text("Next")
    }
}

// ── Sub-step: Server URL ───────────────────────────────

@Composable
private fun RegisterServerUrlSubStep(state: LoginUiState, viewModel: LoginViewModel) {
    Text(
        "Where will your CRM live?",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Spacer(Modifier.height(12.dp))

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        FilterChip(
            selected = !state.useCustomServer,
            onClick = { if (state.useCustomServer) viewModel.toggleCustomServer() },
            label = { Text("BizarreCRM Cloud", style = MaterialTheme.typography.labelMedium) },
            leadingIcon = { Icon(Icons.Default.Language, null, modifier = Modifier.size(16.dp)) },
            modifier = Modifier.weight(1f),
        )
        FilterChip(
            selected = state.useCustomServer,
            onClick = { if (!state.useCustomServer) viewModel.toggleCustomServer() },
            label = { Text("Self-hosted", style = MaterialTheme.typography.labelMedium) },
            leadingIcon = { Icon(Icons.Default.Dns, null, modifier = Modifier.size(16.dp)) },
            modifier = Modifier.weight(1f),
        )
    }
    Spacer(Modifier.height(12.dp))

    if (state.useCustomServer) {
        OutlinedTextField(
            value = state.serverUrl,
            onValueChange = viewModel::updateServerUrl,
            label = { Text("Server URL") },
            placeholder = { Text("https://192.168.0.240:443") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            leadingIcon = { Icon(Icons.Default.Dns, null) },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Done),
        )
    } else {
        Surface(
            color = MaterialTheme.colorScheme.secondaryContainer,
            shape = MaterialTheme.shapes.small,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Row(
                modifier = Modifier.padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(Icons.Default.Language, null, tint = MaterialTheme.colorScheme.onSecondaryContainer, modifier = Modifier.size(18.dp))
                val slugDisplay = if (state.shopSlug.isBlank()) "yourshop" else state.shopSlug
                Text(
                    "Your shop will be hosted at\nhttps://$slugDisplay.$CLOUD_DOMAIN",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSecondaryContainer,
                )
            }
        }
    }

    ErrorMessage(state.error)
    Spacer(Modifier.height(16.dp))

    Button(
        onClick = viewModel::registerNextSubStep,
        enabled = !state.isLoading,
        modifier = Modifier.fillMaxWidth().height(48.dp),
    ) {
        Text("Next")
    }
}

// ── Sub-step: Confirm ─────────────────────────────────

@Composable
private fun RegisterConfirmSubStep(
    state: LoginUiState,
    viewModel: LoginViewModel,
    onLoginSuccess: () -> Unit,
) {
    Text(
        "Everything look right?",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Spacer(Modifier.height(12.dp))

    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant,
        shape = MaterialTheme.shapes.small,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            ConfirmRow("Shop URL", "${state.shopSlug}.$CLOUD_DOMAIN")
            ConfirmRow("Shop Name", state.registerShopName)
            ConfirmRow("Timezone", state.registerTimezone)
            ConfirmRow("Shop Type", state.registerShopType.replaceFirstChar { it.uppercase() })
            ConfirmRow("Owner", "${state.registerFirstName} ${state.registerLastName}".trim())
            ConfirmRow("Email", state.registerEmail)
            ConfirmRow("Server", if (state.useCustomServer && state.serverUrl.isNotBlank()) state.serverUrl else "BizarreCRM Cloud")
        }
    }

    ErrorMessage(state.error)
    Spacer(Modifier.height(16.dp))

    // §2.7-L327 — onAutoLogin navigates to dashboard when server returns a token
    BrandPrimaryButton(
        onClick = { viewModel.registerShop(onAutoLogin = onLoginSuccess) },
        enabled = !state.isLoading,
        modifier = Modifier.fillMaxWidth().height(48.dp),
    ) {
        if (state.isLoading) {
            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp, color = MaterialTheme.colorScheme.onPrimary)
        } else {
            Text("Create Account")
        }
    }
}

@Composable
private fun ConfirmRow(label: String, value: String) {
    if (value.isBlank()) return
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Medium)
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

    // §2.1/L276 — needs-setup banner: server has no users yet.
    // Wizard (§2.10) is not implemented; informational banner directs admin to docs.
    // Does NOT block the login form — admin may already have credentials if setup
    // was completed outside the wizard flow.
    if (state.setupNeeded == true) {
        val setupContext = LocalContext.current
        Surface(
            color = MaterialTheme.colorScheme.secondaryContainer,
            shape = MaterialTheme.shapes.small,
            modifier = androidx.compose.ui.Modifier.fillMaxWidth().padding(bottom = 12.dp),
        ) {
            Column(modifier = androidx.compose.ui.Modifier.padding(10.dp)) {
                Row(
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
                        "This server needs initial setup. A setup wizard will appear in a future release. Please contact your admin to complete setup manually.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSecondaryContainer,
                        modifier = androidx.compose.ui.Modifier.weight(1f),
                    )
                }
                Spacer(androidx.compose.ui.Modifier.height(4.dp))
                TextButton(
                    onClick = {
                        val intent = android.content.Intent(
                            android.content.Intent.ACTION_VIEW,
                            android.net.Uri.parse("https://bizarrecrm.com/docs/setup"),
                        )
                        setupContext.startActivity(intent)
                    },
                    contentPadding = PaddingValues(horizontal = 0.dp, vertical = 0.dp),
                    modifier = androidx.compose.ui.Modifier.height(24.dp),
                ) {
                    Text(
                        "View setup guide",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
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

    // §2.12-L357/L289 — rate-limit banner with ticking countdown.
    // Countdown format: "Nm Ss" for ≥60s remaining, "Ns" for <60s.
    // Banner copy is scope-aware: "ip" = generic, "username" = per-username message.
    // Button re-enables automatically when timer expires.
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
        val countdownText = when {
            remainingSec <= 0L  -> "You can try again now."
            remainingSec >= 60L -> {
                val m = remainingSec / 60
                val s = remainingSec % 60
                val scopePrefix = if (state.rateLimitScope == "username")
                    "Too many attempts for this username." else "Too many attempts."
                "$scopePrefix Wait ${m}m ${s}s."
            }
            else -> {
                val scopePrefix = if (state.rateLimitScope == "username")
                    "Too many attempts for this username." else "Too many attempts."
                "$scopePrefix Wait ${remainingSec}s."
            }
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
                    countdownText,
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

    // §2.17-L407/L414 — Remember me + biometric toggles.
    Spacer(Modifier.height(4.dp))
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Checkbox(
            checked = state.rememberMeChecked,
            onCheckedChange = { viewModel.toggleRememberMe() },
        )
        Text(
            "Remember me",
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier
                .weight(1f)
                .padding(start = 4.dp),
        )
        if (state.rememberMeChecked) {
            Checkbox(
                checked = state.biometricEnabled,
                onCheckedChange = { viewModel.toggleBiometricEnabled() },
            )
            Text(
                "Use biometrics",
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(start = 4.dp),
            )
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
    // §2.10/L294 — strength meter: shows progress and per-rule checks live as user types.
    if (state.newPassword.isNotEmpty()) {
        Spacer(Modifier.height(8.dp))
        PasswordStrengthMeter(password = state.newPassword)
    }
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

    ErrorMessage(state.error)
    Spacer(Modifier.height(16.dp))

    // §2.10/L294 — CTA disabled until strength is at least FAIR.
    val newPassStrength = PasswordStrength.evaluate(state.newPassword).level
    val strengthAcceptable = newPassStrength >= PasswordStrength.Level.FAIR
    Button(
        onClick = viewModel::setPassword,
        enabled = strengthAcceptable && !state.isLoading,
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

// ─── Step 3a: 2FA Enroll (QR Code + secret + OTP submit) ────────────
//
// §2.4 L298 — TwoFaEnrollStep (called TwoFaSetupStep in the step machine).
// Shown after POST /auth/login/2fa-setup returns { qr, secret, manualEntry }.
// Three rendering paths for the QR bitmap:
//   1. Server returned a data:image/... URL → decode base64 → Bitmap
//   2. Server returned a raw secret → QrCodeGenerator encodes otpauth:// URI
//   3. Neither → spinner (server still loading / network lag)
//
// Secret display is copyable via SelectionContainer + "Copy secret" button
// with 30s auto-clear (ClipboardUtil.copySensitive).
// "Open authenticator" launches the otpauth:// Intent; hidden when no app resolves it.

@Composable
private fun TwoFaSetupStep(state: LoginUiState, viewModel: LoginViewModel, onSuccess: () -> Unit) {
    val context = LocalContext.current

    Text("Set Up Two-Factor Auth", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
    Spacer(Modifier.height(4.dp))
    Text(
        "Scan this QR code with any authenticator app (Google Authenticator, Authy, etc.)",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Spacer(Modifier.height(16.dp))

    // ── QR bitmap resolution ────────────────────────────────────────────────
    // Priority: server data URL → on-device ZXing encode from secret → null (spinner)
    val qrBitmap = remember(state.qrCodeDataUrl, state.twoFaSecret, state.username) {
        when {
            state.qrCodeDataUrl.startsWith("data:image") -> {
                try {
                    val base64 = state.qrCodeDataUrl.substringAfter("base64,")
                    val bytes = Base64.decode(base64, Base64.DEFAULT)
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                } catch (_: Exception) { null }
            }
            state.twoFaSecret.isNotBlank() -> {
                // Build otpauth URI on-device and encode with ZXing
                val issuer = "BizarreCRM"
                val accountName = state.username.ifBlank { "user" }
                val otpauthUri = "otpauth://totp/$issuer:$accountName" +
                    "?secret=${state.twoFaSecret}&issuer=$issuer"
                try { QrCodeGenerator.generateQrBitmap(otpauthUri) } catch (_: Exception) { null }
            }
            else -> null
        }
    }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(240.dp),
        contentAlignment = Alignment.Center,
    ) {
        when {
            qrBitmap != null -> Image(
                bitmap = qrBitmap.asImageBitmap(),
                contentDescription = "2FA QR Code — scan with your authenticator app",
                modifier = Modifier.size(240.dp),
            )
            state.qrCodeDataUrl.isBlank() && state.twoFaSecret.isBlank() ->
                CircularProgressIndicator()
            else -> Text(
                "Failed to render QR code — use the manual key below.",
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
                textAlign = TextAlign.Center,
            )
        }
    }

    // ── Secret / manual-entry display ──────────────────────────────────────
    val displaySecret = state.twoFaManualEntry.ifBlank { state.twoFaSecret }
    if (displaySecret.isNotBlank()) {
        Spacer(Modifier.height(12.dp))
        Text(
            "Or enter this key manually:",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(4.dp))
        Surface(
            shape = MaterialTheme.shapes.small,
            color = MaterialTheme.colorScheme.surfaceVariant,
            modifier = Modifier.fillMaxWidth(),
        ) {
            SelectionContainer {
                Text(
                    text = displaySecret,
                    style = MaterialTheme.typography.bodyLarge.copy(
                        fontFamily = BrandMono.fontFamily,
                        letterSpacing = 2.sp,
                    ),
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        // Row: "Copy secret" + optional "Open authenticator"
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            OutlinedButton(
                onClick = {
                    ClipboardUtil.copySensitive(
                        context = context,
                        label = "2FA secret",
                        text = displaySecret,
                        clearAfterMillis = 30_000L,
                    )
                },
                modifier = Modifier.weight(1f),
            ) {
                Icon(Icons.Default.ContentCopy, contentDescription = null, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(4.dp))
                Text("Copy key", style = MaterialTheme.typography.labelMedium)
            }

            // "Open authenticator" — only shown when an app handles otpauth://
            val otpauthUri = remember(state.twoFaSecret, state.username) {
                if (state.twoFaSecret.isBlank()) null
                else {
                    val issuer = "BizarreCRM"
                    val accountName = state.username.ifBlank { "user" }
                    Uri.parse(
                        "otpauth://totp/$issuer:$accountName" +
                        "?secret=${state.twoFaSecret}&issuer=$issuer"
                    )
                }
            }
            val canOpenAuthenticator = remember(otpauthUri) {
                if (otpauthUri == null) false
                else {
                    val intent = Intent(Intent.ACTION_VIEW, otpauthUri)
                    context.packageManager.resolveActivity(intent, 0) != null
                }
            }
            if (canOpenAuthenticator && otpauthUri != null) {
                OutlinedButton(
                    onClick = {
                        context.startActivity(Intent(Intent.ACTION_VIEW, otpauthUri))
                    },
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(Icons.Default.OpenInNew, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("Open app", style = MaterialTheme.typography.labelMedium)
                }
            }
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
    val context = LocalContext.current

    // §2.4 L302 — Start the SMS Retriever session when the verify step is shown.
    // Play Services will deliver the OTP SMS to SmsOtpBroadcastReceiver within
    // 5 minutes; if it doesn't arrive the user types the code manually (already
    // works). startRetriever is safe to call multiple times — Play Services
    // ignores duplicates within an active 5-minute window.
    LaunchedEffect(Unit) {
        val activity = context as? Activity
        if (activity != null) {
            SmsRetrieverHelper.startRetriever(activity)
                .addOnFailureListener { e ->
                    android.util.Log.w("TwoFaVerifyStep", "SmsRetriever start failed", e)
                }
        }
    }

    // §2.4 L302 — Collect OTP codes published by SmsOtpBroadcastReceiver and
    // auto-fill the TOTP field. The flow is hot (no replay), so only codes
    // that arrive while this composable is in the backstack are received.
    LaunchedEffect(Unit) {
        SmsOtpBus.events.collect { code ->
            viewModel.updateTotpCode(code)
        }
    }

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
