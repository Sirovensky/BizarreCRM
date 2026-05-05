package com.bizarreelectronics.crm.ui.screens.customers

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.view.LifecycleCameraController
import androidx.camera.view.PreviewView
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.data.remote.api.CustomerApi
import com.bizarreelectronics.crm.data.remote.dto.CustomerListItem
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.util.BarcodeAnalyzer
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.concurrent.Executors
import javax.inject.Inject

// §5.3 — Customer card barcode / QR scan quick-lookup.
//
// When a tenant prints customer cards with a QR code encoding the customer id
// (or a phone number / email / name), this screen scans the code and routes
// directly to that customer's detail screen.  Falls back to a live results list
// when the code matches multiple customers.
//
// Route: Screen.CustomerBarcodeLookup.route
// Entry point: CustomerCreateScreen "Scan" button.

data class CustomerBarcodeLookupUiState(
    val results: List<CustomerListItem> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null,
    /** Non-null when scanning resolves to a single unambiguous customer id. */
    val navigateToId: Long? = null,
    val lastScanned: String? = null,
)

@HiltViewModel
class CustomerBarcodeLookupViewModel @Inject constructor(
    private val customerApi: CustomerApi,
) : ViewModel() {

    private val _state = MutableStateFlow(CustomerBarcodeLookupUiState())
    val state = _state.asStateFlow()

    fun onBarcodeScanned(raw: String) {
        if (raw.isBlank()) return
        if (raw == _state.value.lastScanned) return   // debounce repeat scans

        _state.value = _state.value.copy(lastScanned = raw, isLoading = true, error = null, results = emptyList())

        viewModelScope.launch {
            try {
                // If the code is a pure numeric string ≤9 digits, attempt a
                // direct id lookup first (tenant-printed cards encode the
                // internal customer id as a QR payload).
                val asId = raw.toLongOrNull()
                if (asId != null && asId > 0 && raw.length <= 9) {
                    try {
                        val resp = customerApi.getCustomer(asId)
                        if (resp.data != null) {
                            _state.value = _state.value.copy(isLoading = false, navigateToId = asId)
                            return@launch
                        }
                    } catch (_: Exception) {
                        // Not a valid id — fall through to search
                    }
                }

                // General search (phone / email / name fragment in the QR payload)
                val resp = customerApi.searchCustomers(raw)
                val hits = resp.data ?: emptyList()
                when {
                    hits.size == 1 -> _state.value = _state.value.copy(isLoading = false, navigateToId = hits[0].id)
                    else           -> _state.value = _state.value.copy(isLoading = false, results = hits)
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoading = false,
                    error = e.message ?: "Scan lookup failed",
                )
            }
        }
    }

    fun clearNavigate() {
        _state.value = _state.value.copy(navigateToId = null)
    }

    fun clearError() {
        _state.value = _state.value.copy(error = null)
    }

    fun resetScan() {
        _state.value = _state.value.copy(
            lastScanned = null,
            results = emptyList(),
            error = null,
            navigateToId = null,
            isLoading = false,
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CustomerBarcodeLookupScreen(
    onBack: () -> Unit,
    onCustomerFound: (Long) -> Unit,
    viewModel: CustomerBarcodeLookupViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }

    // Navigate as soon as a single match is resolved
    LaunchedEffect(state.navigateToId) {
        val id = state.navigateToId ?: return@LaunchedEffect
        viewModel.clearNavigate()
        onCustomerFound(id)
    }

    LaunchedEffect(state.error) {
        val err = state.error ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(err)
        viewModel.clearError()
    }

    // Camera permission
    var hasCameraPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED
        )
    }
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted -> hasCameraPermission = granted }

    LaunchedEffect(Unit) {
        if (!hasCameraPermission) permissionLauncher.launch(Manifest.permission.CAMERA)
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = stringResource(R.string.screen_customer_barcode_lookup),
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.cd_navigate_back),
                        )
                    }
                },
                actions = {
                    if (state.lastScanned != null) {
                        TextButton(onClick = viewModel::resetScan) {
                            Text(stringResource(R.string.customer_barcode_scan_again))
                        }
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            when {
                !hasCameraPermission -> {
                    Box(
                        modifier = Modifier.fillMaxWidth().weight(1f),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(12.dp),
                            modifier = Modifier.padding(32.dp),
                        ) {
                            Icon(
                                Icons.Default.Search,
                                contentDescription = null,
                                modifier = Modifier.size(48.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(
                                stringResource(R.string.customer_barcode_camera_denied),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            FilledTonalButton(onClick = {
                                permissionLauncher.launch(Manifest.permission.CAMERA)
                            }) {
                                Text(stringResource(R.string.customer_barcode_grant_camera))
                            }
                        }
                    }
                }

                state.lastScanned == null -> {
                    // ── Live camera viewfinder ──────────────────────────────
                    val lifecycleOwner = LocalLifecycleOwner.current
                    val cameraController = remember { LifecycleCameraController(context) }

                    Box(
                        modifier = Modifier.fillMaxWidth().weight(1f),
                    ) {
                        AndroidView(
                            factory = { ctx ->
                                val executor = Executors.newSingleThreadExecutor()
                                cameraController.setImageAnalysisAnalyzer(
                                    executor,
                                    BarcodeAnalyzer { barcode, _ ->
                                        viewModel.onBarcodeScanned(barcode)
                                        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                            (ctx.getSystemService(VibratorManager::class.java))
                                                ?.defaultVibrator
                                        } else {
                                            @Suppress("DEPRECATION")
                                            ctx.getSystemService(Vibrator::class.java)
                                        }
                                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                            vibrator?.vibrate(
                                                VibrationEffect.createOneShot(
                                                    50L,
                                                    VibrationEffect.DEFAULT_AMPLITUDE,
                                                )
                                            )
                                        }
                                    }
                                )
                                cameraController.bindToLifecycle(lifecycleOwner)
                                PreviewView(ctx).also { it.controller = cameraController }
                            },
                            modifier = Modifier
                                .fillMaxSize()
                                .semantics {
                                    contentDescription = context.getString(
                                        R.string.customer_barcode_viewfinder_cd,
                                    )
                                },
                        )

                        Surface(
                            color = MaterialTheme.colorScheme.surface.copy(alpha = 0.70f),
                            modifier = Modifier
                                .align(Alignment.BottomCenter)
                                .fillMaxWidth(),
                        ) {
                            Text(
                                stringResource(R.string.customer_barcode_hint),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurface,
                                modifier = Modifier.padding(12.dp),
                            )
                        }
                    }
                }

                state.isLoading -> {
                    Box(
                        modifier = Modifier.fillMaxWidth().weight(1f),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator()
                    }
                }

                state.results.isEmpty() -> {
                    // No match after search
                    Box(
                        modifier = Modifier.fillMaxWidth().weight(1f),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(12.dp),
                            modifier = Modifier.padding(32.dp),
                        ) {
                            Text(
                                stringResource(R.string.customer_barcode_no_match, state.lastScanned ?: ""),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            FilledTonalButton(onClick = viewModel::resetScan) {
                                Text(stringResource(R.string.customer_barcode_scan_again))
                            }
                        }
                    }
                }

                else -> {
                    // Multiple candidates — let user pick
                    Text(
                        stringResource(R.string.customer_barcode_multiple_matches),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                    LazyColumn(modifier = Modifier.weight(1f)) {
                        items(state.results, key = { it.id }) { customer ->
                            val displayName = listOfNotNull(customer.firstName, customer.lastName)
                                .joinToString(" ")
                                .ifBlank { customer.organization ?: "Customer #${customer.id}" }
                            val subtitle = listOfNotNull(
                                customer.phone ?: customer.mobile,
                                customer.email,
                            ).joinToString(" · ")

                            ListItem(
                                headlineContent = { Text(displayName) },
                                supportingContent = { if (subtitle.isNotBlank()) Text(subtitle) },
                                leadingContent = {
                                    Icon(
                                        Icons.Default.Person,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                },
                                modifier = Modifier.clickable(
                                    onClickLabel = stringResource(
                                        R.string.customer_barcode_open_cd,
                                        displayName,
                                    ),
                                    role = Role.Button,
                                ) { onCustomerFound(customer.id) },
                            )
                            HorizontalDivider()
                        }
                    }
                }
            }
        }
    }
}
