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
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Dispatchers
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
import java.net.Inet4Address
import java.net.InetAddress
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
    // Registration fields
    val registerShopName: String = "",
    val registerEmail: String = "",
    val registerPassword: String = "",
)

// ─── ViewModel ──────────────────────────────────────────────────────

@HiltViewModel
class LoginViewModel @Inject constructor(
    private val authPreferences: AuthPreferences,
    private val authApi: AuthApi,
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
    fun updateUsername(value: String) { _state.value = _state.value.copy(username = value, error = null) }
    fun updatePassword(value: String) { _state.value = _state.value.copy(password = value, error = null) }
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

    /** Step 2: Login with credentials */
    fun login() {
        val s = _state.value
        if (s.username.isBlank()) { _state.value = s.copy(error = "Username is required"); return }
        if (s.password.isBlank()) { _state.value = s.copy(error = "Password is required"); return }

        _state.value = s.copy(isLoading = true, error = null)
        viewModelScope.launch {
            try {
                // AUDIT-AND-008: commit serverUrl only when the user submits credentials,
                // not on probe-success. This is the earliest point at which credentials
                // are being sent, so the URL has been validated as a real CRM host.
                authPreferences.serverUrl = s.serverUrl

                val response = authApi.login(LoginRequest(s.username.trim(), s.password))
                val data = response.data ?: throw Exception(response.message ?: "Login failed")

                val challengeToken = data.challengeToken ?: throw Exception("No challenge token received")

                when {
                    data.requiresPasswordSetup == true -> {
                        _state.value = _state.value.copy(
                            isLoading = false,
                            challengeToken = challengeToken,
                            step = SetupStep.SET_PASSWORD,
                        )
                    }
                    data.requires2faSetup == true || data.totpEnabled != true -> {
                        // Need to set up 2FA first
                        setup2FA(challengeToken)
                    }
                    else -> {
                        // 2FA already set up, just need code
                        _state.value = _state.value.copy(
                            isLoading = false,
                            challengeToken = challengeToken,
                            step = SetupStep.TWO_FA_VERIFY,
                        )
                    }
                }
            } catch (e: Exception) {
                val errorMsg = extractErrorMessage(e)
                _state.value = _state.value.copy(isLoading = false, error = errorMsg)
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

                // Password set, now set up 2FA
                setup2FA(newChallenge)
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false, error = extractErrorMessage(e))
            }
        }
    }

    /** Step 3a: Request 2FA QR code */
    private fun setup2FA(challengeToken: String) {
        viewModelScope.launch {
            try {
                val response = authApi.setup2FA(mapOf("challengeToken" to challengeToken))
                val data = response.data ?: throw Exception("Failed to set up 2FA")
                // Server returns { qr: "data:image/png;base64,...", secret: "...", challengeToken: "..." }
                val qrCode = data.qrCode ?: data.qr ?: ""
                val newChallenge = data.challengeToken ?: challengeToken

                _state.value = _state.value.copy(
                    isLoading = false,
                    challengeToken = newChallenge,
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
    viewModel: LoginViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

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

    Box(
        modifier = Modifier.fillMaxSize().statusBarsPadding().imePadding(),
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
                            SetupStep.TWO_FA_VERIFY -> TwoFaVerifyStep(state, viewModel, onLoginSuccess)
                        }
                    }
                }
            }
        }
    }
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

// ─── Step 2: Credentials ────────────────────────────────────────────

@Composable
private fun CredentialsStep(
    state: LoginUiState,
    viewModel: LoginViewModel,
    onForgotPassword: (() -> Unit)? = null,
) {
    val focusManager = LocalFocusManager.current
    var showPassword by remember { mutableStateOf(false) }

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
    BrandPrimaryButton(
        onClick = viewModel::login,
        enabled = state.username.isNotBlank() && state.password.isNotBlank() && !state.isLoading,
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
}

// ─── Step 3b: 2FA Verify (code only) ────────────────────────────────

@Composable
private fun TwoFaVerifyStep(state: LoginUiState, viewModel: LoginViewModel, onSuccess: () -> Unit) {
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
