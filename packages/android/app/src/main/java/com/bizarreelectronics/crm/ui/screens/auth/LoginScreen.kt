package com.bizarreelectronics.crm.ui.screens.auth

import android.graphics.BitmapFactory
import android.util.Base64
import androidx.compose.animation.*
import androidx.compose.foundation.Image
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.ui.theme.SuccessGreen
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.data.remote.dto.*
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import com.bizarreelectronics.crm.BuildConfig
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

// ─── State ──────────────────────────────────────────────────────────

enum class SetupStep { SERVER, CREDENTIALS, SET_PASSWORD, TWO_FA_SETUP, TWO_FA_VERIFY }

data class LoginUiState(
    val step: SetupStep = SetupStep.SERVER,
    val serverUrl: String = "",
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
)

// ─── ViewModel ──────────────────────────────────────────────────────

@HiltViewModel
class LoginViewModel @Inject constructor(
    private val authPreferences: AuthPreferences,
    private val authApi: AuthApi,
) : ViewModel() {

    private val _state = MutableStateFlow(LoginUiState(
        serverUrl = authPreferences.serverUrl ?: "",
        step = if (authPreferences.serverUrl.isNullOrBlank()) SetupStep.SERVER else SetupStep.CREDENTIALS,
    ))
    val state = _state.asStateFlow()

    fun updateServerUrl(value: String) { _state.value = _state.value.copy(serverUrl = value, error = null) }
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
        val url = _state.value.serverUrl.trimEnd('/')
        if (url.isBlank()) { _state.value = _state.value.copy(error = "Server URL is required"); return }

        _state.value = _state.value.copy(isLoading = true, error = null)
        viewModelScope.launch {
            try {
                val result = withContext(Dispatchers.IO) {
                    // Quick test: hit the public embed config endpoint
                    val clientBuilder = OkHttpClient.Builder()
                        .connectTimeout(10, TimeUnit.SECONDS)
                        .readTimeout(10, TimeUnit.SECONDS)

                    // Trust self-signed certs ONLY in debug builds (LAN development)
                    if (BuildConfig.DEBUG) {
                        val trustAll = arrayOf<TrustManager>(object : X509TrustManager {
                            override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) {}
                            override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {}
                            override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
                        })
                        val sslCtx = SSLContext.getInstance("TLS")
                        sslCtx.init(null, trustAll, SecureRandom())
                        clientBuilder
                            .sslSocketFactory(sslCtx.socketFactory, trustAll[0] as X509TrustManager)
                            .hostnameVerifier { _, _ -> true }
                    }

                    val client = clientBuilder.build()
                    val request = Request.Builder()
                        .url("$url/api/v1/portal/embed/config")
                        .build()
                    val response = client.newCall(request).execute()
                    if (!response.isSuccessful) throw Exception("Server returned ${response.code}")
                    val body = response.body?.string() ?: throw Exception("Empty response")
                    val json = JSONObject(body)
                    val data = json.optJSONObject("data")
                    data?.optString("name") ?: "CRM Server"
                }

                authPreferences.serverUrl = url
                authPreferences.storeName = result

                _state.value = _state.value.copy(
                    isLoading = false,
                    serverConnected = true,
                    storeName = result,
                    step = SetupStep.CREDENTIALS,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = "Could not connect: ${e.message}",
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
    viewModel: LoginViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    // Backup codes dialog — must be dismissed before proceeding to dashboard
    if (state.showBackupCodes != null) {
        AlertDialog(
            onDismissRequest = { /* User must explicitly dismiss */ },
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
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Column(modifier = Modifier.padding(12.dp)) {
                            state.showBackupCodes!!.forEachIndexed { index, code ->
                                Text(
                                    "${index + 1}.  $code",
                                    style = MaterialTheme.typography.bodyMedium.copy(
                                        fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
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
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.Bold,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                "Electronics Repair Management",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(32.dp))

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
                label = "step",
            ) { step ->
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
                ) {
                    Column(modifier = Modifier.padding(24.dp)) {
                        when (step) {
                            SetupStep.SERVER -> ServerStep(state, viewModel)
                            SetupStep.CREDENTIALS -> CredentialsStep(state, viewModel)
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
        SetupStep.SERVER -> 0
        SetupStep.CREDENTIALS, SetupStep.SET_PASSWORD -> 1
        SetupStep.TWO_FA_SETUP, SetupStep.TWO_FA_VERIFY -> 2
    }

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        steps.forEachIndexed { index, (label, _) ->
            val isActive = index <= currentIndex
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Surface(
                    shape = MaterialTheme.shapes.extraLarge,
                    color = if (isActive) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant,
                    modifier = Modifier.size(28.dp),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        if (index < currentIndex) {
                            Icon(Icons.Default.Check, null, tint = Color.White, modifier = Modifier.size(16.dp))
                        } else {
                            Text("${index + 1}", style = MaterialTheme.typography.labelSmall,
                                color = if (isActive) Color.White else MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                Spacer(Modifier.height(4.dp))
                Text(label, style = MaterialTheme.typography.labelSmall,
                    color = if (isActive) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (index < steps.lastIndex) {
                Divider(
                    modifier = Modifier.width(40.dp).padding(horizontal = 4.dp),
                    color = if (index < currentIndex) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant,
                    thickness = 2.dp,
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
    val focusRequester = remember { FocusRequester() }

    LaunchedEffect(Unit) { focusRequester.requestFocus() }

    Text("Connect to Server", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
    Spacer(Modifier.height(4.dp))
    Text("Enter your CRM server address", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    Spacer(Modifier.height(16.dp))

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
                Icon(Icons.Default.CheckCircle, "Connected", tint = SuccessGreen)
            }
        },
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done, keyboardType = KeyboardType.Uri),
        keyboardActions = KeyboardActions(onDone = { viewModel.connectToServer() }),
    )

    ErrorMessage(state.error)
    Spacer(Modifier.height(16.dp))

    Button(
        onClick = viewModel::connectToServer,
        enabled = state.serverUrl.isNotBlank() && !state.isLoading,
        modifier = Modifier.fillMaxWidth().height(48.dp),
    ) {
        if (state.isLoading) {
            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp, color = Color.White)
        } else {
            Text("Connect")
        }
    }

    Spacer(Modifier.height(8.dp))
    Text(
        "Your server IP is on the CRM startup screen",
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center,
        modifier = Modifier.fillMaxWidth(),
    )
}

// ─── Step 2: Credentials ────────────────────────────────────────────

@Composable
private fun CredentialsStep(state: LoginUiState, viewModel: LoginViewModel) {
    val focusManager = LocalFocusManager.current
    var showPassword by remember { mutableStateOf(false) }

    Row(verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = viewModel::goBack, modifier = Modifier.size(32.dp)) {
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

    Button(
        onClick = viewModel::login,
        enabled = state.username.isNotBlank() && state.password.isNotBlank() && !state.isLoading,
        modifier = Modifier.fillMaxWidth().height(48.dp),
    ) {
        if (state.isLoading) {
            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp, color = Color.White)
        } else {
            Text("Sign In")
        }
    }
}

// ─── Step 2b: Set Password ──────────────────────────────────────────

@Composable
private fun SetPasswordStep(state: LoginUiState, viewModel: LoginViewModel) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = viewModel::goBack, modifier = Modifier.size(32.dp)) {
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
            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp, color = Color.White)
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
        IconButton(onClick = viewModel::goBack, modifier = Modifier.size(32.dp)) {
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
            fontSize = 24.sp,
            letterSpacing = 8.sp,
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
            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp, color = Color.White)
        } else {
            Text("Continue")
        }
    }
}
