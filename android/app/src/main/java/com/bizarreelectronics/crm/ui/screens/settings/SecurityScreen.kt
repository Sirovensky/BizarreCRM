package com.bizarreelectronics.crm.ui.screens.settings

// §2.6 Security screen — biometric unlock toggle + Change PIN + Change Password + Lock Now.
//
// Unlock chain (L319):
//   bio → fail-3x → fall back to PIN (navigate to Screen.PinSetup / PinLockScreen)
//   PIN → fail-5x → hard-lock → full re-auth (handled by PinPreferences.hardLockout already)
//
// Keystore key lifecycle (L322):
//   Toggle ON  → generate AES256 key with setInvalidatedByBiometricEnrollment(true)
//              → confirm with BiometricPrompt(CryptoObject) immediately
//              → only persist pref on success
//   Toggle OFF → clear pref + delete Keystore key
//   Catch KeyPermanentlyInvalidatedException → "Re-enroll biometric" dialog

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_WEAK
import androidx.biometric.BiometricPrompt
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.local.prefs.PinPreferences.Companion.GRACE_NEVER
import com.bizarreelectronics.crm.ui.components.SensitiveScreenGuard
import com.bizarreelectronics.crm.ui.components.Sensitivity
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.inject.Inject

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

/**
 * §2.6 — ViewModel for SecurityScreen. Owns:
 *
 *  - [biometricAvailability]: result of BiometricManager.canAuthenticate for
 *    the toggle's enabled/subtitle state.
 *  - [biometricEnabled]: mirrors AppPreferences.biometricEnabled.
 *  - Toggle-ON path: generate Keystore key → confirm with CryptoObject prompt
 *    → persist pref only on success.
 *  - Toggle-OFF path: clear pref + delete Keystore key.
 *  - [reEnrollRequired]: set when KeyPermanentlyInvalidatedException is caught;
 *    drives the "Re-enroll biometric" alert dialog.
 */
@HiltViewModel
class SecurityViewModel @Inject constructor(
    @ApplicationContext private val applicationContext: Context,
    private val appPreferences: AppPreferences,
    private val pinPreferences: com.bizarreelectronics.crm.data.local.prefs.PinPreferences,
) : ViewModel() {

    companion object {
        /** Keystore alias for the biometric confirmation key (§2.6 / L322). */
        const val BIO_KEY_ALIAS = "bizarre_crm_biometric_unlock_key"

        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val CIPHER_ALGORITHM =
            "${KeyProperties.KEY_ALGORITHM_AES}/" +
                    "${KeyProperties.BLOCK_MODE_CBC}/" +
                    KeyProperties.ENCRYPTION_PADDING_PKCS7
    }

    // ---------------------------------------------------------------------------
    // Biometric availability — evaluated once per composition lifecycle.
    // ---------------------------------------------------------------------------

    /**
     * Computes BiometricManager result code using BIOMETRIC_STRONG | BIOMETRIC_WEAK
     * (plan L318 — wider net than the existing BiometricAuth helper which restricts
     * to BIOMETRIC_STRONG | DEVICE_CREDENTIAL).
     *
     * Returns one of:
     *   BIOMETRIC_SUCCESS            → toggle enabled
     *   BIOMETRIC_ERROR_NONE_ENROLLED → enrolled but nothing set up — show subtitle
     *   BIOMETRIC_ERROR_NO_HARDWARE  → no sensor at all — disable toggle
     *   BIOMETRIC_ERROR_HW_UNAVAILABLE → sensor present but temporarily unavailable
     *   BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED → firmware update needed
     *   BIOMETRIC_ERROR_UNSUPPORTED  → Android version issue
     */
    fun checkBiometricAvailability(): Int =
        BiometricManager.from(applicationContext)
            .canAuthenticate(BIOMETRIC_STRONG or BIOMETRIC_WEAK)

    // ---------------------------------------------------------------------------
    // State
    // ---------------------------------------------------------------------------

    private val _biometricEnabled = MutableStateFlow(appPreferences.biometricEnabled)
    val biometricEnabled: StateFlow<Boolean> = _biometricEnabled.asStateFlow()

    /** True while the CryptoObject confirmation prompt is in flight. */
    private val _promptPending = MutableStateFlow(false)
    val promptPending: StateFlow<Boolean> = _promptPending.asStateFlow()

    /**
     * Set to true when we catch [KeyPermanentlyInvalidatedException] on toggle-on
     * or on a subsequent prompt call. Drives the re-enroll dialog (L322).
     */
    private val _reEnrollRequired = MutableStateFlow(false)
    val reEnrollRequired: StateFlow<Boolean> = _reEnrollRequired.asStateFlow()

    /** Transient user-facing message (snackbar). */
    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    // ---------------------------------------------------------------------------
    // Keystore helpers
    // ---------------------------------------------------------------------------

    /**
     * (Re-)generates the AES256/CBC/PKCS7 key in the Android Keystore with:
     *   - setUserAuthenticationRequired(true) — key only usable after bio auth
     *   - setInvalidatedByBiometricEnrollment(true) — key deleted if new fingers added (L322)
     *
     * Returns a [Cipher] initialized for ENCRYPT_MODE wrapped in a
     * [BiometricPrompt.CryptoObject] so the caller can show the prompt
     * confirming the user can authenticate RIGHT NOW.
     *
     * Throws [KeyPermanentlyInvalidatedException] if the existing key was
     * invalidated — caller must call [handleReEnrollRequired].
     *
     * NOTE (L320 TODO): In a future wave this Cipher will also be used to
     * encrypt/decrypt stored "Remember me" credentials via EncryptedSharedPreferences
     * so login-time biometric unlocks the credential blob without re-entering the
     * password. The Keystore key infrastructure here is already prepared for that
     * path. The decryption flow would call Cipher.init(DECRYPT_MODE, keystoreKey)
     * and pass the resulting CryptoObject to BiometricPrompt before reading the
     * encrypted credential from EncryptedSharedPreferences.
     */
    @Throws(KeyPermanentlyInvalidatedException::class)
    fun generateKeystoreKeyAndCipher(): BiometricPrompt.CryptoObject {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).also { it.load(null) }
        // Always regenerate so we're guaranteed a fresh key bound to the
        // current enrolled biometrics. Deleting first avoids stale-alias issues.
        if (keyStore.containsAlias(BIO_KEY_ALIAS)) {
            keyStore.deleteEntry(BIO_KEY_ALIAS)
        }

        val keyGenSpec = KeyGenParameterSpec.Builder(
            BIO_KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_CBC)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_PKCS7)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
            .build()

        val keyGen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        keyGen.init(keyGenSpec)
        keyGen.generateKey()

        val secretKey = keyStore.getKey(BIO_KEY_ALIAS, null) as javax.crypto.SecretKey
        val cipher = Cipher.getInstance(CIPHER_ALGORITHM)
        // This init call will throw KeyPermanentlyInvalidatedException if the
        // key is already stale (shouldn't happen right after generation, but
        // guard defensively).
        cipher.init(Cipher.ENCRYPT_MODE, secretKey)
        return BiometricPrompt.CryptoObject(cipher)
    }

    /**
     * Returns a [BiometricPrompt.CryptoObject] for an existing key without
     * regenerating it. Used to verify the user can still authenticate after
     * a toggle re-confirm flow.
     *
     * Throws [KeyPermanentlyInvalidatedException] if the biometric enrollment
     * has changed since the key was generated — caller must call
     * [handleReEnrollRequired].
     */
    @Throws(KeyPermanentlyInvalidatedException::class)
    fun existingCipherForPrompt(): BiometricPrompt.CryptoObject {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).also { it.load(null) }
        val secretKey = keyStore.getKey(BIO_KEY_ALIAS, null) as javax.crypto.SecretKey
        val cipher = Cipher.getInstance(CIPHER_ALGORITHM)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey)
        return BiometricPrompt.CryptoObject(cipher)
    }

    /** Deletes the Keystore key entry. Safe to call even if alias doesn't exist. */
    private fun deleteKeystoreKey() {
        runCatching {
            val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).also { it.load(null) }
            if (keyStore.containsAlias(BIO_KEY_ALIAS)) {
                keyStore.deleteEntry(BIO_KEY_ALIAS)
            }
        }.onFailure { e ->
            android.util.Log.w("SecurityViewModel", "deleteKeystoreKey failed", e)
        }
    }

    // ---------------------------------------------------------------------------
    // Toggle actions
    // ---------------------------------------------------------------------------

    /**
     * Called when the user flips the switch ON.
     *
     * We do NOT persist the pref yet. The caller must show BiometricPrompt
     * with the returned CryptoObject. [onBiometricConfirmSuccess] is called
     * on success; [onBiometricConfirmError] on failure/cancel.
     *
     * Returns null and emits an error message if key generation fails or if
     * [KeyPermanentlyInvalidatedException] is caught.
     */
    fun prepareEnableBiometric(): BiometricPrompt.CryptoObject? {
        _promptPending.value = true
        return try {
            generateKeystoreKeyAndCipher()
        } catch (e: KeyPermanentlyInvalidatedException) {
            _promptPending.value = false
            handleReEnrollRequired()
            null
        } catch (e: Exception) {
            _promptPending.value = false
            _message.value = "Failed to set up biometric key: ${e.localizedMessage}"
            android.util.Log.e("SecurityViewModel", "generateKeystoreKeyAndCipher failed", e)
            null
        }
    }

    /** Called by the BiometricPrompt success callback when enabling. Persists the pref. */
    fun onBiometricConfirmSuccess() {
        _promptPending.value = false
        appPreferences.biometricEnabled = true
        _biometricEnabled.value = true
        _message.value = "Biometric unlock enabled"
    }

    /** Called by the BiometricPrompt error/cancel callback when enabling. */
    fun onBiometricConfirmError(msg: String) {
        _promptPending.value = false
        // Key was generated but user cancelled/failed — clean up the key so
        // we don't leave a dangling entry without the pref being set.
        deleteKeystoreKey()
        _biometricEnabled.value = false
        if (msg.isNotBlank()) {
            _message.value = "Biometric not confirmed: $msg"
        }
    }

    /**
     * Called when the user flips the switch OFF.
     * Clears the pref and removes the Keystore key immediately — no prompt needed.
     */
    fun disableBiometric() {
        appPreferences.biometricEnabled = false
        _biometricEnabled.value = false
        deleteKeystoreKey()
        _message.value = "Biometric unlock disabled"
    }

    // ---------------------------------------------------------------------------
    // Re-enrollment detection (L322)
    // ---------------------------------------------------------------------------

    /** Signal that the Keystore key was permanently invalidated. */
    fun handleReEnrollRequired() {
        deleteKeystoreKey()
        appPreferences.biometricEnabled = false
        _biometricEnabled.value = false
        _reEnrollRequired.value = true
    }

    /** Dismiss the re-enroll dialog without re-enabling. */
    fun dismissReEnrollDialog() {
        _reEnrollRequired.value = false
    }

    /** User chose to re-enable from the re-enroll dialog — same as flipping switch ON. */
    fun reEnroll(activity: FragmentActivity, onShowPrompt: (BiometricPrompt.CryptoObject) -> Unit) {
        _reEnrollRequired.value = false
        viewModelScope.launch {
            val cryptoObject = prepareEnableBiometric() ?: return@launch
            onShowPrompt(cryptoObject)
        }
    }

    // ---------------------------------------------------------------------------
    // Auto-lock grace window (§2.5 L311)
    // ---------------------------------------------------------------------------

    /**
     * Emits the current [lockGraceMinutes] value and updates whenever the pref changes.
     * UI observes this to show the selected segment in the auto-lock row.
     */
    val lockGraceMinutes: StateFlow<Int> = pinPreferences.lockGraceMinutesFlow
        .stateIn(viewModelScope, SharingStarted.Eagerly, pinPreferences.lockGraceMinutes)

    /** Called when the user selects a new segment from the auto-lock row. */
    fun setLockGraceMinutes(minutes: Int) {
        pinPreferences.setLockGraceMinutes(minutes)
    }

    // ---------------------------------------------------------------------------
    // Lock Now (L311 / L318-adjacent)
    // ---------------------------------------------------------------------------

    /** Whether a PIN is currently configured — drives the "Lock now" row enabled state. */
    val pinIsSet: Boolean
        get() = pinPreferences.isPinSet

    /**
     * Triggers an immediate app lock via [PinPreferences.lockNow].
     * Sets lastUnlockAtMillis = 0 so [PinPreferences.shouldLock] returns true on
     * the next MainActivity.onResume() call, which shows the PinLockScreen.
     */
    fun lockNow() {
        if (pinPreferences.isPinSet) {
            pinPreferences.lockNow()
            _message.value = "App will lock on next resume"
        } else {
            _message.value = "Set up a PIN first to use Lock now"
        }
    }

    fun clearMessage() {
        _message.value = null
    }
}

// ---------------------------------------------------------------------------
// Composable
// ---------------------------------------------------------------------------

/**
 * §2.6 Security sub-screen.
 *
 * Rows:
 *   1. "Biometric unlock" switch — disabled if BiometricManager reports no hardware/enrollment.
 *      Toggle-ON triggers Keystore key generation + BiometricPrompt confirmation.
 *      Toggle-OFF clears pref + key immediately.
 *   2. "Auto-lock PIN after" segmented buttons (§2.5 L311) — Immediate/1m/5m/15m/Never.
 *   3. "Change PIN" → [onChangePin] (wires to Screen.PinSetup).
 *   4. "Active sessions" → [onActiveSessions] (§2.11 — wires to Screen.ActiveSessions).
 *   5. "Change password" → [onChangePassword] (§2.9 — wires to Screen.ChangePassword).
 *   6. "Lock now" → forces PinLockScreen on next resume.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SecurityScreen(
    onBack: () -> Unit,
    onChangePin: () -> Unit,
    onChangePassword: () -> Unit,
    onActiveSessions: (() -> Unit)? = null,
    onRecoveryCodes: (() -> Unit)? = null,
    // §2.18 L417 — "Manage 2FA factors" row callback.
    // Role gate: only Owner / Manager / Admin should wire this callback; other
    // roles pass null (row renders disabled). If role check is not wired at the
    // call site, pass a non-null lambda to show for all authenticated users.
    onManageTwoFactorFactors: (() -> Unit)? = null,
    // §2.22 L463 — "Passkeys" row callback. Navigates to PasskeyScreen.
    // Pass null to hide the row (e.g. on pre-API-28 devices detected at the call site,
    // though PasskeyScreen also guards this internally for defence-in-depth).
    onPasskeys: (() -> Unit)? = null,
    viewModel: SecurityViewModel = hiltViewModel(),
) {
    val context = LocalContext.current
    val activity = context as? FragmentActivity
    val snackbarHostState = remember { SnackbarHostState() }

    val biometricEnabled by viewModel.biometricEnabled.collectAsState()
    val promptPending by viewModel.promptPending.collectAsState()
    val reEnrollRequired by viewModel.reEnrollRequired.collectAsState()
    val message by viewModel.message.collectAsState()
    val lockGraceMinutes by viewModel.lockGraceMinutes.collectAsState()

    // Evaluate availability once — only changes if user goes to Settings and
    // adds/removes fingerprints, which triggers a process restart on most OEMs.
    val availabilityCode = remember(context) { viewModel.checkBiometricAvailability() }
    val isBioAvailable = availabilityCode == BiometricManager.BIOMETRIC_SUCCESS
    val bioSubtitle = when (availabilityCode) {
        BiometricManager.BIOMETRIC_SUCCESS ->
            "Require fingerprint or face when opening the app"
        BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED ->
            "No biometrics enrolled — add a fingerprint or face in Settings"
        BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE ->
            "This device has no biometric hardware"
        BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE ->
            "Biometric hardware is temporarily unavailable"
        else ->
            "Biometric unlock is not available on this device"
    }

    LaunchedEffect(message) {
        val msg = message ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(msg)
        viewModel.clearMessage()
    }

    // Helper — shows a BiometricPrompt with CryptoObject for the enable flow.
    // Wrapped in remember so the lambda instance is stable across recompositions;
    // activity reference is captured directly (stable for a single screen lifecycle).
    val showBiometricPrompt: (BiometricPrompt.CryptoObject) -> Unit = remember(activity, viewModel) { { cryptoObject ->
        if (activity != null) {
            val executor = ContextCompat.getMainExecutor(activity)
            val callback = object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    result: BiometricPrompt.AuthenticationResult,
                ) {
                    viewModel.onBiometricConfirmSuccess()
                }

                override fun onAuthenticationError(
                    errorCode: Int,
                    errString: CharSequence,
                ) {
                    viewModel.onBiometricConfirmError(errString.toString())
                }

                override fun onAuthenticationFailed() {
                    // BiometricPrompt shows its own "Try again" UI — no action here.
                    // After 3 consecutive failures the prompt auto-dismisses and
                    // onAuthenticationError fires with ERROR_LOCKOUT (code 7).
                    // At that point onBiometricConfirmError cleans up the key.
                    // The caller is then responsible for navigating to PinLockScreen
                    // (L319 unlock chain: bio fail-3x → PIN).
                    //
                    // TODO (L319): count failures here; at 3 emit a "fallback to PIN"
                    //   event so SecurityScreen (or the activity) can navigate to
                    //   Screen.PinSetup / PinLockScreen.
                }
            }
            val prompt = BiometricPrompt(activity, executor, callback)
            val info = BiometricPrompt.PromptInfo.Builder()
                .setTitle("Confirm biometric")
                .setSubtitle("Verify you can unlock with biometrics")
                // CryptoObject prompts cannot include DEVICE_CREDENTIAL as a
                // fallback on API 28; the user must use the hardware sensor.
                .setNegativeButtonText("Cancel")
                .build()
            prompt.authenticate(info, cryptoObject)
        } else {
            // Unlikely but handle gracefully — activity not available in tests/previews.
            viewModel.onBiometricConfirmError("Activity not available")
        }
    } }

    // §2.16 L401 — require biometric re-auth on entry (DangerZone tier → Full level).
    SensitiveScreenGuard(sensitivity = Sensitivity.DangerZone) {
    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Security",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {

            // ─── Biometric unlock card ───
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text("Biometric unlock", style = MaterialTheme.typography.titleSmall)

                    SecurityPreferenceRow(
                        icon = Icons.Default.Fingerprint,
                        iconDescription = "Biometric unlock",
                        title = "Biometric unlock",
                        subtitle = bioSubtitle,
                        checked = biometricEnabled,
                        enabled = isBioAvailable && !promptPending,
                        onCheckedChange = { wantEnabled ->
                            if (wantEnabled) {
                                val cryptoObject = viewModel.prepareEnableBiometric()
                                if (cryptoObject != null) {
                                    showBiometricPrompt(cryptoObject)
                                }
                            } else {
                                viewModel.disableBiometric()
                            }
                        },
                    )
                }
            }

            // ─── Auto-lock grace window card (§2.5 L311) ───
            Card(modifier = Modifier.fillMaxWidth()) {
                AutoLockRow(
                    selectedMinutes = lockGraceMinutes,
                    onSelect = { viewModel.setLockGraceMinutes(it) },
                )
            }

            // ─── PIN / Password card ───
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(vertical = 8.dp)) {
                    SecurityNavRow(
                        icon = Icons.Default.Pin,
                        title = "Change PIN",
                        subtitle = "Update your local app PIN",
                        onClick = onChangePin,
                    )

                    HorizontalDivider(
                        modifier = Modifier.padding(horizontal = 16.dp),
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                    )

                    // §2.11: Active sessions — view and revoke other sessions.
                    SecurityNavRow(
                        icon = Icons.Default.Devices,
                        title = "Active sessions",
                        subtitle = "View and revoke other logged-in sessions",
                        onClick = { onActiveSessions?.invoke() },
                        enabled = onActiveSessions != null,
                    )

                    HorizontalDivider(
                        modifier = Modifier.padding(horizontal = 16.dp),
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                    )

                    // §2.9: Change-password screen implemented (ActionPlan L340).
                    SecurityNavRow(
                        icon = Icons.Default.Key,
                        title = "Change password",
                        subtitle = "Update your account password",
                        onClick = onChangePassword,
                    )

                    HorizontalDivider(
                        modifier = Modifier.padding(horizontal = 16.dp),
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                    )

                    // §2.18: Manage 2FA factors (ActionPlan L417-L426).
                    // Role gate: Owner / Manager / Admin only. Pass null for other roles.
                    SecurityNavRow(
                        icon = Icons.Default.Shield,
                        title = "Manage 2FA factors",
                        subtitle = "View enrolled factors and add new ones",
                        onClick = { onManageTwoFactorFactors?.invoke() },
                        enabled = onManageTwoFactorFactors != null,
                    )

                    HorizontalDivider(
                        modifier = Modifier.padding(horizontal = 16.dp),
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                    )

                    // §2.19: Recovery codes screen (ActionPlan L427-L438).
                    SecurityNavRow(
                        icon = Icons.Default.VpnKey,
                        title = "Recovery codes",
                        subtitle = "Generate one-time codes for 2FA recovery",
                        onClick = { onRecoveryCodes?.invoke() },
                        enabled = onRecoveryCodes != null,
                    )

                    HorizontalDivider(
                        modifier = Modifier.padding(horizontal = 16.dp),
                        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
                    )

                    // §2.22 L463: Passkeys screen — enroll, list, remove passkeys + hardware keys.
                    SecurityNavRow(
                        icon = Icons.Default.Key,
                        title = "Passkeys",
                        subtitle = "Sign in with biometrics or a hardware security key",
                        onClick = { onPasskeys?.invoke() },
                        enabled = onPasskeys != null,
                    )
                }
            }

            // ─── Lock now ───
            Card(modifier = Modifier.fillMaxWidth()) {
                SecurityNavRow(
                    icon = Icons.Default.Lock,
                    title = "Lock now",
                    subtitle = "Immediately lock the app — requires PIN on next open",
                    onClick = { viewModel.lockNow() },
                    enabled = viewModel.pinIsSet,
                )
            }
        }
    }

    // Re-enroll dialog (L322): fires when KeyPermanentlyInvalidatedException is caught.
    if (reEnrollRequired) {
        ConfirmDialog(
            title = "Biometric changed",
            message = "Your enrolled biometrics have changed since you set up biometric unlock. " +
                    "Re-enable to confirm with your current biometrics.",
            confirmLabel = "Re-enable",
            onConfirm = {
                viewModel.reEnroll(
                    activity = activity ?: return@ConfirmDialog,
                    onShowPrompt = showBiometricPrompt,
                )
            },
            onDismiss = { viewModel.dismissReEnrollDialog() },
            isDestructive = false,
        )
    }
    } // end SensitiveScreenGuard
}

// ---------------------------------------------------------------------------
// Private composables
// ---------------------------------------------------------------------------

/**
 * Preference row with a trailing Switch. Used inside the Biometric unlock card.
 * Follows the same visual contract as [PreferenceRow] in SettingsScreen.
 */
@Composable
private fun SecurityPreferenceRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    iconDescription: String,
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    enabled: Boolean = true,
) {
    // a11y: merge so TalkBack reads the whole row as one node; contentDescription
    //       tells users both the toggle state and the descriptive subtitle.
    val toggleState = if (checked) "toggled on" else "toggled off"
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {
                contentDescription = "$title, $toggleState. $subtitle"
            },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            icon,
            contentDescription = iconDescription,
            modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyMedium)
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            enabled = enabled,
        )
    }
}

/**
 * §2.5 — Auto-lock grace-window row.
 *
 * Displays a segmented-button strip offering {Immediate / 1 min / 5 min / 15 min / Never}.
 * The selected option is persisted via [onSelect] → [SecurityViewModel.setLockGraceMinutes].
 * Helper text below the strip explains the setting to the user.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AutoLockRow(
    selectedMinutes: Int,
    onSelect: (Int) -> Unit,
) {
    data class GraceOption(val label: String, val minutes: Int)
    val options = listOf(
        GraceOption("Immediate", 0),
        GraceOption("1 min", 1),
        GraceOption("5 min", 5),
        GraceOption("15 min", 15),
        GraceOption("Never", GRACE_NEVER),
    )

    Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                Icons.Default.Timer,
                contentDescription = null,
                modifier = Modifier.size(20.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.width(12.dp))
            Text("Auto-lock PIN after", style = MaterialTheme.typography.bodyMedium)
        }
        Spacer(Modifier.height(10.dp))
        SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
            options.forEachIndexed { index, option ->
                SegmentedButton(
                    shape = SegmentedButtonDefaults.itemShape(index = index, count = options.size),
                    onClick = { onSelect(option.minutes) },
                    selected = selectedMinutes == option.minutes,
                    label = { Text(option.label, style = MaterialTheme.typography.labelSmall) },
                )
            }
        }
        Spacer(Modifier.height(6.dp))
        Text(
            "Time of inactivity before PIN is required.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/**
 * Navigation row with a trailing chevron. Used for Change PIN, Change Password,
 * and Lock Now. Follows the same visual contract as [SettingsRow] in SettingsScreen.
 */
@Composable
private fun SecurityNavRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    subtitle: String,
    onClick: () -> Unit,
    enabled: Boolean = true,
) {
    // a11y: mergeDescendants collapses icon + text + chevron into one node;
    //       contentDescription gives a fully descriptive label for each action row.
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .then(
                if (enabled) Modifier.clickable { onClick() }
                else Modifier
            )
            .semantics(mergeDescendants = true) {
                role = Role.Button
                contentDescription = "$title. $subtitle"
            }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            icon,
            contentDescription = null, // decorative — title Text is the accessible name
            modifier = Modifier.size(20.dp),
            tint = if (enabled) MaterialTheme.colorScheme.onSurfaceVariant
            else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.38f),
        )
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                title,
                style = MaterialTheme.typography.bodyMedium,
                color = if (enabled) MaterialTheme.colorScheme.onSurface
                else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f),
            )
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(
                    alpha = if (enabled) 1f else 0.38f,
                ),
            )
        }
        if (enabled) {
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null, // decorative trailing chevron
                tint = MaterialTheme.colorScheme.secondary,
                modifier = Modifier.size(20.dp),
            )
        }
    }
}
