package com.bizarreelectronics.crm.ui.screens.settings

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription

import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import coil3.compose.AsyncImage
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import com.bizarreelectronics.crm.data.remote.api.SettingsApi
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.RequestBody.Companion.toRequestBody
import javax.inject.Inject

data class ProfileUiState(
    val username: String = "",
    val firstName: String = "",
    val lastName: String = "",
    val email: String = "",
    val role: String = "",
    val avatarUrl: String? = null,
    val isLoading: Boolean = true,
    val error: String? = null,
    val snackbarMessage: String? = null,
    val isSubmitting: Boolean = false,
    // U6 fix: VM drives dialog close by bumping a success counter when a
    // change-password or change-pin mutation succeeds.
    val passwordChangeSuccessCounter: Int = 0,
    val pinChangeSuccessCounter: Int = 0,
)

@HiltViewModel
class ProfileViewModel @Inject constructor(
    private val authApi: AuthApi,
    private val settingsApi: SettingsApi,
    private val authPreferences: AuthPreferences,
) : ViewModel() {

    private val _state = MutableStateFlow(ProfileUiState())
    val state = _state.asStateFlow()

    init {
        loadProfile()
    }

    private fun loadProfile() {
        // Start with cached prefs for instant display
        _state.value = _state.value.copy(
            username = authPreferences.username.orEmpty(),
            firstName = authPreferences.userFirstName.orEmpty(),
            lastName = authPreferences.userLastName.orEmpty(),
            role = authPreferences.userRole.orEmpty(),
            isLoading = true,
        )

        // Then refresh from server
        viewModelScope.launch {
            try {
                val response = authApi.getMe()
                val user = response.data
                if (user != null) {
                    _state.value = _state.value.copy(
                        username = user.username,
                        firstName = user.firstName.orEmpty(),
                        lastName = user.lastName.orEmpty(),
                        email = user.email.orEmpty(),
                        role = user.role,
                        avatarUrl = user.avatarUrl,
                        isLoading = false,
                    )
                } else {
                    _state.value = _state.value.copy(isLoading = false)
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = e.message ?: "Failed to load profile",
                )
            }
        }
    }

    // U6 fix: actually call the change-password endpoint instead of showing a
    // "not implemented yet" toast.
    fun changePassword(currentPassword: String, newPassword: String) {
        if (_state.value.isSubmitting) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isSubmitting = true)
            try {
                val response = authApi.changePassword(
                    mapOf(
                        "currentPassword" to currentPassword,
                        "newPassword" to newPassword,
                    ),
                )
                if (response.success) {
                    _state.value = _state.value.copy(
                        isSubmitting = false,
                        snackbarMessage = "Password changed successfully",
                        passwordChangeSuccessCounter = _state.value.passwordChangeSuccessCounter + 1,
                    )
                } else {
                    _state.value = _state.value.copy(
                        isSubmitting = false,
                        snackbarMessage = response.message ?: "Failed to change password",
                    )
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    snackbarMessage = "Failed to change password: ${e.message}",
                )
            }
        }
    }

    // U6 fix: same for PIN.
    fun changePin(currentPin: String, newPin: String) {
        if (_state.value.isSubmitting) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isSubmitting = true)
            try {
                val response = authApi.changePin(
                    mapOf(
                        "currentPin" to currentPin,
                        "newPin" to newPin,
                    ),
                )
                if (response.success) {
                    _state.value = _state.value.copy(
                        isSubmitting = false,
                        snackbarMessage = "PIN changed successfully",
                        pinChangeSuccessCounter = _state.value.pinChangeSuccessCounter + 1,
                    )
                } else {
                    _state.value = _state.value.copy(
                        isSubmitting = false,
                        snackbarMessage = response.message ?: "Failed to change PIN",
                    )
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    snackbarMessage = "Failed to change PIN: ${e.message}",
                )
            }
        }
    }

    fun clearSnackbar() {
        _state.value = _state.value.copy(snackbarMessage = null)
    }

    /**
     * L1981 — Upload a new avatar image via POST /auth/avatar (multipart).
     * The URI is read as bytes from the content resolver and sent as
     * "avatar" form field. On success, [ProfileUiState.avatarUrl] is updated
     * with the server-returned URL.
     *
     * 404 on the endpoint is tolerated (plan constraint) — an error snackbar
     * is shown but the upload failure does not crash or block the screen.
     *
     * @param context  Android Context for opening the content resolver.
     * @param uri      Content URI of the selected image from PhotoPicker.
     */
    fun uploadAvatar(context: android.content.Context, uri: Uri) {
        if (_state.value.isSubmitting) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isSubmitting = true)
            try {
                val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                if (bytes == null) {
                    _state.value = _state.value.copy(
                        isSubmitting = false,
                        snackbarMessage = "Could not read selected image",
                    )
                    return@launch
                }
                val mimeType = context.contentResolver.getType(uri) ?: "image/jpeg"
                val requestBody = bytes.toRequestBody(mimeType.toMediaTypeOrNull())
                val part = MultipartBody.Part.createFormData("avatar", "avatar.jpg", requestBody)
                val response = settingsApi.uploadAvatar(part)
                if (response.success) {
                    val newUrl = response.data?.avatarUrl
                    _state.value = _state.value.copy(
                        isSubmitting = false,
                        avatarUrl = newUrl ?: _state.value.avatarUrl,
                        snackbarMessage = "Avatar updated",
                    )
                } else {
                    _state.value = _state.value.copy(
                        isSubmitting = false,
                        snackbarMessage = response.message ?: "Failed to upload avatar",
                    )
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSubmitting = false,
                    snackbarMessage = "Avatar upload failed: ${e.message}",
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileScreen(
    onBack: () -> Unit = {},
    viewModel: ProfileViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val context = LocalContext.current

    var showPasswordDialog by rememberSaveable { mutableStateOf(false) }
    var showPinDialog by rememberSaveable { mutableStateOf(false) }

    // L1981 — PhotoPicker launcher (Android 13+ native picker; falls back to
    // GetContent on older API via the Jetpack contract).
    val photoPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickVisualMedia(),
    ) { uri: Uri? ->
        if (uri != null) {
            viewModel.uploadAvatar(context, uri)
        }
    }

    LaunchedEffect(state.snackbarMessage) {
        val msg = state.snackbarMessage
        if (msg != null) {
            snackbarHostState.showSnackbar(msg)
            viewModel.clearSnackbar()
        }
    }

    LaunchedEffect(state.passwordChangeSuccessCounter) {
        if (state.passwordChangeSuccessCounter > 0) {
            showPasswordDialog = false
        }
    }

    LaunchedEffect(state.pinChangeSuccessCounter) {
        if (state.pinChangeSuccessCounter > 0) {
            showPinDialog = false
        }
    }

    if (showPasswordDialog) {
        ChangePasswordDialog(
            isSubmitting = state.isSubmitting,
            onDismiss = { showPasswordDialog = false },
            onSubmit = { current, new ->
                viewModel.changePassword(current, new)
            },
        )
    }

    if (showPinDialog) {
        ChangePinDialog(
            isSubmitting = state.isSubmitting,
            onDismiss = { showPinDialog = false },
            onSubmit = { current, new ->
                viewModel.changePin(current, new)
            },
        )
    }

    Scaffold(
        // D5-8: password / PIN change fields live deep in the scroll and would
        // be hidden under the soft keyboard without explicit imePadding.
        modifier = Modifier.imePadding(),
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = "Profile",
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
    ) { padding ->
        if (state.isLoading && state.username.isBlank()) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                // a11y: announce loading state to screen readers
                CircularProgressIndicator(
                    modifier = Modifier.semantics { contentDescription = "Loading profile" },
                )
            }
        } else {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(16.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                // L1981 — Avatar: Coil-loaded if avatarUrl is present, else initials fallback.
                val initials = buildString {
                    state.firstName.firstOrNull()?.let { append(it.uppercase()) }
                    state.lastName.firstOrNull()?.let { append(it.uppercase()) }
                }.ifBlank { state.username.take(2).uppercase() }

                Box(contentAlignment = Alignment.BottomEnd) {
                    if (!state.avatarUrl.isNullOrBlank()) {
                        AsyncImage(
                            model = state.avatarUrl,
                            contentDescription = "Profile avatar",
                            contentScale = ContentScale.Crop,
                            modifier = Modifier
                                .size(80.dp)
                                .clip(CircleShape),
                        )
                    } else {
                        // Initials fallback
                        Surface(
                            shape = CircleShape,
                            color = MaterialTheme.colorScheme.primaryContainer,
                            modifier = Modifier
                                .size(80.dp)
                                .semantics { contentDescription = "Profile avatar: $initials" },
                        ) {
                            Box(contentAlignment = Alignment.Center) {
                                Text(
                                    initials,
                                    style = MaterialTheme.typography.headlineMedium,
                                    fontWeight = FontWeight.Bold,
                                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                                )
                            }
                        }
                    }

                    // "Change photo" floating icon button
                    SmallFloatingActionButton(
                        onClick = {
                            photoPickerLauncher.launch(
                                PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                            )
                        },
                        modifier = Modifier
                            .size(28.dp)
                            .semantics { contentDescription = "Change profile photo" },
                        containerColor = MaterialTheme.colorScheme.primary,
                        contentColor = MaterialTheme.colorScheme.onPrimary,
                    ) {
                        Icon(
                            Icons.Default.CameraAlt,
                            contentDescription = null,
                            modifier = Modifier.size(14.dp),
                        )
                    }
                }

                // "Change photo" text button (more discoverable)
                TextButton(
                    onClick = {
                        photoPickerLauncher.launch(
                            PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                        )
                    },
                    enabled = !state.isSubmitting,
                ) {
                    if (state.isSubmitting) {
                        CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.width(6.dp))
                        Text("Uploading...")
                    } else {
                        Text("Change photo")
                    }
                }

                val fullName = "${state.firstName} ${state.lastName}".trim()
                if (fullName.isNotBlank()) {
                    Text(
                        fullName,
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                    )
                }

                if (state.role.isNotBlank()) {
                    val roleLabel = state.role.replaceFirstChar { it.uppercase() }
                    // a11y: role badge — announces the user's assigned role
                    Text(
                        roleLabel,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.semantics { contentDescription = "Your role: $roleLabel" },
                    )
                }

                HorizontalDivider()

                // Profile details
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        ProfileDetailRow(
                            icon = Icons.Default.Person,
                            label = "Username",
                            value = state.username.ifBlank { "-" },
                        )
                        ProfileDetailRow(
                            icon = Icons.Default.Email,
                            label = "Email",
                            value = state.email.ifBlank { "-" },
                        )
                        ProfileDetailRow(
                            icon = Icons.Default.Security,
                            label = "2FA Status",
                            value = "Enabled",
                        )
                    }
                }

                state.error?.let { errorText ->
                    // a11y: error message — contentDescription prefixes "Error:" so TalkBack reads it distinctly
                    Text(
                        errorText,
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.semantics { contentDescription = "Error: $errorText" },
                    )
                }

                // Actions
                // a11y: explicit contentDescription so TalkBack reads the full action phrase
                OutlinedButton(
                    onClick = { showPasswordDialog = true },
                    modifier = Modifier
                        .fillMaxWidth()
                        .semantics { contentDescription = "Change password" },
                ) {
                    // decorative — parent button semantics supplies the accessible name
                    Icon(Icons.Default.Lock, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Change Password")
                }

                // a11y: explicit contentDescription so TalkBack reads the full action phrase
                OutlinedButton(
                    onClick = { showPinDialog = true },
                    modifier = Modifier
                        .fillMaxWidth()
                        .semantics { contentDescription = "Change PIN" },
                ) {
                    // decorative — parent button semantics supplies the accessible name
                    Icon(Icons.Default.Pin, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Change PIN")
                }
            }
        }
    }
}

@Composable
private fun ChangePasswordDialog(
    isSubmitting: Boolean,
    onDismiss: () -> Unit,
    onSubmit: (currentPassword: String, newPassword: String) -> Unit,
) {
    var currentPassword by rememberSaveable { mutableStateOf("") }
    var newPassword by rememberSaveable { mutableStateOf("") }
    var confirmPassword by rememberSaveable { mutableStateOf("") }

    val passwordsMatch = newPassword == confirmPassword
    val newIsLongEnough = newPassword.length >= 8
    val canSubmit = currentPassword.isNotBlank() &&
        newIsLongEnough &&
        passwordsMatch &&
        !isSubmitting

    AlertDialog(
        onDismissRequest = {
            if (!isSubmitting) onDismiss()
        },
        title = { Text("Change Password") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = currentPassword,
                    onValueChange = { currentPassword = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Current password") },
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                    enabled = !isSubmitting,
                )
                OutlinedTextField(
                    value = newPassword,
                    onValueChange = { newPassword = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("New password (min 8 chars)") },
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                    enabled = !isSubmitting,
                    isError = newPassword.isNotEmpty() && !newIsLongEnough,
                    supportingText = {
                        if (newPassword.isNotEmpty() && !newIsLongEnough) {
                            Text(
                                "Password must be at least 8 characters",
                                color = MaterialTheme.colorScheme.error,
                            )
                        }
                    },
                )
                OutlinedTextField(
                    value = confirmPassword,
                    onValueChange = { confirmPassword = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Confirm new password") },
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                    enabled = !isSubmitting,
                    isError = confirmPassword.isNotEmpty() && !passwordsMatch,
                    supportingText = {
                        if (confirmPassword.isNotEmpty() && !passwordsMatch) {
                            Text(
                                "Passwords do not match",
                                color = MaterialTheme.colorScheme.error,
                            )
                        }
                    },
                )
            }
        },
        confirmButton = {
            // a11y: confirm button — contentDescription reflects current submitting state
            TextButton(
                onClick = {
                    if (canSubmit) onSubmit(currentPassword, newPassword)
                },
                enabled = canSubmit,
                modifier = Modifier.semantics {
                    contentDescription = if (isSubmitting) "Saving password change" else "Save password change"
                    role = Role.Button
                },
            ) {
                if (isSubmitting) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Saving...")
                } else {
                    Text("Save")
                }
            }
        },
        dismissButton = {
            // a11y: dismiss button
            TextButton(
                onClick = onDismiss,
                enabled = !isSubmitting,
                modifier = Modifier.semantics {
                    contentDescription = "Cancel password change"
                    role = Role.Button
                },
            ) {
                Text("Cancel")
            }
        },
    )
}

@Composable
private fun ChangePinDialog(
    isSubmitting: Boolean,
    onDismiss: () -> Unit,
    onSubmit: (currentPin: String, newPin: String) -> Unit,
) {
    var currentPin by rememberSaveable { mutableStateOf("") }
    var newPin by rememberSaveable { mutableStateOf("") }
    var confirmPin by rememberSaveable { mutableStateOf("") }

    val newIsValid = newPin.length in 4..8 && newPin.all { it.isDigit() }
    val pinsMatch = newPin == confirmPin
    val canSubmit = currentPin.isNotBlank() && newIsValid && pinsMatch && !isSubmitting

    AlertDialog(
        onDismissRequest = {
            if (!isSubmitting) onDismiss()
        },
        title = { Text("Change PIN") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = currentPin,
                    onValueChange = { value ->
                        if (value.length <= 8 && value.all { it.isDigit() }) currentPin = value
                    },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Current PIN") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                    enabled = !isSubmitting,
                )
                OutlinedTextField(
                    value = newPin,
                    onValueChange = { value ->
                        if (value.length <= 8 && value.all { it.isDigit() }) newPin = value
                    },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("New PIN (4-8 digits)") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                    enabled = !isSubmitting,
                    isError = newPin.isNotEmpty() && !newIsValid,
                    supportingText = {
                        if (newPin.isNotEmpty() && !newIsValid) {
                            Text(
                                "PIN must be 4-8 digits",
                                color = MaterialTheme.colorScheme.error,
                            )
                        }
                    },
                )
                OutlinedTextField(
                    value = confirmPin,
                    onValueChange = { value ->
                        if (value.length <= 8 && value.all { it.isDigit() }) confirmPin = value
                    },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Confirm new PIN") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                    enabled = !isSubmitting,
                    isError = confirmPin.isNotEmpty() && !pinsMatch,
                    supportingText = {
                        if (confirmPin.isNotEmpty() && !pinsMatch) {
                            Text(
                                "PINs do not match",
                                color = MaterialTheme.colorScheme.error,
                            )
                        }
                    },
                )
            }
        },
        confirmButton = {
            // a11y: confirm button — contentDescription reflects current submitting state
            TextButton(
                onClick = {
                    if (canSubmit) onSubmit(currentPin, newPin)
                },
                enabled = canSubmit,
                modifier = Modifier.semantics {
                    contentDescription = if (isSubmitting) "Saving PIN change" else "Save PIN change"
                    role = Role.Button
                },
            ) {
                if (isSubmitting) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Saving...")
                } else {
                    Text("Save")
                }
            }
        },
        dismissButton = {
            // a11y: dismiss button
            TextButton(
                onClick = onDismiss,
                enabled = !isSubmitting,
                modifier = Modifier.semantics {
                    contentDescription = "Cancel PIN change"
                    role = Role.Button
                },
            ) {
                Text("Cancel")
            }
        },
    )
}

@Composable
private fun ProfileDetailRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    value: String,
) {
    // a11y: mergeDescendants collapses icon + label + value into one node;
    // contentDescription announces the pair as "<label>: <value>"
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) { contentDescription = "$label: $value" },
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // decorative — merged row contentDescription supplies the announcement
        Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp))
        Column {
            Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, style = MaterialTheme.typography.bodyMedium)
        }
    }
}
