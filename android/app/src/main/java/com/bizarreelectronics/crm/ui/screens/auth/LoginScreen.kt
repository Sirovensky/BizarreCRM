package com.bizarreelectronics.crm.ui.screens.auth

import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Base64
import timber.log.Timber
import androidx.compose.animation.*
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.VerifiedUser
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.foundation.clickable
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.activity.compose.BackHandler
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.ui.components.WaveDivider
import com.bizarreelectronics.crm.ui.components.auth.LoginPillButton
import com.bizarreelectronics.crm.ui.components.auth.PasswordStrengthMeter
import com.bizarreelectronics.crm.ui.components.shared.BrandPrimaryButton
import com.bizarreelectronics.crm.util.PasswordStrength
import com.bizarreelectronics.crm.ui.theme.BrandMono
import com.bizarreelectronics.crm.ui.theme.LocalExtendedColors
import com.bizarreelectronics.crm.ui.theme.clickableHover
import com.bizarreelectronics.crm.ui.theme.textFieldHover
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.data.remote.dto.*
import android.app.Activity
import android.provider.Settings
import androidx.fragment.app.FragmentActivity
import com.bizarreelectronics.crm.data.local.prefs.BiometricCredentialStore
import com.bizarreelectronics.crm.ui.auth.BiometricAuth
import com.bizarreelectronics.crm.util.ClipboardUtil
import com.bizarreelectronics.crm.util.DeviceBinding
import com.bizarreelectronics.crm.util.NetworkMonitor
import com.bizarreelectronics.crm.util.QrCodeGenerator
import com.bizarreelectronics.crm.util.DeepLinkBus
import com.bizarreelectronics.crm.util.SmsOtpBus
import com.bizarreelectronics.crm.util.SmsRetrieverHelper
import com.bizarreelectronics.crm.util.SsoLauncher
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
    // §2.20 L443 — SSO provider list. Null = not yet loaded. Empty = no SSO on tenant.
    // The "Sign in with SSO" button is visible only when this list is non-empty.
    val ssoProviders: List<SsoProvider>? = null,
    // §2.20 — true while GET /auth/sso/providers is in flight.
    val ssoProvidersLoading: Boolean = false,
    // §2.20 — pending SSO provider picked from the bottom sheet. Cleared after launch.
    val pendingSsoProvider: SsoProvider? = null,
    // §2.20 — true while POST /auth/sso/token-exchange is in flight.
    val ssoExchangeLoading: Boolean = false,
    // §2.20 — CSRF state token generated at launch time, validated on callback.
    val ssoState: String = "",
    // §2.20 — set to true after a successful SSO token exchange. LoginScreen
    // reacts by calling onLoginSuccess() and clearing this flag.
    val ssoLoginSuccess: Boolean = false,

    // §2.21 L454 — Magic-link state.
    // magicLinksEnabled: loaded from GET /tenants/me. Null = not yet probed
    // (show button optimistically). False = tenant disabled; hide button.
    val magicLinksEnabled: Boolean? = null,
    // showMagicLinkSheet: true while the "Email me a link" bottom sheet is open.
    val showMagicLinkSheet: Boolean = false,
    // magicLinkEmail: controlled input in the bottom sheet.
    val magicLinkEmail: String = "",
    // magicLinkSent: true after a successful POST /auth/magic-link/request,
    // switches the sheet to "Check your email" inline banner.
    val magicLinkSent: Boolean = false,
    // magicLinkLoading: true while the request POST is in flight.
    val magicLinkLoading: Boolean = false,
    // magicLinkError: inline error in the bottom sheet.
    val magicLinkError: String? = null,
    // magicLinkResendCooldownMs: System.currentTimeMillis() deadline before resend is allowed.
    // Null = no cooldown active.
    val magicLinkResendCooldownMs: Long? = null,

    // Magic-link exchange state (token arrived from deep link).
    // pendingMagicToken: the raw token from the deep link, pending user confirmation
    // in the phishing-defense preview card.
    val pendingMagicToken: String? = null,
    // magicLinkTenantName: from MagicLinkExchangeResponse.tenantName, shown in preview card.
    val magicLinkTenantName: String? = null,
    // magicLinkExpiresAt: ISO-8601 expiry from exchange response; drives countdown display.
    val magicLinkExpiresAt: String? = null,
    // magicLinkExchangeLoading: true while POST /auth/magic-link/exchange is in flight.
    val magicLinkExchangeLoading: Boolean = false,
    // magicLinkExchangeError: shown in the phishing-defense preview card on failure.
    val magicLinkExchangeError: String? = null,
    // magicLinkLoginSuccess: set to true after a successful same-device exchange.
    val magicLinkLoginSuccess: Boolean = false,

    // §2.22 L463 — Passkey sign-in state.
    // passkeyEnabled: loaded from GET /tenants/me. Null = not yet probed (hide button
    // optimistically — opt-in model; servers that predate this field return false default).
    // False = tenant disabled; hide button. True = show "Use passkey" button.
    val passkeyEnabled: Boolean? = null,
    // passkeyLoading: true while the begin → CredentialManager → finish handshake is in flight.
    val passkeyLoading: Boolean = false,
    // passkeyError: transient error shown below the passkey button.
    val passkeyError: String? = null,
    // passkeyLoginSuccess: set after a successful login/finish; LoginScreen navigates to dashboard.
    val passkeyLoginSuccess: Boolean = false,

    // §2.20 L449 — SSO hybrid email-domain auto-detect.
    // domainSsoDetected: true when the username's email domain maps to an SSO provider.
    //   LoginScreen swaps the password field for "Continue with SSO" button.
    // domainSsoProviderId: the server-returned provider_id to launch with SsoLauncher.
    //   Null when domainSsoDetected is false.
    // domainSsoChecking: true while the debounced GET /auth/sso/check-domain is in flight.
    val domainSsoDetected: Boolean = false,
    val domainSsoProviderId: String? = null,
    val domainSsoChecking: Boolean = false,
)

// ─── ViewModel ──────────────────────────────────────────────────────

@HiltViewModel
class LoginViewModel @Inject constructor(
    private val authPreferences: AuthPreferences,
    private val authApi: AuthApi,
    private val networkMonitor: NetworkMonitor,
    private val biometricCredentialStore: BiometricCredentialStore,
    private val biometricAuth: BiometricAuth,
    private val deepLinkBus: DeepLinkBus,
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
        storeName = authPreferences.storeName ?: "",
        // §2.17-L407/L408 — restore biometric stash preferences from prefs.
        biometricEnabled = authPreferences.biometricCredentialsEnabled,
        // §2.17-L414 — default remember-me to true when TalkBack is active.
        rememberMeChecked = authPreferences.biometricCredentialsEnabled
            || authPreferences.rememberMeDefaultForA11y,
    ))
    val state = _state.asStateFlow()

    init {
        // Diagnostic: log every step transition so the double-Sign-In bug
        // can be reproduced from logcat. `adb logcat -s LoginVM:V` to read.
        viewModelScope.launch {
            var prev: SetupStep? = null
            _state.collect {
                if (it.step != prev) {
                    timber.log.Timber.tag("LoginVM").i("step transition: %s -> %s", prev, it.step)
                    prev = it.step
                }
            }
        }
        // §2.12-L358 — observe device network state and mirror it into uiState.
        // This is purely informational: the offline banner cannot be bypassed
        // because login always requires a real network round-trip.
        viewModelScope.launch {
            networkMonitor.isOnline.collect { online ->
                _state.value = _state.value.copy(networkOffline = !online)
            }
        }

        // §2.20 L443 — load SSO providers on init so the button shows (or hides)
        // before the user reaches the credentials step. 404 is silenced.
        viewModelScope.launch { loadSsoProviders() }

        // §2.21 L454 — probe magic-link feature flag from GET /tenants/me.
        // 404 or any network failure defaults to enabled (opt-out model).
        viewModelScope.launch { probemagicLinksEnabled() }

        // §2.22 L463 — probe passkey feature flag from GET /tenants/me.
        // 404 or any network failure defaults to disabled (opt-in model; hide button).
        viewModelScope.launch { probePasskeyEnabled() }

        // §2.21 L454 — collect magic-link tokens published by MainActivity.
        // DeepLinkBus.publishMagicLinkToken is called when a magic-link URI arrives.
        viewModelScope.launch {
            deepLinkBus.pendingMagicToken.collect { token ->
                if (token != null) {
                    deepLinkBus.consumeMagicToken()
                    _state.value = _state.value.copy(pendingMagicToken = token)
                }
            }
        }

        // §2.20 L446 — collect SSO callbacks published by MainActivity.
        // DeepLinkBus.publishSsoResult is called when bizarrecrm://sso/callback arrives.
        viewModelScope.launch {
            deepLinkBus.pendingSsoResult.collect { result ->
                if (result != null) {
                    deepLinkBus.consumeSsoResult()
                    val currentState = _state.value
                    val pendingProvider = currentState.pendingSsoProvider
                    if (pendingProvider == null) {
                        _state.value = currentState.copy(error = "Sign-in link mismatch. Try again.")
                        return@collect
                    }
                    // CSRF state check
                    if (result.state != currentState.ssoState) {
                        _state.value = currentState.copy(
                            error = "Sign-in link mismatch. Try again.",
                            pendingSsoProvider = null,
                            ssoState = "",
                        )
                        return@collect
                    }
                    exchangeSsoCode(pendingProvider.id, result.code, result.state)
                }
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
    // §2.20 L449 — debounce job for domain SSO check
    private var _domainCheckJob: kotlinx.coroutines.Job? = null

    fun updateUsername(value: String) {
        _state.value = _state.value.copy(
            username = value,
            error = null,
            unreachableHost = false,
            rateLimited = false,
            // Reset domain SSO state when username changes
            domainSsoDetected = false,
            domainSsoProviderId = null,
        )
        // §2.20 L449 — if the username looks like an email, debounce a domain check
        val atIdx = value.indexOf('@')
        if (atIdx > 0) {
            val domain = value.substring(atIdx + 1).trim()
            if (domain.isNotBlank()) {
                _domainCheckJob?.cancel()
                _domainCheckJob = viewModelScope.launch {
                    delay(500L) // 500 ms debounce
                    checkDomainSso(domain)
                }
            }
        }
    }

    /**
     * §2.20 L449 — Calls GET /auth/sso/check-domain?domain=<d>.
     *
     * On [uses_sso = true]: sets [domainSsoDetected] = true + stores [provider_id].
     *   The CREDENTIALS step UI swaps the password field for a "Continue with SSO" button.
     * On 404 or [uses_sso = false]: domain is local-auth only; no UI change.
     * Any network error is silenced — local-auth fallback remains available.
     */
    private suspend fun checkDomainSso(domain: String) {
        _state.value = _state.value.copy(domainSsoChecking = true)
        try {
            val response = authApi.checkSsoDomain(domain)
            val result = response.data
            _state.value = _state.value.copy(
                domainSsoDetected = result?.uses_sso == true,
                domainSsoProviderId = if (result?.uses_sso == true) result.provider_id else null,
                domainSsoChecking = false,
            )
        } catch (e: retrofit2.HttpException) {
            // 404 → domain not in SSO config; treat as local auth
            _state.value = _state.value.copy(
                domainSsoDetected = false,
                domainSsoProviderId = null,
                domainSsoChecking = false,
            )
        } catch (_: Exception) {
            // Network error — silently fall back to local auth
            _state.value = _state.value.copy(domainSsoChecking = false)
        }
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

    /**
     * 2026-04-27 — User-driven backward nav from the LoginTabBar. Tab indexes:
     * 0 = Server (or Register), 1 = Credentials (or SetPassword), 2 = TWO_FA_*.
     * Forward jumps are rejected since later steps require valid intermediate
     * data (URL probed, credentials authenticated). Backward jumps re-use the
     * same state cleanup goBack() does so we don't leak TOTP secrets / 2FA
     * setup data when a user backs all the way to Server from TWO_FA_SETUP.
     */
    fun goToTab(targetIndex: Int) {
        val current = _state.value
        val currentIndex = when (current.step) {
            SetupStep.SERVER, SetupStep.REGISTER -> 0
            SetupStep.CREDENTIALS, SetupStep.SET_PASSWORD -> 1
            SetupStep.TWO_FA_SETUP, SetupStep.TWO_FA_VERIFY -> 2
        }
        if (targetIndex >= currentIndex) return  // forward / same — no-op.
        val targetStep = when (targetIndex) {
            0 -> SetupStep.SERVER
            1 -> SetupStep.CREDENTIALS
            else -> return  // unreachable in practice
        }
        _state.value = current.copy(
            error = null,
            step = targetStep,
            // Same scrub rules as goBack(): clear TOTP secret + register form
            // when leaving those steps, so backing out from a tab tap doesn't
            // leave sensitive in-flight data live.
            registerSubStep = if (current.step == SetupStep.REGISTER) RegisterSubStep.Company else current.registerSubStep,
            twoFaSecret = if (currentIndex == 2) "" else current.twoFaSecret,
            twoFaManualEntry = if (currentIndex == 2) "" else current.twoFaManualEntry,
            qrCodeDataUrl = if (currentIndex == 2) "" else current.qrCodeDataUrl,
        )
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
            // LOGIN-MOCK-189: clear TOTP secret from VM heap when backing out of TWO_FA_SETUP
            // to avoid leaving sensitive data live while the user is back on CREDENTIALS.
            twoFaSecret = if (current.step == SetupStep.TWO_FA_SETUP) "" else current.twoFaSecret,
            twoFaManualEntry = if (current.step == SetupStep.TWO_FA_SETUP) "" else current.twoFaManualEntry,
            qrCodeDataUrl = if (current.step == SetupStep.TWO_FA_SETUP) "" else current.qrCodeDataUrl,
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
                        // LOGIN-MOCK-175: preserve HTTP status code by encoding it in the
                        // exception message so the catch block can detect 409 conflicts.
                        val serverMsg = rJson.optString("message", "Registration failed")
                        throw Exception("HTTP_${response.code}:$serverMsg")
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
                // LOGIN-MOCK-175: distinguish slug conflict (409) from network timeout.
                val rawMsg = e.message ?: "Registration failed"
                val errorMsg = when {
                    rawMsg.startsWith("HTTP_409:") -> {
                        val detail = rawMsg.removePrefix("HTTP_409:")
                        if (detail.isNotBlank()) detail else "That shop URL is already taken. Please choose another."
                    }
                    rawMsg.startsWith("HTTP_") -> {
                        rawMsg.substringAfter(":")
                            .takeIf { it.isNotBlank() } ?: "Registration failed. Please try again."
                    }
                    e is java.net.SocketTimeoutException ||
                    e is java.net.ConnectException ||
                    e is java.net.UnknownHostException ->
                        "Network error. Check your connection and try again."
                    else -> rawMsg
                }
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = errorMsg,
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
        if (s.isLoading) {
            // Double-fire guard: ignore taps while a login round-trip is in flight.
            // Without this, biometric auto-login + manual Sign In can race and the
            // server's second response can briefly stomp the first, surfacing as a
            // "sign-in screen showed twice" UX bug.
            timber.log.Timber.tag("LoginVM").w("login() ignored — already isLoading")
            return
        }
        if (s.username.isBlank()) { _state.value = s.copy(error = "Username is required"); return }
        if (s.password.isBlank()) { _state.value = s.copy(error = "Password is required"); return }

        timber.log.Timber.tag("LoginVM").i("login() start — step=%s", s.step)
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
        // LOGIN-MOCK-168: mark loading immediately so the UI shows a spinner
        _state.value = _state.value.copy(isLoading = true, error = null)
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
                // LOGIN-MOCK-173: on 401 the server returns a fresh challengeToken in the body
                // so the user can retry without restarting login.
                if (e is retrofit2.HttpException && e.code() == 401) {
                    val retryToken = try {
                        val body = e.response()?.errorBody()?.string()
                        if (body != null) JSONObject(body).optJSONObject("data")?.optString("challengeToken", "") else null
                    } catch (_: Exception) { null }
                    if (!retryToken.isNullOrBlank()) {
                        _state.value = _state.value.copy(
                            isLoading = false,
                            totpCode = "",
                            challengeToken = retryToken,
                            error = extractErrorMessage(e),
                        )
                        return@launch
                    }
                }
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

    /**
     * LOGIN-MOCK-174 — Verify a backup code during the 2FA login challenge.
     *
     * Calls POST /auth/login/2fa-backup with the current challengeToken + backup code.
     * On 401 the server issues a fresh challengeToken in the response body so the user
     * can correct the code without restarting login — same retry-token pattern as verify2FA.
     */
    fun verifyBackupCode(onSuccess: () -> Unit) {
        val s = _state.value
        if (s.totpCode.isBlank()) { _state.value = s.copy(error = "Enter your backup code"); return }

        _state.value = s.copy(isLoading = true, error = null)
        viewModelScope.launch {
            try {
                val response = authApi.verify2FABackup(
                    mapOf("challengeToken" to s.challengeToken, "code" to s.totpCode.trim())
                )
                val data = response.data ?: throw Exception(response.message ?: "Verification failed")

                val user = data.user
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
                } else {
                    onSuccess()
                }
            } catch (e: Exception) {
                // LOGIN-MOCK-174: on 401 preserve fresh challengeToken for retry
                if (e is retrofit2.HttpException && e.code() == 401) {
                    val retryToken = try {
                        val body = e.response()?.errorBody()?.string()
                        if (body != null) JSONObject(body).optJSONObject("data")?.optString("challengeToken", "") else null
                    } catch (_: Exception) { null }
                    if (!retryToken.isNullOrBlank()) {
                        _state.value = _state.value.copy(
                            isLoading = false,
                            totpCode = "",
                            challengeToken = retryToken,
                            error = extractErrorMessage(e),
                        )
                        return@launch
                    }
                }
                _state.value = _state.value.copy(
                    isLoading = false,
                    totpCode = "",
                    error = extractErrorMessage(e),
                )
            }
        }
    }

    /** §2.12-L357 — called by the UI countdown LaunchedEffect when the timer reaches zero. */
    fun clearRateLimit() {
        _state.value = _state.value.copy(rateLimited = false, rateLimitResetMs = null, rateLimitScope = null)
    }

    /**
     * LOGIN-MOCK-169 — called by the QR-spinner LaunchedEffect after the 10-second
     * timeout. Re-checks state before firing so a successful load that arrived just
     * before the delay expired does not incorrectly surface the error.
     */
    fun timeoutQrSetupIfStillBlank() {
        val s = _state.value
        if (s.qrCodeDataUrl.isBlank() && s.twoFaSecret.isBlank()) {
            _state.value = s.copy(
                isLoading = false,
                error = "QR code failed to load. Try again or use the manual key below.",
            )
        }
    }

    /**
     * LOGIN-MOCK-169 — re-triggers the 2FA QR setup call (clears error + calls setup2FA).
     * Invoked by the Retry button in TwoFaSetupStep when a timeout has occurred.
     */
    fun retryQrSetup() {
        val s = _state.value
        // Clear error and re-enter loading state so the spinner appears again,
        // then re-invoke setup2FA with the current challengeToken.
        _state.value = s.copy(error = null, qrCodeDataUrl = "", twoFaSecret = "", twoFaManualEntry = "")
        setup2FA(s.challengeToken, s.challengeTokenExpiresAtMs)
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

    // §2.20 — SSO functions

    /**
     * Loads the SSO provider list from GET /auth/sso/providers.
     * 404 → silently hides the "Sign in with SSO" button (no SSO configured on tenant).
     * Any other error is also silenced — SSO is optional; credentials login still works.
     */
    private suspend fun loadSsoProviders() {
        _state.value = _state.value.copy(ssoProvidersLoading = true)
        try {
            val response = authApi.getSsoProviders()
            _state.value = _state.value.copy(
                ssoProviders = response.data?.providers ?: emptyList(),
                ssoProvidersLoading = false,
            )
        } catch (e: retrofit2.HttpException) {
            // 404 = no SSO on this tenant — hide the button silently
            _state.value = _state.value.copy(ssoProviders = emptyList(), ssoProvidersLoading = false)
        } catch (_: Exception) {
            // Network error — hide the button; credentials login still works
            _state.value = _state.value.copy(ssoProviders = emptyList(), ssoProvidersLoading = false)
        }
    }

    /** Clears the SSO success flag after LoginScreen has dispatched onLoginSuccess(). */
    fun clearSsoLoginSuccess() {
        _state.value = _state.value.copy(ssoLoginSuccess = false)
    }

    /** Called from the provider-picker sheet when the user taps an SSO provider. */
    fun launchSsoProvider(activity: Activity, provider: SsoProvider) {
        val state = java.util.UUID.randomUUID().toString().replace("-", "")
        _state.value = _state.value.copy(
            pendingSsoProvider = provider,
            ssoState = state,
            error = null,
        )
        SsoLauncher.launch(activity, provider.authUrl, state)
    }

    /**
     * Exchanges the SSO authorization [code] for tokens via POST /auth/sso/token-exchange.
     * On success: stores accessToken + refreshToken, navigates to dashboard.
     * On state mismatch (400): surfaces "Sign-in link mismatch. Try again."
     * 404 → server doesn't support token exchange yet; surfaces generic error.
     */
    fun exchangeSsoCode(provider: String, code: String, state: String) {
        viewModelScope.launch {
            _state.value = _state.value.copy(ssoExchangeLoading = true, error = null)
            try {
                val response = authApi.tokenExchange(
                    SsoTokenExchangeRequest(provider = provider, code = code, state = state),
                )
                val data = response.data ?: throw Exception("Empty token response")
                authPreferences.saveUser(
                    token = data.accessToken,
                    refreshToken = data.refreshToken,
                    id = data.user.id,
                    username = data.user.username,
                    firstName = data.user.firstName,
                    lastName = data.user.lastName,
                    role = data.user.role,
                )
                _state.value = _state.value.copy(
                    ssoExchangeLoading = false,
                    pendingSsoProvider = null,
                    ssoState = "",
                    ssoLoginSuccess = true,
                )
            } catch (e: retrofit2.HttpException) {
                val msg = when (e.code()) {
                    400  -> "Sign-in link mismatch. Try again."
                    404  -> "SSO token exchange is not supported on this server."
                    else -> "SSO sign-in failed (${e.code()}). Try again."
                }
                _state.value = _state.value.copy(
                    ssoExchangeLoading = false,
                    error = msg,
                    pendingSsoProvider = null,
                    ssoState = "",
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    ssoExchangeLoading = false,
                    error = "SSO sign-in failed: ${e.message}",
                    pendingSsoProvider = null,
                    ssoState = "",
                )
            }
        }
    }

    // endregion

    // region — §2.21 Magic-link

    /**
     * Probes GET /tenants/me for [TenantMeResponse.magicLinksEnabled].
     * 404 or network failure → default to true (opt-out model; button shown).
     */
    private suspend fun probemagicLinksEnabled() {
        try {
            val response = authApi.getTenantMe()
            val enabled = response.data?.magicLinksEnabled ?: false
            _state.value = _state.value.copy(magicLinksEnabled = enabled)
        } catch (_: Exception) {
            // 404 or any failure → treat as disabled (opt-in model; hide button until confirmed).
            _state.value = _state.value.copy(magicLinksEnabled = false)
        }
    }

    // endregion

    // region — §2.22 Passkey sign-in

    /**
     * Probes GET /tenants/me for [TenantMeResponse.passkeyEnabled].
     *
     * Opt-in model: defaults to false when the server predates this field.
     * "Use passkey" button is hidden until the server explicitly opts in.
     */
    private suspend fun probePasskeyEnabled() {
        try {
            val response = authApi.getTenantMe()
            val enabled = response.data?.passkeyEnabled ?: false
            _state.value = _state.value.copy(passkeyEnabled = enabled)
        } catch (_: Exception) {
            // 404 or any failure → hide button (opt-in model).
            _state.value = _state.value.copy(passkeyEnabled = false)
        }
    }

    /**
     * Runs the full passkey sign-in handshake:
     *  1. POST /auth/passkey/login/begin → challenge JSON
     *  2. [PasskeyManager.signInWithPasskey] → CredentialManager get sheet
     *  3. POST /auth/passkey/login/finish → { accessToken, refreshToken, user }
     *
     * On success, sets [passkeyLoginSuccess] = true so the composable navigates
     * to the dashboard. The same auth-storage path used by password login is
     * reused here (authPreferences.saveUser).
     *
     * Password remains as a breakglass path (L468). "Remove password" deferred (L469).
     */
    fun signInWithPasskey(activity: android.app.Activity) {
        if (_state.value.passkeyLoading) return
        _state.value = _state.value.copy(passkeyLoading = true, passkeyError = null)
        viewModelScope.launch {
            try {
                // Step 1: get challenge from server.
                val beginResponse = authApi.beginPasskeyLogin()
                val challengeJson = beginResponse.data?.challengeJson
                    ?: throw Exception("Server returned no passkey challenge")

                // Step 2: present system credential sheet.
                val outcome = com.bizarreelectronics.crm.util.PasskeyManager.signInWithPasskey(
                    activity = activity,
                    challengeJson = challengeJson,
                )

                when (outcome) {
                    is com.bizarreelectronics.crm.util.PasskeyManager.PasskeyOutcome.Success -> {
                        val responseJson = when (val cred = outcome.data.credential) {
                            is androidx.credentials.PublicKeyCredential -> cred.authenticationResponseJson
                            else -> throw Exception("Unexpected credential type: ${cred::class.simpleName}")
                        }
                        // Step 3: exchange assertion with server.
                        val finishResponse = authApi.finishPasskeyLogin(
                            com.bizarreelectronics.crm.data.remote.dto.PasskeyLoginFinishRequest(
                                responseJson = responseJson,
                            )
                        )
                        val tokens = finishResponse.data ?: throw Exception("No token data in passkey login response")
                        val user = tokens.user
                        authPreferences.saveUser(
                            token = tokens.accessToken,
                            refreshToken = tokens.refreshToken,
                            id = user.id,
                            username = user.username,
                            firstName = user.firstName,
                            lastName = user.lastName,
                            role = user.role,
                        )
                        _state.value = _state.value.copy(passkeyLoading = false, passkeyLoginSuccess = true)
                    }
                    is com.bizarreelectronics.crm.util.PasskeyManager.PasskeyOutcome.Cancelled -> {
                        _state.value = _state.value.copy(passkeyLoading = false)
                    }
                    is com.bizarreelectronics.crm.util.PasskeyManager.PasskeyOutcome.NoCredentials -> {
                        _state.value = _state.value.copy(
                            passkeyLoading = false,
                            passkeyError = "No passkey found on this device. Sign in with your password first.",
                        )
                    }
                    is com.bizarreelectronics.crm.util.PasskeyManager.PasskeyOutcome.Unsupported -> {
                        _state.value = _state.value.copy(
                            passkeyLoading = false,
                            passkeyEnabled = false,
                        )
                    }
                    is com.bizarreelectronics.crm.util.PasskeyManager.PasskeyOutcome.Error -> {
                        _state.value = _state.value.copy(
                            passkeyLoading = false,
                            passkeyError = outcome.message,
                        )
                    }
                }
            } catch (e: retrofit2.HttpException) {
                val msg = when (e.code()) {
                    404 -> "Passkey login is not available on this server."
                    401 -> "Passkey not recognized. Try again or use your password."
                    else -> "Passkey sign-in failed (${e.code()})."
                }
                _state.value = _state.value.copy(passkeyLoading = false, passkeyError = msg)
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    passkeyLoading = false,
                    passkeyError = "Passkey sign-in failed: ${e.message}",
                )
            }
        }
    }

    fun clearPasskeyError() {
        _state.value = _state.value.copy(passkeyError = null)
    }

    /** LOGIN-MOCK-165: dismiss the setup-needed banner. Sets setupNeeded=false locally. */
    fun dismissSetupNeededBanner() {
        _state.value = _state.value.copy(setupNeeded = false)
    }

    fun clearPasskeyLoginSuccess() {
        _state.value = _state.value.copy(passkeyLoginSuccess = false)
    }

    // endregion — passkey

    // region — §2.21 Magic-link (continued)

    fun updateMagicLinkEmail(value: String) {
        _state.value = _state.value.copy(magicLinkEmail = value, magicLinkError = null)
    }

    fun openMagicLinkSheet() {
        _state.value = _state.value.copy(
            showMagicLinkSheet = true,
            magicLinkEmail = "",
            magicLinkSent = false,
            magicLinkError = null,
            magicLinkResendCooldownMs = null,
        )
    }

    fun closeMagicLinkSheet() {
        _state.value = _state.value.copy(
            showMagicLinkSheet = false,
            magicLinkEmail = "",
            magicLinkSent = false,
            magicLinkError = null,
            magicLinkResendCooldownMs = null,
        )
    }

    /**
     * Sends POST /auth/magic-link/request {email}.
     * On success: shows "Check your email" banner and starts 30-second resend cooldown.
     * 404 → feature disabled; surfaces graceful error.
     */
    fun requestMagicLink() {
        val s = _state.value
        val emailRegex = Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")
        val email = s.magicLinkEmail.trim()
        if (email.isBlank() || !emailRegex.matches(email)) {
            _state.value = s.copy(magicLinkError = "Enter a valid email address")
            return
        }
        _state.value = s.copy(magicLinkLoading = true, magicLinkError = null)
        viewModelScope.launch {
            try {
                authApi.requestMagicLink(
                    com.bizarreelectronics.crm.data.remote.dto.MagicLinkRequest(email = email),
                )
                _state.value = _state.value.copy(
                    magicLinkLoading = false,
                    magicLinkSent = true,
                    magicLinkResendCooldownMs = System.currentTimeMillis() + 30_000L,
                )
            } catch (e: retrofit2.HttpException) {
                val msg = when (e.code()) {
                    404  -> "Magic-link login is not available on this server."
                    429  -> "Too many requests. Please wait before trying again."
                    else -> "Failed to send link (${e.code()}). Try again."
                }
                _state.value = _state.value.copy(magicLinkLoading = false, magicLinkError = msg)
            } catch (_: Exception) {
                _state.value = _state.value.copy(
                    magicLinkLoading = false,
                    magicLinkError = "Could not send the link. Check your connection.",
                )
            }
        }
    }

    /** Clears the resend cooldown after the timer expires. */
    fun clearMagicLinkResendCooldown() {
        _state.value = _state.value.copy(magicLinkResendCooldownMs = null)
    }

    /**
     * Called by the phishing-defense preview card when the user taps "Continue".
     * Validates token regex then calls POST /auth/magic-link/exchange.
     *
     * Same-device (server fingerprint matches) → [TwoFactorResponse] tokens issued;
     * set magicLinkLoginSuccess = true.
     * Different device → server returns requires_2fa = true; advance to TWO_FA_VERIFY.
     * 404 → feature disabled; surface error.
     */
    fun exchangeMagicLink(context: android.content.Context) {
        val s = _state.value
        val token = s.pendingMagicToken ?: return
        // Client-side token shape guard (belt-and-suspenders; server validates too).
        val tokenPattern = Regex("^[A-Za-z0-9_-]{20,128}$")
        if (!tokenPattern.matches(token)) {
            _state.value = s.copy(
                magicLinkExchangeError = "Invalid sign-in link. Request a new one.",
                pendingMagicToken = null,
            )
            return
        }
        val fingerprint = DeviceBinding.fingerprint(context)
        _state.value = s.copy(magicLinkExchangeLoading = true, magicLinkExchangeError = null)
        viewModelScope.launch {
            try {
                val response = authApi.exchangeMagicLink(
                    com.bizarreelectronics.crm.data.remote.dto.MagicLinkTokenExchange(
                        token = token,
                        deviceFingerprint = fingerprint,
                    ),
                )
                val data = response.data ?: throw Exception("Empty exchange response")
                if (data.requires2fa) {
                    // Different-device path: push to 2FA verify step.
                    val challengeToken = data.challengeToken
                        ?: throw Exception("No challenge token for 2FA")
                    _state.value = _state.value.copy(
                        magicLinkExchangeLoading = false,
                        pendingMagicToken = null,
                        challengeToken = challengeToken,
                        challengeTokenExpiresAtMs = System.currentTimeMillis() + 600_000L,
                        challengeExpired = false,
                        step = SetupStep.TWO_FA_VERIFY,
                    )
                } else {
                    // Same-device path: tokens issued immediately.
                    val accessToken = data.accessToken
                        ?: throw Exception("No access token in exchange response")
                    val user = data.user ?: throw Exception("No user in exchange response")
                    authPreferences.saveUser(
                        token = accessToken,
                        refreshToken = data.refreshToken,
                        id = user.id,
                        username = user.username,
                        firstName = user.firstName,
                        lastName = user.lastName,
                        role = user.role,
                    )
                    _state.value = _state.value.copy(
                        magicLinkExchangeLoading = false,
                        pendingMagicToken = null,
                        magicLinkLoginSuccess = true,
                    )
                }
            } catch (e: retrofit2.HttpException) {
                val msg = when (e.code()) {
                    404  -> "Magic-link login is not available on this server."
                    410  -> "This sign-in link has expired or already been used. Request a new one."
                    else -> "Sign-in failed (${e.code()}). Request a new link."
                }
                _state.value = _state.value.copy(
                    magicLinkExchangeLoading = false,
                    magicLinkExchangeError = msg,
                    pendingMagicToken = null,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    magicLinkExchangeLoading = false,
                    magicLinkExchangeError = "Sign-in failed: ${e.message}",
                    pendingMagicToken = null,
                )
            }
        }
    }

    fun dismissMagicLinkPreview() {
        _state.value = _state.value.copy(
            pendingMagicToken = null,
            magicLinkExchangeError = null,
        )
    }

    fun clearMagicLinkLoginSuccess() {
        _state.value = _state.value.copy(magicLinkLoginSuccess = false)
    }

    // endregion

    private fun extractErrorMessage(e: Exception): String {
        // Try to extract server error message from Retrofit HttpException
        if (e is retrofit2.HttpException) {
            val body = e.response()?.errorBody()?.string()
            if (body != null) {
                try {
                    val serverMsg = JSONObject(body).optString("message", e.message ?: "Request failed")
                    return friendlyErrorMessage(serverMsg)
                } catch (_: Exception) {}
            }
            return "Server error (${e.code()})"
        }
        return friendlyErrorMessage(e.message ?: "An error occurred")
    }

    // LOGIN-MOCK-167 — maps raw server error strings to brand-friendly copy.
    private fun friendlyErrorMessage(serverMsg: String): String = when (serverMsg) {
        "Origin header required"    -> "Connection blocked. Restart the app or contact support."
        "Invalid credentials"       -> "Username or password incorrect."
        "Challenge expired"         -> "Sign-in timed out. Please start again."
        "TOTP not configured"       -> "Two-factor auth is not set up on this account."
        "Invalid code"              -> "That code is incorrect. Please try again."
        "No backup codes available" -> "No backup codes left. Contact your admin."
        "Invalid backup code"       -> "That backup code is incorrect."
        "Account locked"            -> "This account is locked. Contact your admin."
        else                        -> "Sign-in error: $serverMsg"
    }
}

// ─── UI ─────────────────────────────────────────────────────────────

@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
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
    // LOGIN-MOCK-148: haptic for biometric auth events in this scope.
    val haptic = LocalHapticFeedback.current
    // LOGIN-MOCK-153: Reduce Motion guard. Read ANIMATOR_DURATION_SCALE once per
    // composition; value rarely changes mid-session. Cache via remember.
    val isReduceMotion = remember {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
    val animDuration = if (isReduceMotion) 0 else 300

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
            // LOGIN-MOCK-148: success haptic after biometric stash resolves.
            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
            onLoginSuccess()
        }
    }

    // §2.17-L407 — biometric auto-login: attempt on first composition when stored creds exist.
    LaunchedEffect(Unit) {
        val activity = (context as? FragmentActivity)
        if (activity != null) {
            // LOGIN-MOCK-148: success haptic on biometric auto-login.
            viewModel.attemptBiometricAutoLogin(activity, onSuccess = {
                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                onLoginSuccess()
            })
        }
    }

    // §2.20 L447 — SSO token-exchange success: navigate to dashboard.
    val ssoLoginSuccess = state.ssoLoginSuccess
    LaunchedEffect(ssoLoginSuccess) {
        if (ssoLoginSuccess) {
            viewModel.clearSsoLoginSuccess()
            onLoginSuccess()
        }
    }

    // §2.21 L454 — magic-link same-device exchange success: navigate to dashboard.
    val magicLinkLoginSuccess = state.magicLinkLoginSuccess
    LaunchedEffect(magicLinkLoginSuccess) {
        if (magicLinkLoginSuccess) {
            viewModel.clearMagicLinkLoginSuccess()
            onLoginSuccess()
        }
    }

    // §2.22 L463 — passkey login success: navigate to dashboard.
    val passkeyLoginSuccess = state.passkeyLoginSuccess
    LaunchedEffect(passkeyLoginSuccess) {
        if (passkeyLoginSuccess) {
            viewModel.clearPasskeyLoginSuccess()
            onLoginSuccess()
        }
    }

    // §2.21 L454 — phishing-defense preview card: shown when a magic-link token
    // arrives via deep link (pendingMagicToken != null). The card is rendered as
    // a full-screen overlay so it pre-empts any other content.
    val pendingMagicToken = state.pendingMagicToken
    if (pendingMagicToken != null) {
        MagicLinkPreviewDialog(
            token = pendingMagicToken,
            tenantName = state.magicLinkTenantName,
            expiresAt = state.magicLinkExpiresAt,
            isLoading = state.magicLinkExchangeLoading,
            error = state.magicLinkExchangeError,
            onConfirm = { viewModel.exchangeMagicLink(context) },
            onDismiss = { viewModel.dismissMagicLinkPreview() },
        )
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
    // §23.5 standaloneModal: contentWindowInsets = WindowInsets(0) so the Scaffold's
    // default safeDrawing inset does not double-count with the explicit safeDrawingPadding()
    // below. (LoginScreen sits outside the NavHost — there is no parent Scaffold above.)
    // The previous combo (default safeDrawing innerPadding + .imePadding()) added the IME
    // inset twice, leaving a dark blank band masking the Connect button when the keyboard
    // was open. See ScaffoldInsetsDefaults.standaloneModal KDoc for the full strategy.
    Scaffold(
        snackbarHost = {
            // LOGIN-MOCK-150: wrap each snackbar in SwipeToDismissBox so the user can
            // swipe it away instead of waiting for the auto-dismiss timer.
            SnackbarHost(hostState = snackbarHostState) { data ->
                val dismissState = rememberSwipeToDismissBoxState()
                LaunchedEffect(dismissState.currentValue) {
                    if (dismissState.currentValue != SwipeToDismissBoxValue.Settled) {
                        data.dismiss()
                    }
                }
                SwipeToDismissBox(
                    state = dismissState,
                    backgroundContent = {},
                ) {
                    Snackbar(snackbarData = data)
                }
            }
        },
        containerColor = MaterialTheme.colorScheme.background,
        contentWindowInsets = com.bizarreelectronics.crm.util.ScaffoldInsetsDefaults.standaloneModal,
    ) { innerPadding ->
    Box(
        modifier = Modifier.fillMaxSize().padding(innerPadding)
            .safeDrawingPadding(),
        // LOGIN-MOCK-114: changed Center → TopCenter so the card is always reachable
        // by scrolling when the keyboard is up. Alignment.Center pins the column at
        // the vertical midpoint of the *remaining* Box height, which can push the
        // Connect button + footer row under the IME on shorter phones (screens 07/08).
        contentAlignment = Alignment.TopCenter,
    ) {
        // 2026-04-27: when IME is open we collapse the wordmark + top breathing
        // room AND auto-scroll the column to its bottom so the active form's
        // footer (Connect / Sign In / 2FA action row + supporting links) stays
        // above the keyboard. Compose's per-field BringIntoViewRequester only
        // scrolls the focused TextField into view, not its sibling buttons
        // below — leaving the CTA hidden on small-DPI / shorter screens.
        val imeVisible = WindowInsets.isImeVisible
        val scrollState = rememberScrollState()
        LaunchedEffect(imeVisible, state.step) {
            if (imeVisible) {
                // Wait one frame for the IME-resize to propagate, then scroll
                // the column to its new max so the bottom of the card is in
                // view. Using animateScrollTo so the motion is smooth and
                // tracks the IME-open animation.
                kotlinx.coroutines.delay(50L)
                scrollState.animateScrollTo(scrollState.maxValue)
            } else {
                // 2026-04-27 user-flagged: previously when the IME closed the
                // scroll position stayed at maxValue, leaving the wordmark
                // clipped above the viewport. Snap back to the top so the
                // header always sits where it belongs when the keyboard is
                // dismissed.
                scrollState.animateScrollTo(0)
            }
        }
        // 2026-04-27 user-flagged jitter: when IME closed (back press), wordmark
        // would visually leap because three independent dp/visibility flips ran
        // in one frame — outer Column vertical padding, top spacer, and the
        // WaveDivider band. Animate the dp values + fade the wave so the
        // wordmark never appears to teleport. Reduce Motion (ANIMATOR_DURATION_SCALE=0)
        // collapses to 0ms — instant swap with no trail, matching the rest of
        // the screen's reduce-motion contract.
        val tween = androidx.compose.animation.core.tween<Dp>(durationMillis = animDuration)
        val outerVertical by androidx.compose.animation.core.animateDpAsState(
            targetValue = if (imeVisible) 8.dp else 24.dp,
            animationSpec = tween,
            label = "login_outer_vpad",
        )
        val topSpacer by androidx.compose.animation.core.animateDpAsState(
            targetValue = if (imeVisible) 0.dp else 32.dp,
            animationSpec = tween,
            label = "login_top_spacer",
        )
        val waveSpacerBelow by androidx.compose.animation.core.animateDpAsState(
            targetValue = if (imeVisible) 8.dp else 12.dp,
            animationSpec = tween,
            label = "login_wave_below",
        )
        Column(
            modifier = Modifier
                .widthIn(max = 420.dp)
                .padding(horizontal = 16.dp)
                .padding(vertical = outerVertical)
                .verticalScroll(scrollState),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // Logo / App name — small top breathing room replaces the old 80dp pin.
            Spacer(Modifier.height(topSpacer))
            // LOGIN-MOCK-097/054: merge wordmark + subtitle into one TalkBack heading stop.
            Column(modifier = Modifier.semantics(mergeDescendants = true) { heading() }) {
                Text(
                    "Bizarre CRM",
                    style = MaterialTheme.typography.headlineLarge,
                    color = MaterialTheme.colorScheme.onBackground,
                    maxLines = 2,
                    softWrap = true,
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    "Electronics Repair Management",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            // 2026-04-27 — WaveDivider under the wordmark removed; the new
            // LinearWavyProgressIndicator step indicator on LoginTabBar is now
            // the single brand wave on the screen ("only one wave at a time"
            // rule from feedback_brand_color memory).
            Spacer(Modifier.height(waveSpacerBelow))

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
                            contentDescription = "Sign-out icon",
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
                        TextButton(onClick = onSessionBannerDismissed, modifier = Modifier.clickableHover()) {
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
                            contentDescription = "Device changed icon",
                            tint = MaterialTheme.colorScheme.onErrorContainer,
                        )
                        Text(
                            text = "Biometric sign-in was disabled because this device changed. Sign in with your password to re-enable.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onErrorContainer,
                            modifier = Modifier.weight(1f),
                        )
                        TextButton(onClick = viewModel::dismissDeviceChangedBanner, modifier = Modifier.clickableHover()) {
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
                            contentDescription = "Sign-out icon",
                            tint = MaterialTheme.colorScheme.onErrorContainer,
                        )
                        Text(
                            text = "Signed out on another device.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onErrorContainer,
                            modifier = Modifier.weight(1f),
                        )
                        TextButton(onClick = viewModel::dismissServerRevokeBanner, modifier = Modifier.clickableHover()) {
                            Text("Dismiss")
                        }
                    }
                }
                Spacer(Modifier.height(16.dp))
            }

            // Tab strip — Server | Sign In | 2FA
            // LOGIN-MOCK-153: pass animDuration so tab indicator respects Reduce Motion.
            LoginTabBar(
                currentStep = state.step,
                animDuration = animDuration,
                onTabClick = viewModel::goToTab,
            )
            Spacer(Modifier.height(12.dp)) // LOGIN-MOCK-272: 24→12dp to match mockup

            // Step content with animation
            AnimatedContent(
                targetState = state.step,
                transitionSpec = {
                    // 2026-04-27 perf: shortened to a single 180ms cross-fade
                    // (was 300ms slide + delayed fadeIn + 150ms fadeOut). The
                    // earlier triple-animation spec triggered ~5 simultaneous
                    // animations on overlapping subtrees + animateContentSize
                    // remeasures, eating frame budget on 90Hz devices and
                    // causing visible jitter (~15fps perceived). Plain fade is
                    // cheaper and the user lands on the new step faster.
                    // Reduce Motion: animDuration=0 collapses to instant swap.
                    fadeIn(animationSpec = tween(animDuration)) togetherWith
                        fadeOut(animationSpec = tween(animDuration))
                },
                // AND-038: contentKey ensures AnimatedContent remeasures correctly
                // when transitioning between enum values with the same ordinal index.
                contentKey = { it.ordinal },
                label = "step",
            ) { step ->
                // LOGIN-MOCK-099: intercept predictive-back / hardware Back to navigate
                // between steps instead of exiting the login screen entirely.
                val isNotFirstStep = step != SetupStep.SERVER
                BackHandler(enabled = isNotFirstStep) { viewModel.goBack() }

                Surface(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(20.dp),
                    color = MaterialTheme.colorScheme.surfaceContainer,
                ) {
                    // LOGIN-MOCK-051/107: 24dp horizontal × 20dp vertical card
                    // padding. animateContentSize was previously layered on top
                    // of the AnimatedContent slide+fade — that combination
                    // remeasured the entire form subtree every frame on step
                    // transitions, causing ~15fps perceived jitter on 90Hz
                    // devices (user-flagged 2026-04-27). Removed; the new
                    // single-fade transition crossfades the cards in place,
                    // and any height delta is masked by the fade itself.
                    Column(modifier = Modifier.padding(horizontal = 24.dp, vertical = 20.dp)) {
                        when (step) {
                            SetupStep.SERVER -> ServerStep(state, viewModel)
                            SetupStep.REGISTER -> RegisterStep(state, viewModel, onLoginSuccess)
                            SetupStep.CREDENTIALS -> CredentialsStep(state, viewModel)
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

/**
 * LoginTabBar — Material3 TabRow replacing the old StepIndicator bar+text widget.
 *
 * Three tabs: Server | Sign In | 2FA.
 * Active tab: cream (#FDEED0) text + 2dp cream underline indicator
 *   — driven by MaterialTheme.colorScheme.primary (= cream in BizarreCrmTheme).
 * Inactive tabs: muted onSurfaceVariant text + faint divider underline.
 * Container is transparent so it blends with the screen background.
 */
/**
 * 2026-04-27 — Replaced TabRow with a M3 Expressive
 * [androidx.compose.material3.LinearWavyProgressIndicator] step indicator.
 * The wave doubles as the brand wave (the WaveDivider under the wordmark
 * was removed so there's exactly one wave on screen).
 *
 * Layout from top:
 *   1. 3 caption labels (Server / Sign In / 2FA), each in its own equal
 *      column. Past = onSurface (cream-tappable). Active = primary cream
 *      bold. Future = onSurfaceVariant 0.45α + disabled().
 *   2. LinearWavyProgressIndicator with progress = (currentIndex + 1) / 3.
 *   3. "Step N of 3" caption row.
 *
 * Tappable behaviour mirrors the prior TabRow: past captions fire
 * onTabClick → ViewModel.goToTab; future captions are inert and carry
 * disabled() semantics for TalkBack.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3ExpressiveApi::class)
@Composable
private fun LoginTabBar(
    currentStep: SetupStep,
    animDuration: Int = 300,
    onTabClick: (Int) -> Unit = {},
) {
    val tabLabels = listOf("Server", "Sign In", "2FA")
    val selectedIndex = when (currentStep) {
        SetupStep.SERVER, SetupStep.REGISTER -> 0
        SetupStep.CREDENTIALS, SetupStep.SET_PASSWORD -> 1
        SetupStep.TWO_FA_SETUP, SetupStep.TWO_FA_VERIFY -> 2
    }

    val activeColor = MaterialTheme.colorScheme.primary
    val onSurface = MaterialTheme.colorScheme.onSurface
    val inactiveColor = MaterialTheme.colorScheme.onSurfaceVariant
    val trackColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f)

    // Progress fraction: animate to (selectedIndex + 1) / 3 so the wavy bar
    // glides between steps instead of jumping. Reduce Motion (animDuration=0)
    // collapses the tween to a snap.
    val targetFraction = (selectedIndex + 1) / 3f
    val animatedProgress by androidx.compose.animation.core.animateFloatAsState(
        targetValue = targetFraction,
        animationSpec = tween(durationMillis = animDuration),
        label = "login_step_progress",
    )

    Column(modifier = Modifier.fillMaxWidth()) {
        // ── Caption row: 3 equal columns, tappable for past steps ─────────
        Row(modifier = Modifier.fillMaxWidth()) {
            tabLabels.forEachIndexed { index, label ->
                val isSelected = index == selectedIndex
                val isFuture = index > selectedIndex
                val isPast = index < selectedIndex

                val labelColor = when {
                    isSelected -> activeColor
                    isFuture -> inactiveColor.copy(alpha = 0.45f)
                    else -> onSurface
                }

                val tapModifier = if (isPast) {
                    Modifier.clickable(
                        onClickLabel = "Go back to $label step",
                    ) { onTabClick(index) }
                } else Modifier

                Box(
                    modifier = Modifier
                        .weight(1f)
                        .then(tapModifier)
                        .padding(vertical = 8.dp)
                        .semantics {
                            role = Role.Tab
                            selected = isSelected
                            if (isSelected || isFuture) disabled()
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = label,
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Medium,
                        color = labelColor,
                    )
                }
            }
        }

        // ── Wavy progress indicator (M3 Expressive) ────────────────────────
        // The "Step N of 3" caption is intentionally omitted: caption labels
        // above already convey the same info, and the extra row was pushing
        // the form card off the top of the screen on shorter phones. The
        // contentDescription on the progress bar still announces step N/3 to
        // TalkBack, so a11y is preserved.
        androidx.compose.material3.LinearWavyProgressIndicator(
            progress = { animatedProgress },
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 4.dp)
                .semantics {
                    contentDescription =
                        "Step ${selectedIndex + 1} of ${tabLabels.size}, ${tabLabels[selectedIndex]}"
                },
            color = activeColor,
            trackColor = trackColor,
            waveSpeed = 5.dp,
        )
    }
}

@Composable
private fun ErrorMessage(error: String?) {
    // LOGIN-MOCK-144: AnimatedVisibility gives the error a fade+expand entrance so
    // validation failures draw attention without a jarring instant-appear.
    // Spacer is outside AnimatedVisibility to prevent layout jump when error appears.
    // LOGIN-MOCK-153: collapse animation durations when Reduce Motion is enabled.
    val ctx = LocalContext.current
    val errAnimDuration = remember {
        if (Settings.Global.getFloat(ctx.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f) 0 else 150
    }
    val errExpandDuration = remember {
        if (Settings.Global.getFloat(ctx.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f) 0 else 200
    }
    AnimatedVisibility(
        visible = error != null,
        enter = fadeIn(animationSpec = tween(errAnimDuration)) + expandVertically(animationSpec = tween(errExpandDuration)),
        exit = fadeOut(animationSpec = tween(errAnimDuration)) + shrinkVertically(animationSpec = tween(errAnimDuration)),
    ) {
        Column {
            Spacer(Modifier.height(12.dp))
            // LOGIN-MOCK-091: liveRegion=Polite ensures TalkBack announces the error
            // when it first appears without interrupting ongoing speech.
            Text(
                error ?: "",
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
            )
        }
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

    // LOGIN-MOCK-098/055: merge title + subtitle into one TalkBack heading stop.
    Column(modifier = Modifier.semantics(mergeDescendants = true) { heading() }) {
        Text(
            "Connect to Your Shop",
            // LOGIN-MOCK-129: drop fontSize = 22.sp override — BizarreTypography.titleLarge
            // is already 22sp; redundant override defeats fontScale scaling.
            style = MaterialTheme.typography.titleLarge.copy(
                fontWeight = FontWeight.Bold,
            ),
            color = MaterialTheme.colorScheme.onSurface,
        )
        Spacer(Modifier.height(4.dp))
        Text(
            if (state.useCustomServer) "Enter your self-hosted server address"
            else "Enter your shop name to connect",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
    Spacer(Modifier.height(16.dp))

    if (state.useCustomServer) {
        // Custom server mode — full URL input (self-hosted)
        OutlinedTextField(
            value = state.serverUrl,
            onValueChange = viewModel::updateServerUrl,
            label = { Text("Server URL") },
            placeholder = { Text("https://192.168.0.240:443") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth().focusRequester(focusRequester).textFieldHover(),
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
            modifier = Modifier.fillMaxWidth().focusRequester(focusRequester).textFieldHover(),
            leadingIcon = { Icon(Icons.Default.Store, null) },
            suffix = {
                // LOGIN-MOCK-108: bodyLarge (16sp) matches OutlinedTextField value text size.
                // LOGIN-MOCK-133: LTR override prevents domain suffix from mirroring in RTL.
                CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
                    Text(
                        ".$CLOUD_DOMAIN",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        style = MaterialTheme.typography.bodyLarge,
                    )
                }
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

    val isConnectEnabled = if (state.useCustomServer) state.serverUrl.isNotBlank() && !state.isLoading
                           else state.shopSlug.length >= 3 && !state.isLoading
    LoginPillButton(
        onClick = viewModel::connectToServer,
        enabled = isConnectEnabled,
        isLoading = state.isLoading,
        label = "Connect",
    )

    Spacer(Modifier.height(12.dp))

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        TextButton(onClick = viewModel::toggleCustomServer, modifier = Modifier.clickableHover()) {
            Text(
                if (state.useCustomServer) "Use BizarreCRM Cloud" else "Self-hosted?",
                style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold),
            )
        }
        if (!state.useCustomServer) {
            TextButton(onClick = viewModel::goToRegister, modifier = Modifier.clickableHover()) {
                Text("Register new shop", style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold))
            }
        }
    }
    Spacer(Modifier.height(4.dp)) // LOGIN-MOCK-278: bottom card clearance
}

// ─── Step 1b: Register New Shop (single form) ───────────────────────
// Mockup parity: one card, 4 fields visible at once — no sub-step wizard.

@Composable
private fun RegisterStep(state: LoginUiState, viewModel: LoginViewModel, onLoginSuccess: () -> Unit) {
    val focusManager = LocalFocusManager.current
    // LOGIN-MOCK-187: rememberSaveable survives rotation / config changes.
    var showPassword by rememberSaveable { mutableStateOf(false) }
    // LOGIN-MOCK-094: auto-focus Shop URL field on entry so TalkBack users don't
    // have to swipe through heading nodes before reaching the first input.
    val shopUrlFocusRequester = remember { FocusRequester() }
    LaunchedEffect(Unit) { shopUrlFocusRequester.requestFocus() }

    // LOGIN-MOCK-176: per-field validation state (only shown after the field is touched)
    val shopSlugError = state.shopSlug.isNotBlank() &&
        (state.shopSlug.length < 3 || state.shopSlug.length > 30 ||
         !state.shopSlug.matches(Regex("^[a-z0-9-]+$")))
    val emailRegex = Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")
    val emailError = state.registerEmail.isNotBlank() && !emailRegex.matches(state.registerEmail.trim())
    val passwordError = state.registerPassword.isNotBlank() && state.registerPassword.length < 8

    // LOGIN-MOCK-161: welcome banner for setup invite token.
    // Shown above the heading when an invite token was delivered via deep link so the
    // user knows they are completing a shop invite rather than a self-registration.
    if (state.registerSetupToken != null) {
        Surface(
            color = MaterialTheme.colorScheme.secondaryContainer,
            shape = MaterialTheme.shapes.small,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(
                text = "Welcome — completing your shop invite.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSecondaryContainer,
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            )
        }
        Spacer(Modifier.height(12.dp))
    }

    // Header row: back arrow + title
    // LOGIN-MOCK-098/055: title + subtitle merged into one heading stop; back arrow
    // sits outside the merged Column so it remains independently focusable.
    Row(verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = viewModel::goBack, modifier = Modifier.clickableHover()) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", modifier = Modifier.size(20.dp))
        }
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.semantics(mergeDescendants = true) { heading() }) {
            Text(
                text = "Register New Shop",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                text = "Create your repair shop on Bizarre CRM",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
    Spacer(Modifier.height(20.dp)) // LOGIN-MOCK-104: 16→20dp to match 20dp inter-field rhythm

    // Field 1: Shop URL
    OutlinedTextField(
        value = state.shopSlug,
        onValueChange = viewModel::updateShopSlug,
        label = { Text("Shop URL") },
        singleLine = true,
        // LOGIN-MOCK-094: shopUrlFocusRequester for auto-focus on card entry.
        modifier = Modifier.fillMaxWidth().focusRequester(shopUrlFocusRequester).textFieldHover(),
        leadingIcon = { Icon(Icons.Outlined.Link, contentDescription = null) },
        isError = shopSlugError,
        suffix = {
            // LOGIN-MOCK-108: bodyLarge (16sp) matches OutlinedTextField value text size.
            // LOGIN-MOCK-133: LTR override prevents domain suffix from mirroring in RTL.
            CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
                Text(
                    ".$CLOUD_DOMAIN",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.bodyLarge,
                )
            }
        },
        // LOGIN-MOCK-176: show error message when invalid, helper copy otherwise
        supportingText = {
            if (shopSlugError) Text("Lowercase letters, numbers, hyphens only")
            else Text("3-30 characters: letters, numbers, hyphens")
        },
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
        keyboardActions = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Down) }),
    )
    // LOGIN-MOCK-273: M3 supportingText already renders ~16dp bottom clearance; adding
    // 20dp here produces a ~36dp compound gap that exceeds every other inter-field distance.
    // Reduce to 4dp so the visual gap matches the 8dp shown in mockups screens 02–05.
    Spacer(Modifier.height(4.dp))

    // Field 2: Shop Display Name
    OutlinedTextField(
        value = state.registerShopName,
        onValueChange = viewModel::updateRegisterShopName,
        label = { Text("Shop Display Name") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth().textFieldHover(),
        leadingIcon = { Icon(Icons.Default.Store, contentDescription = null) },
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
        keyboardActions = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Down) }),
    )
    Spacer(Modifier.height(20.dp))

    // Field 3: Admin Email
    OutlinedTextField(
        value = state.registerEmail,
        onValueChange = viewModel::updateRegisterEmail,
        label = { Text("Admin Email") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth().textFieldHover(),
        isError = emailError,
        leadingIcon = { Icon(Icons.Default.Email, contentDescription = null) },
        // LOGIN-MOCK-176: inline email validation
        supportingText = { if (emailError) Text("Enter a valid email address") },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email, imeAction = ImeAction.Next),
        keyboardActions = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Down) }),
    )
    Spacer(Modifier.height(20.dp))

    // Field 4: Admin Password
    OutlinedTextField(
        value = state.registerPassword,
        onValueChange = viewModel::updateRegisterPassword,
        label = { Text("Admin Password") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth().textFieldHover(),
        isError = passwordError,
        leadingIcon = { Icon(Icons.Default.Lock, contentDescription = null) },
        visualTransformation = if (showPassword) VisualTransformation.None else PasswordVisualTransformation(),
        trailingIcon = {
            // LOGIN-MOCK-093: stateful contentDescription so TalkBack announces
            // the resulting visibility state, not a generic static label.
            IconButton(onClick = { showPassword = !showPassword }, modifier = Modifier.clickableHover()) {
                Icon(
                    if (showPassword) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                    contentDescription = if (showPassword) "Hide password" else "Show password",
                )
            }
        },
        // LOGIN-MOCK-176: show error when too short, helper copy otherwise
        supportingText = {
            if (passwordError) Text("Password must be at least 8 characters")
            else Text("Minimum 8 characters")
        },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done),
        // LOGIN-MOCK-090(F): onDone was calling clearFocus() only — hardware-keyboard
        // Enter did nothing. Now submits if the form is valid, else clears focus.
        keyboardActions = KeyboardActions(onDone = {
            val canSubmit = state.shopSlug.length >= 3
                && state.registerShopName.isNotBlank()
                && state.registerEmail.isNotBlank()
                && state.registerPassword.length >= 8
                && !state.isLoading
            if (canSubmit) viewModel.registerShop(onAutoLogin = onLoginSuccess)
            else focusManager.clearFocus()
        }),
    )
    // LOGIN-MOCK-273: password supportingText has built-in bottom clearance; without an
    // explicit spacer the error text runs flush to the helper line. 4dp gives breathing room
    // consistent with the 4dp clearance used after the Shop URL supportingText above.
    Spacer(Modifier.height(4.dp))

    // Error shown between password helper and Create Shop button
    // LOGIN-MOCK-091: liveRegion=Polite so TalkBack announces this error on appearance.
    // LOGIN-MOCK-144: AnimatedVisibility gives the inline error a fade+expand entrance.
    // LOGIN-MOCK-153: collapse durations when Reduce Motion is enabled.
    val regErrCtx = LocalContext.current
    val regErrAnimDuration = remember {
        if (Settings.Global.getFloat(regErrCtx.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f) 0 else 150
    }
    val regErrExpandDuration = remember {
        if (Settings.Global.getFloat(regErrCtx.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f) 0 else 200
    }
    AnimatedVisibility(
        visible = state.error != null,
        enter = fadeIn(animationSpec = tween(regErrAnimDuration)) + expandVertically(animationSpec = tween(regErrExpandDuration)),
        exit = fadeOut(animationSpec = tween(regErrAnimDuration)) + shrinkVertically(animationSpec = tween(regErrAnimDuration)),
    ) {
        Text(
            text = state.error ?: "",
            color = MaterialTheme.colorScheme.error,
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.fillMaxWidth().semantics { liveRegion = LiveRegionMode.Polite },
        )
    }

    // LOGIN-MOCK-273: collapse to 8dp above the Create Shop button now that the error
    // block has its own 4dp top spacer; avoids double-gap when error is visible.
    Spacer(Modifier.height(8.dp)) // LOGIN-MOCK-113: 20→16dp; LOGIN-MOCK-273: 16→8dp

    val isFormValid = state.shopSlug.length >= 3
        && state.registerShopName.isNotBlank()
        && state.registerEmail.isNotBlank()
        && state.registerPassword.length >= 8
        && !state.isLoading

    // §2.7-L327 — onAutoLogin navigates to dashboard when server returns a token
    LoginPillButton(
        onClick = { viewModel.registerShop(onAutoLogin = onLoginSuccess) },
        enabled = isFormValid,
        isLoading = state.isLoading,
        label = "Create Shop",
    )
    Spacer(Modifier.height(4.dp)) // LOGIN-MOCK-278: bottom card clearance
}

// ─── Step 2: Credentials ────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CredentialsStep(
    state: LoginUiState,
    viewModel: LoginViewModel,
) {
    val focusManager = LocalFocusManager.current
    // LOGIN-MOCK-187: rememberSaveable survives rotation / config changes.
    var showPassword by rememberSaveable { mutableStateOf(false) }

    // 2026-04-27 user-flagged regression: tapping Connect on Server step
    // landed here without auto-focusing the Username field, AND there was
    // a brief flicker where the IME hid (during the AnimatedContent
    // transition) before re-appearing. Race the IME hide-timer:
    // request focus on the very first frame after CredentialsStep
    // composes, so Android's IME policy never sees the gap where no
    // TextField has focus and never decides to dismiss the keyboard.
    // withFrameNanos waits for the next render frame — that's enough
    // time for Modifier.focusRequester to bind, and short enough that
    // the IME state machine treats it as a focus transfer instead of a
    // dismiss-then-reopen. Guard on blank username so 2FA returns
    // don't re-pop the keyboard.
    val usernameFocusRequester = remember { FocusRequester() }
    val keyboardController = androidx.compose.ui.platform.LocalSoftwareKeyboardController.current
    LaunchedEffect(Unit) {
        if (state.username.isBlank()) {
            // One frame of layout settle so focusRequester is bound.
            androidx.compose.runtime.withFrameNanos { }
            runCatching { usernameFocusRequester.requestFocus() }
            keyboardController?.show()
        }
    }

    // LOGIN-MOCK-177: per-field validation (only shown after the field is touched)
    val usernameError = state.username.isNotBlank() && state.username.trim().length < 2
    val credPasswordError = state.password.isNotBlank() && state.password.length < 1

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
    // LOGIN-MOCK-165: (b) banner is now dismissible via X button. Copy updated to remove
    // placeholder "future release" text. Dismiss sets setupNeeded=false locally.
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
                        "This server has not been set up. Please contact your admin or follow the docs to complete setup.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSecondaryContainer,
                        modifier = androidx.compose.ui.Modifier.weight(1f),
                    )
                    // LOGIN-MOCK-165: dismiss button
                    IconButton(
                        onClick = { viewModel.dismissSetupNeededBanner() },
                        modifier = androidx.compose.ui.Modifier.size(24.dp).clickableHover(),
                    ) {
                        Icon(
                            Icons.Default.Close,
                            contentDescription = "Dismiss setup banner",
                            modifier = androidx.compose.ui.Modifier.size(16.dp),
                            tint = MaterialTheme.colorScheme.onSecondaryContainer,
                        )
                    }
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
                    modifier = androidx.compose.ui.Modifier.height(24.dp).clickableHover(),
                ) {
                    Text(
                        "View setup guide",
                        style = MaterialTheme.typography.labelSmall,
                        // LOGIN-MOCK-138: caramel primary (#A66D1F) on Surface100 = 3.6:1 < 4.5:1
                        // WCAG AA threshold for small text. onSurfaceVariant meets contrast.
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
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
                    modifier = Modifier.clickableHover(),
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

    // LOGIN-MOCK-098/055: merge "Sign In" title + store-name subtitle into one heading stop.
    // LOGIN-MOCK-070: removed redundant Spacer(width(8.dp)) — IconButton already has
    // 12dp internal horizontal padding giving the correct optical gap to the title.
    Row(verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = viewModel::goBack, modifier = Modifier.clickableHover()) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", modifier = Modifier.size(20.dp))
        }
        Column(modifier = Modifier.semantics(mergeDescendants = true) { heading() }) {
            Text("Sign In", style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold), color = MaterialTheme.colorScheme.onSurface)
            if (state.storeName.isNotBlank()) {
                Text(state.storeName, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
    Spacer(Modifier.height(20.dp)) // LOGIN-MOCK-275: 16→20dp header-to-username gap

    OutlinedTextField(
        value = state.username,
        onValueChange = viewModel::updateUsername,
        label = { Text("Username") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth().focusRequester(usernameFocusRequester).textFieldHover(),
        isError = usernameError,
        leadingIcon = { Icon(Icons.Default.Person, null) },
        // LOGIN-MOCK-177: inline username validation
        supportingText = { if (usernameError) Text("Username must be at least 2 characters") },
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
        // D5-6: IME Next advances focus to the password field instead of sitting
        // inert under the visible "Next" glyph on the native keyboard.
        keyboardActions = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Down) }),
    )
    Spacer(Modifier.height(16.dp))

    // §2.20 L449 — SSO hybrid: swap password field for SSO CTA when domain matches.
    // While check is in flight (domainSsoChecking), show a small spinner below the
    // username field instead of the password field, preventing flicker.
    when {
        state.domainSsoChecking -> {
            Box(
                modifier = Modifier.fillMaxWidth().height(56.dp),
                contentAlignment = Alignment.CenterStart,
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                    Text(
                        "Checking sign-in method\u2026",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
        state.domainSsoDetected -> {
            // Replace password field with "Continue with SSO" primary button.
            BrandPrimaryButton(
                onClick = viewModel::login,
                enabled = !state.isLoading,
                modifier = Modifier.fillMaxWidth().height(56.dp),
            ) {
                if (state.isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary,
                    )
                } else {
                    // LOGIN-MOCK-135: Language (globe) is non-directional; OpenInBrowser mirrors in RTL.
                    Icon(Icons.Default.Language, null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("Continue with SSO")
                }
            }
        }
        else -> {
            OutlinedTextField(
                value = state.password,
                onValueChange = viewModel::updatePassword,
                label = { Text("Password") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().textFieldHover(),
                isError = credPasswordError,
                leadingIcon = { Icon(Icons.Default.Lock, null) },
                visualTransformation = if (showPassword) VisualTransformation.None else PasswordVisualTransformation(),
                trailingIcon = {
                    // LOGIN-MOCK-093: stateful contentDescription (CredentialsStep)
                    IconButton(onClick = { showPassword = !showPassword }, modifier = Modifier.clickableHover()) {
                        Icon(
                            if (showPassword) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                            contentDescription = if (showPassword) "Hide password" else "Show password",
                        )
                    }
                },
                // LOGIN-MOCK-177: inline password validation
                supportingText = { if (credPasswordError) Text("Password cannot be empty") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { focusManager.clearFocus(); viewModel.login() }),
            )
        }
    }

    ErrorMessage(state.error)
    Spacer(Modifier.height(16.dp))

    // CROSS48: Sign In is the single dominant CTA on this step — route
    // through BrandPrimaryButton so every primary button in the app
    // shares the same orange filled / onPrimary text / 12dp theme shape.
    // §2.12-L357/L358: disabled while offline or rate-limited.
    // §2.20 L449: when SSO mode detected, the SSO CTA above is the primary action;
    // this "Sign In" button is hidden to avoid duplicate CTAs.
    if (!state.domainSsoDetected) {
        LoginPillButton(
            onClick = viewModel::login,
            enabled = state.username.isNotBlank() && state.password.isNotBlank()
                    && !state.isLoading && !state.networkOffline && !state.rateLimited,
            isLoading = state.isLoading,
            label = "Sign In",
        )
    }

    // §2.20 L445 — "Sign in with SSO" button + provider picker.
    // Visible only when the server returned at least one SSO provider (404 = hidden).
    val ssoAvailable = !state.ssoProviders.isNullOrEmpty()
    // LOGIN-MOCK-187: rememberSaveable survives rotation / config changes.
    var showSsoSheet by rememberSaveable { mutableStateOf(false) }
    if (ssoAvailable) {
        val activity = LocalContext.current as? Activity

        Spacer(Modifier.height(12.dp))
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
        Spacer(Modifier.height(12.dp))

        OutlinedButton(
            onClick = { showSsoSheet = true },
            modifier = Modifier.fillMaxWidth().height(48.dp).clickableHover(),
            enabled = !state.ssoExchangeLoading,
        ) {
            if (state.ssoExchangeLoading) {
                CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
            } else {
                // LOGIN-MOCK-135: Language (globe) is non-directional; OpenInBrowser mirrors in RTL.
                Icon(Icons.Default.Language, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Sign in with SSO")
            }
        }

        if (showSsoSheet) {
            ModalBottomSheet(onDismissRequest = { showSsoSheet = false }) {
                Column(modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 32.dp)) {
                    Text(
                        "Choose your sign-in provider",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Spacer(Modifier.height(16.dp))
                    state.ssoProviders?.forEach { provider ->
                        OutlinedButton(
                            onClick = {
                                showSsoSheet = false
                                if (activity != null) {
                                    viewModel.launchSsoProvider(activity, provider)
                                }
                            },
                            modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp).clickableHover(),
                        ) {
                            Text(provider.name)
                        }
                    }
                }
            }
        }
    }

    // §2.21 L454 — "Email me a link" button + bottom sheet.
    // LOGIN-MOCK-155: opt-in model — button only visible after probe confirms enabled.
    // Hides the button during probe-pending state to avoid jank + spurious error path.
    // Matches passkey opt-in pattern (passkeyEnabled == true).
    val magicLinksVisible = state.magicLinksEnabled == true
    if (magicLinksVisible) {
        Spacer(Modifier.height(if (ssoAvailable) 8.dp else 12.dp))
        if (!ssoAvailable) {
            // Only show divider when SSO is not also present (avoid double dividers).
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            Spacer(Modifier.height(12.dp))
        }

        TextButton(
            onClick = { viewModel.openMagicLinkSheet() },
            modifier = Modifier.fillMaxWidth().clickableHover(),
        ) {
            Icon(
                Icons.Default.Email,
                contentDescription = null,
                modifier = Modifier.size(16.dp),
            )
            Spacer(Modifier.width(6.dp))
            Text(
                "Email me a link",
                style = MaterialTheme.typography.labelMedium,
            )
        }

        if (state.showMagicLinkSheet) {
            MagicLinkRequestSheet(state = state, viewModel = viewModel)
        }
    }

    // §2.22 L463 — "Use passkey" button.
    // Shown when GET /tenants/me returns passkey_enabled = true AND
    // PasskeyManager.isSupported() (device API >= 28).
    // Hidden when tenant has not enabled passkeys or device is unsupported.
    val passkeyVisible = state.passkeyEnabled == true &&
            com.bizarreelectronics.crm.util.PasskeyManager.isSupported()
    if (passkeyVisible) {
        val activityForPasskey = LocalContext.current as? android.app.Activity
        Spacer(Modifier.height(8.dp))
        TextButton(
            onClick = {
                if (activityForPasskey != null) {
                    viewModel.signInWithPasskey(activityForPasskey)
                }
            },
            enabled = !state.passkeyLoading,
            modifier = Modifier.fillMaxWidth().clickableHover(),
        ) {
            if (state.passkeyLoading) {
                CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                Spacer(Modifier.width(8.dp))
                Text("Signing in…", style = MaterialTheme.typography.labelMedium)
            } else {
                Icon(
                    Icons.Default.Key,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp),
                )
                Spacer(Modifier.width(6.dp))
                Text(
                    "Use passkey",
                    style = MaterialTheme.typography.labelMedium,
                )
            }
        }
        // Inline error below the passkey button.
        val passkeyErr = state.passkeyError
        // LOGIN-MOCK-156: auto-dismiss passkey error after 5 s so it doesn't persist indefinitely.
        LaunchedEffect(passkeyErr) {
            if (passkeyErr != null) {
                delay(5_000L)
                viewModel.clearPasskeyError()
            }
        }
        if (passkeyErr != null) {
            Text(
                text = passkeyErr,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.padding(top = 4.dp),
            )
        }
    }
    Spacer(Modifier.height(4.dp)) // LOGIN-MOCK-278: bottom card clearance
}

/**
 * §2.21 L454 — Bottom sheet: email input → POST /auth/magic-link/request.
 *
 * Two states:
 *  - Email form (magicLinkSent = false): email field + "Send link" button.
 *  - Sent banner (magicLinkSent = true): "Check your email" info + 30s resend cooldown.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MagicLinkRequestSheet(state: LoginUiState, viewModel: LoginViewModel) {
    ModalBottomSheet(onDismissRequest = { viewModel.closeMagicLinkSheet() }) {
        Column(modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 40.dp)) {
            Text(
                "Sign in with a magic link",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                "We'll send a one-time sign-in link to your email. The link expires in 15 minutes.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(16.dp))

            if (!state.magicLinkSent) {
                // ── Email input form ──
                OutlinedTextField(
                    value = state.magicLinkEmail,
                    onValueChange = viewModel::updateMagicLinkEmail,
                    label = { Text("Email address") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth().textFieldHover(),
                    leadingIcon = { Icon(Icons.Default.Email, null) },
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Email,
                        imeAction = ImeAction.Done,
                    ),
                    keyboardActions = KeyboardActions(onDone = { viewModel.requestMagicLink() }),
                    isError = state.magicLinkError != null,
                    supportingText = state.magicLinkError?.let { err ->
                        { Text(err, color = MaterialTheme.colorScheme.error) }
                    },
                )
                Spacer(Modifier.height(16.dp))

                Button(
                    onClick = { viewModel.requestMagicLink() },
                    enabled = state.magicLinkEmail.isNotBlank() && !state.magicLinkLoading,
                    modifier = Modifier.fillMaxWidth().height(48.dp).clickableHover(),
                ) {
                    if (state.magicLinkLoading) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(20.dp),
                            strokeWidth = 2.dp,
                            color = MaterialTheme.colorScheme.onPrimary,
                        )
                    } else {
                        Text("Send link")
                    }
                }
            } else {
                // ── "Check your email" banner ──
                Surface(
                    color = MaterialTheme.colorScheme.secondaryContainer,
                    shape = MaterialTheme.shapes.medium,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Icon(
                            Icons.Default.MarkEmailRead,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSecondaryContainer,
                        )
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                "Check your email",
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = FontWeight.SemiBold,
                                color = MaterialTheme.colorScheme.onSecondaryContainer,
                            )
                            Text(
                                "A sign-in link was sent to ${state.magicLinkEmail}.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSecondaryContainer,
                            )
                        }
                    }
                }
                Spacer(Modifier.height(16.dp))

                // 30-second resend cooldown ticker.
                val cooldownMs = state.magicLinkResendCooldownMs
                var cooldownSec by remember(cooldownMs) {
                    mutableStateOf(
                        if (cooldownMs == null) 0L
                        else ((cooldownMs - System.currentTimeMillis()) / 1000L).coerceAtLeast(0L)
                    )
                }
                LaunchedEffect(cooldownMs) {
                    if (cooldownMs == null) { cooldownSec = 0L; return@LaunchedEffect }
                    while (cooldownSec > 0L) {
                        delay(1_000L)
                        cooldownSec = ((cooldownMs - System.currentTimeMillis()) / 1000L).coerceAtLeast(0L)
                    }
                    viewModel.clearMagicLinkResendCooldown()
                }

                TextButton(
                    onClick = {
                        viewModel.requestMagicLink()
                    },
                    enabled = cooldownSec <= 0L && !state.magicLinkLoading,
                    modifier = Modifier.fillMaxWidth().clickableHover(),
                ) {
                    if (cooldownSec > 0L) {
                        Text("Resend in ${cooldownSec}s", style = MaterialTheme.typography.labelMedium)
                    } else {
                        Text("Resend link", style = MaterialTheme.typography.labelMedium)
                    }
                }
            }
        }
    }
}

/**
 * §2.21 L454 — Phishing-defense preview card shown before exchanging a magic-link token.
 *
 * Renders as an AlertDialog with:
 *  - Tenant name (from exchange response, or generic fallback).
 *  - Link validity countdown (if expiresAt is present).
 *  - "Continue" button that calls the exchange; "Cancel" dismisses without exchange.
 *  - Inline error message on exchange failure.
 *
 * The user MUST tap "Continue" to confirm intent before any POST is sent.
 */
@Composable
private fun MagicLinkPreviewDialog(
    token: String,
    tenantName: String?,
    expiresAt: String?,
    isLoading: Boolean,
    error: String?,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    // Suppress unused parameter lint — token is intentionally not displayed
    // (showing the raw token would expose it to shoulder-surfing; the preview
    // card shows only the tenant and expiry context).
    @Suppress("UNUSED_VARIABLE")
    val _unused = token

    AlertDialog(
        onDismissRequest = { if (!isLoading) onDismiss() },
        icon = {
            Icon(
                Icons.Default.Link,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
            )
        },
        title = {
            Text(
                "Sign-in link received",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    buildString {
                        append("You're about to sign in to ")
                        append(tenantName?.takeIf { it.isNotBlank() } ?: "Bizarre CRM")
                        append(".")
                    },
                    style = MaterialTheme.typography.bodyMedium,
                )
                if (expiresAt != null) {
                    Text(
                        "This link is one-time-use and expires soon.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Text(
                    "Only continue if you requested this link.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (error != null) {
                    Text(
                        error,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }
        },
        confirmButton = {
            Button(
                onClick = onConfirm,
                enabled = !isLoading,
            ) {
                if (isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary,
                    )
                } else {
                    Text("Continue")
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !isLoading, modifier = Modifier.clickableHover()) {
                Text("Cancel")
            }
        },
    )
}

// ─── Step 2b: Set Password ──────────────────────────────────────────

@Composable
private fun SetPasswordStep(state: LoginUiState, viewModel: LoginViewModel) {
    // D5-6: local focus manager so IME Next advances from the new password
    // field to the confirm password field.
    val focusManager = LocalFocusManager.current
    // LOGIN-MOCK-098/055/101: merge title + subtitle into one heading stop.
    Row(verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = viewModel::goBack, modifier = Modifier.clickableHover()) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", modifier = Modifier.size(20.dp))
        }
        Spacer(Modifier.width(8.dp))
        Column(modifier = Modifier.semantics(mergeDescendants = true) { heading() }) {
            Text("Set Your Password", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(4.dp))
            Text("This is your first login. Please set a password.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    Spacer(Modifier.height(16.dp))

    OutlinedTextField(
        value = state.newPassword,
        onValueChange = viewModel::updateNewPassword,
        label = { Text("New Password") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth().textFieldHover(),
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
        modifier = Modifier.fillMaxWidth().textFieldHover(),
        visualTransformation = PasswordVisualTransformation(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done),
        keyboardActions = KeyboardActions(onDone = { viewModel.setPassword() }),
    )

    ErrorMessage(state.error)
    Spacer(Modifier.height(16.dp))

    // §2.10/L294 — CTA disabled until strength is at least FAIR.
    // LOGIN-MOCK-073: replaced raw Button (48dp, 12dp corner) with LoginPillButton
    // (56dp, 28dp pill) to match spec used by Connect / Create Shop / Sign In.
    val newPassStrength = PasswordStrength.evaluate(state.newPassword).level
    val strengthAcceptable = newPassStrength >= PasswordStrength.Level.FAIR
    LoginPillButton(
        onClick = viewModel::setPassword,
        enabled = strengthAcceptable && !state.isLoading,
        isLoading = state.isLoading,
        label = "Set Password",
    )

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

    // LOGIN-MOCK-098/055/101: merge title + subtitle into one heading stop.
    Column(modifier = Modifier.semantics(mergeDescendants = true) { heading() }) {
        Text("Set Up Two-Factor Auth", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(4.dp))
        Text(
            "Scan this QR code with Google Authenticator or any TOTP app",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
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
    // LOGIN-MOCK-188: recycle the bitmap when composition leaves or keys change
    // to prevent ~60-150 KB leak on low-RAM devices during 2FA setup.
    DisposableEffect(qrBitmap) {
        onDispose { qrBitmap?.recycle() }
    }

    // LOGIN-MOCK-169: 10-second QR load timeout — fires timeoutQrSetupIfStillBlank()
    // when qrCodeDataUrl and twoFaSecret are still blank after 10 seconds.
    val qrLoadKey = state.qrCodeDataUrl + state.twoFaSecret
    LaunchedEffect(qrLoadKey) {
        if (state.qrCodeDataUrl.isBlank() && state.twoFaSecret.isBlank()) {
            delay(10_000L)
            // VM re-reads current state so we avoid stale closure capture
            viewModel.timeoutQrSetupIfStillBlank()
        }
    }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            // LOGIN-MOCK-109: 240dp → 200dp saves ~40dp vertical space without
            // clipping at typical scan distances; image scaled proportionally.
            .height(200.dp),
        contentAlignment = Alignment.Center,
    ) {
        when {
            qrBitmap != null -> Surface(
                color = Color.White,
                shape = RoundedCornerShape(8.dp),
            ) {
                Image(
                    bitmap = qrBitmap.asImageBitmap(),
                    contentDescription = "2FA QR Code — scan with your authenticator app",
                    modifier = Modifier
                        .padding(12.dp) // LOGIN-MOCK-109: 16dp → 12dp proportional to height reduction
                        .size(172.dp),  // LOGIN-MOCK-109: 200dp → 172dp proportional
                )
            }
            // LOGIN-MOCK-169: show Retry button when timed out (error is set by timeoutQrSetup)
            state.qrCodeDataUrl.isBlank() && state.twoFaSecret.isBlank() && state.error != null ->
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        state.error,
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall,
                        textAlign = TextAlign.Center,
                    )
                    Spacer(Modifier.height(8.dp))
                    OutlinedButton(onClick = {
                        viewModel.retryQrSetup()
                    }) {
                        Text("Retry")
                    }
                }
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

    // ── Secret / manual-entry display — collapsed by default ───────────────
    val displaySecret = state.twoFaManualEntry.ifBlank { state.twoFaSecret }
    if (displaySecret.isNotBlank()) {
        var manualEntryExpanded by rememberSaveable { mutableStateOf(false) }
        Spacer(Modifier.height(4.dp))
        TextButton(
            onClick = { manualEntryExpanded = (manualEntryExpanded == false) },
            modifier = Modifier.fillMaxWidth().wrapContentWidth(Alignment.CenterHorizontally).clickableHover(),
        ) {
            Text(
                if (manualEntryExpanded) "Hide manual key" else "Can't scan?",
                style = MaterialTheme.typography.labelMedium,
            )
        }
        if (manualEntryExpanded) {
            Spacer(Modifier.height(4.dp))
            Text(
                "Or enter this key manually:",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(4.dp))
            // LOGIN-MOCK-081: surfaceVariant resolves near-invisible on dark card;
            // surfaceContainerHighest gives adequate contrast for the monospace key block.
            Surface(
                shape = MaterialTheme.shapes.small,
                color = MaterialTheme.colorScheme.surfaceContainerHighest,
                modifier = Modifier.fillMaxWidth(),
            ) {
                SelectionContainer {
                    Text(
                        text = displaySecret,
                        style = MaterialTheme.typography.bodyLarge.copy(
                            fontFamily = BrandMono.fontFamily,
                            letterSpacing = 2.sp,
                        ),
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp), // LOGIN-MOCK-279: 12/10→16/12dp
                    )
                }
            }
            Spacer(Modifier.height(8.dp))
            // Row: "Copy key" + optional "Open authenticator"
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
                    modifier = Modifier.weight(1f).clickableHover(),
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
                        modifier = Modifier.weight(1f).clickableHover(),
                    ) {
                        Icon(Icons.Default.OpenInNew, contentDescription = null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(4.dp))
                        Text("Open app", style = MaterialTheme.typography.labelMedium)
                    }
                }
            }
        }
    }

    // LOGIN-MOCK-112: 16dp → 4dp between QR block and TotpCodeInputContent.
    // TotpCodeInputContent already emits its own Spacer(16dp) before the Continue
    // button, so 4+16 = 20dp total visual gap — matching the mockup grouping.
    // This also fixes LOGIN-MOCK-110: the QR image inner padding (12dp) + 4dp spacer
    // = 16dp visual gap from QR image edge to code field, matching subtitle→QR gap.
    Spacer(Modifier.height(4.dp))
    // LOGIN-MOCK-092: pass autoFocusOnEntry = false so keyboard doesn't open
    // immediately on Setup entry, which would scroll the QR code off-screen.
    TotpCodeInputContent(state, viewModel, onSuccess, autoFocusOnEntry = false)
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
                    Timber.w(e, "SmsRetriever start failed")
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

    // LOGIN-MOCK-098/055: merge title + subtitle into one heading stop.
    Row(verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = viewModel::goBack, modifier = Modifier.clickableHover()) {
            Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", modifier = Modifier.size(20.dp))
        }
        Spacer(Modifier.width(8.dp))
        Column(modifier = Modifier.semantics(mergeDescendants = true) { heading() }) {
            // LOGIN-MOCK-118: "Auth" matches TwoFaSetupStep heading (screen-10 mockup-backed).
            Text("Two-Factor Auth", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(4.dp))
            // LOGIN-MOCK-119: align with Setup step's "TOTP app" phrasing; drops misleading
            // "your" (user may not have installed an app yet at the verify step).
            Text("Enter the 6-digit code from your TOTP app", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    // LOGIN-MOCK-277: align with every other step's 16 dp subtitle-to-first-field gap
    // (ServerStep, RegisterStep, CredentialsStep, SetPasswordStep all use 16 dp here).
    // The previous 24 dp made the verify card appear taller than its siblings.
    Spacer(Modifier.height(16.dp))

    TotpCodeInputContent(state, viewModel, onSuccess)
    // §2.13-L366: countdown shown while challenge token is live
    ChallengeTokenCountdown(state.challengeTokenExpiresAtMs)

    // §2.8 L335 — recovery escape hatch shown below the verify form
    if (onBackupCodeRecovery != null) {
        Spacer(Modifier.height(4.dp))
        TextButton(
            onClick = onBackupCodeRecovery,
            modifier = Modifier.fillMaxWidth().clickableHover(),
        ) {
            Text(
                "Lost 2FA access? Use a backup code",
                style = MaterialTheme.typography.labelMedium,
            )
        }
    }
}

// ─── Shared TOTP code input ─────────────────────────────────────────

// LOGIN-MOCK-092: added autoFocusOnEntry param (default true) so TwoFaSetupStep
// can pass false, preventing the keyboard from opening and scrolling the QR code
// off-screen before the user has a chance to scan it (WCAG 3.2.2 On Input).
// TwoFaVerifyStep keeps the default true — user must type immediately.
@Composable
private fun TotpCodeInputContent(
    state: LoginUiState,
    viewModel: LoginViewModel,
    onSuccess: () -> Unit,
    autoFocusOnEntry: Boolean = true,
) {
    val focusRequester = remember { FocusRequester() }
    val focusManager = LocalFocusManager.current

    // LOGIN-MOCK-147: haptic feedback at key 2FA events — must stay in composition
    // context because LocalHapticFeedback is not accessible from the ViewModel.
    val haptic = LocalHapticFeedback.current

    // LOGIN-MOCK-092: gate auto-focus behind the parameter so Setup step doesn't
    // force keyboard open before the user has scanned the QR code.
    if (autoFocusOnEntry) {
        LaunchedEffect(Unit) { focusRequester.requestFocus() }
    }

    // LOGIN-MOCK-147: fire haptic when a wrong-code error appears.
    val previousError = remember { mutableStateOf<String?>(null) }
    LaunchedEffect(state.error) {
        if (state.error != null && previousError.value != state.error) {
            haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        }
        previousError.value = state.error
    }

    OutlinedTextField(
        value = state.totpCode,
        onValueChange = { code ->
            viewModel.updateTotpCode(code)
            // LOGIN-MOCK-147: haptic on 6th-digit entry — signals code is complete.
            if (code.length == 6) {
                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
            }
        },
        label = { Text("6-digit code") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth().focusRequester(focusRequester).textFieldHover(),
        textStyle = LocalTextStyle.current.copy(
            fontFamily = BrandMono.fontFamily,
            fontSize = 24.sp,
            // LOGIN-MOCK-130: reduced from 6.sp — 6.sp overflows at fontScale ≥ 1.5.
            letterSpacing = 4.sp,
            textAlign = TextAlign.Center,
            fontWeight = FontWeight.Bold,
        ),
        leadingIcon = { Icon(Icons.Outlined.VerifiedUser, null) },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Done),
        keyboardActions = KeyboardActions(onDone = {
            focusManager.clearFocus() // Dismiss keyboard
        }),
    )

    // LOGIN-MOCK-076: ErrorMessage moved AFTER the Continue button so a wrong-code
    // error doesn't push the CTA below the keyboard on small phones. The field-to-CTA
    // rhythm is now constant; error appears beneath the button.
    Spacer(Modifier.height(16.dp))

    LoginPillButton(
        onClick = {
            // LOGIN-MOCK-147: wrap onSuccess to fire success haptic in composition context.
            viewModel.verify2FA(onSuccess = {
                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                onSuccess()
            })
        },
        enabled = state.totpCode.length == 6 && !state.isLoading,
        isLoading = state.isLoading,
        label = "Continue",
    )

    ErrorMessage(state.error)
}
