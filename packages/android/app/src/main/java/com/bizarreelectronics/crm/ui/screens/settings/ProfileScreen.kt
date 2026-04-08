package com.bizarreelectronics.crm.ui.screens.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.AuthApi
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
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
)

@HiltViewModel
class ProfileViewModel @Inject constructor(
    private val authApi: AuthApi,
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

    fun onChangePasswordClick() {
        _state.value = _state.value.copy(snackbarMessage = "Change password is not implemented yet")
    }

    fun onChangePinClick() {
        _state.value = _state.value.copy(snackbarMessage = "Change PIN is not implemented yet")
    }

    fun clearSnackbar() {
        _state.value = _state.value.copy(snackbarMessage = null)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileScreen(
    viewModel: ProfileViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.snackbarMessage) {
        val msg = state.snackbarMessage
        if (msg != null) {
            snackbarHostState.showSnackbar(msg)
            viewModel.clearSnackbar()
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(title = { Text("Profile") })
        },
    ) { padding ->
        if (state.isLoading && state.username.isBlank()) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                CircularProgressIndicator()
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
                // Avatar placeholder
                Surface(
                    shape = MaterialTheme.shapes.extraLarge,
                    color = MaterialTheme.colorScheme.primaryContainer,
                    modifier = Modifier.size(80.dp),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        val initials = buildString {
                            state.firstName.firstOrNull()?.let { append(it.uppercase()) }
                            state.lastName.firstOrNull()?.let { append(it.uppercase()) }
                        }.ifBlank { state.username.take(2).uppercase() }

                        Text(
                            initials,
                            style = MaterialTheme.typography.headlineMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onPrimaryContainer,
                        )
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
                    Text(
                        state.role.replaceFirstChar { it.uppercase() },
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
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
                    Text(
                        errorText,
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }

                // Actions
                OutlinedButton(
                    onClick = viewModel::onChangePasswordClick,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(Icons.Default.Lock, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Change Password")
                }

                OutlinedButton(
                    onClick = viewModel::onChangePinClick,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(Icons.Default.Pin, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Change PIN")
                }
            }
        }
    }
}

@Composable
private fun ProfileDetailRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    value: String,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp))
        Column {
            Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, style = MaterialTheme.typography.bodyMedium)
        }
    }
}
