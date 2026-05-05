package com.bizarreelectronics.crm.ui.screens.tickets.components

import android.util.Base64
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.HourglassEmpty
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.local.prefs.AppPreferences
import com.bizarreelectronics.crm.data.local.prefs.AuthPreferences
import com.bizarreelectronics.crm.data.remote.api.WaiverApi
import com.bizarreelectronics.crm.data.remote.dto.SignedWaiverDto
import com.bizarreelectronics.crm.data.remote.dto.SubmitSignatureRequest
import com.bizarreelectronics.crm.data.remote.dto.WaiverTemplateDto
import com.bizarreelectronics.crm.util.MultipartUpload
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import timber.log.Timber
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import javax.inject.Inject

// ─── UI state ────────────────────────────────────────────────────────────────

/**
 * Combined template + signing status entry for the list.
 *
 * @param template        Server-managed template (title, body, type, version).
 * @param signedWaiver    Non-null when this template has already been signed.
 * @param isReSignRequired True when the server template version is higher than
 *                        the locally recorded accepted version (L786).
 */
data class WaiverRowState(
    val template: WaiverTemplateDto,
    val signedWaiver: SignedWaiverDto?,
    val isReSignRequired: Boolean,
) {
    /** True when the template is signed AND no re-sign is required. */
    val isSigned: Boolean get() = signedWaiver != null && !isReSignRequired
}

data class WaiverListUiState(
    val rows: List<WaiverRowState> = emptyList(),
    val isLoading: Boolean = true,
    val error: String? = null,
    val actionMessage: String? = null,
    val isSubmitting: Boolean = false,
    /** Template currently open in [WaiverSheet]. Null = sheet hidden. */
    val activeTemplate: WaiverTemplateDto? = null,
)

// ─── ViewModel ───────────────────────────────────────────────────────────────

/**
 * ViewModel for [WaiverListScreen] — §4.14 L780-L786 (plan:L780-L786).
 *
 * Loads required templates + existing signatures from the server, merges them
 * into [WaiverRowState] entries with re-sign detection, and handles signature
 * submission with multipart upload delegation.
 *
 * ## 404 handling
 *
 * Both [WaiverApi.getRequiredTemplates] and [WaiverApi.getSignedWaivers] may
 * return 404 when the server doesn't support the waiver feature. [WaiverListScreen]
 * is only reachable when the caller already confirmed the feature is available
 * (the Waivers action is hidden on 404 — see [TicketDetailScreen]). However, the
 * ViewModel still guards against 404 here so a race condition doesn't crash.
 *
 * ## Re-sign detection (L786)
 *
 * After loading templates, [AppPreferences.getAcceptedWaiverVersion] is compared
 * against [WaiverTemplateDto.version]. If the server version is higher, the row
 * is flagged [WaiverRowState.isReSignRequired].
 */
@HiltViewModel
class WaiverListViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val waiverApi: WaiverApi,
    private val appPreferences: AppPreferences,
    private val authPreferences: AuthPreferences,
    private val multipartUpload: MultipartUpload,
) : ViewModel() {

    private val ticketId: Long =
        savedStateHandle.get<String>("ticketId")?.toLongOrNull() ?: 0L

    private val _state = MutableStateFlow(WaiverListUiState())
    val state: StateFlow<WaiverListUiState> = _state.asStateFlow()

    init {
        load()
    }

    /** Reload templates + signed waivers from the server. */
    fun load() {
        _state.value = _state.value.copy(isLoading = true, error = null)
        viewModelScope.launch {
            try {
                val templatesResp = waiverApi.getRequiredTemplates(ticketId)
                val signedResp = waiverApi.getSignedWaivers(ticketId)

                val templates = templatesResp.data?.templates ?: emptyList()
                val signed = signedResp.data?.waivers ?: emptyList()

                val rows = templates.map { template ->
                    val matchingSigned = signed.firstOrNull { it.templateId == template.id }
                    val localVersion = appPreferences.getAcceptedWaiverVersion(template.id)
                    val isReSignRequired = template.version > localVersion && matchingSigned != null
                    WaiverRowState(
                        template = template,
                        signedWaiver = matchingSigned,
                        isReSignRequired = isReSignRequired,
                    )
                }

                _state.value = _state.value.copy(isLoading = false, rows = rows)
            } catch (e: HttpException) {
                if (e.code() == 404) {
                    // Feature not yet enabled on this server — show empty list
                    _state.value = _state.value.copy(isLoading = false, rows = emptyList())
                } else {
                    _state.value = _state.value.copy(isLoading = false, error = "Failed to load waivers: ${e.message}")
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false, error = "Failed to load waivers: ${e.message}")
            }
        }
    }

    /** Open the sign sheet for [template]. */
    fun openSheet(template: WaiverTemplateDto) {
        _state.value = _state.value.copy(activeTemplate = template)
    }

    /** Dismiss the sign sheet without submitting. */
    fun dismissSheet() {
        _state.value = _state.value.copy(activeTemplate = null)
    }

    /**
     * Submit a completed signature.
     *
     * Posts [request] to the server. On success, records the accepted version in
     * [AppPreferences] for re-sign detection (L786), enqueues the bitmap for
     * multipart upload, and reloads the list.
     *
     * **Never logs [request.signatureBase64].**
     *
     * @param request   Completed [SubmitSignatureRequest] from [WaiverSheet].
     * @param bitmap    Raw PNG bitmap for multipart upload via [MultipartUploadWorker].
     * @param cacheDir  App cache directory for temp PNG file.
     */
    fun submitSignature(
        request: SubmitSignatureRequest,
        bitmap: android.graphics.Bitmap,
        cacheDir: File,
    ) {
        _state.value = _state.value.copy(isSubmitting = true, activeTemplate = null)
        viewModelScope.launch {
            try {
                val response = waiverApi.submitSignature(ticketId, request)
                if (response.success) {
                    // Record accepted version for re-sign gate (L786)
                    appPreferences.setAcceptedWaiverVersion(request.templateId, request.version)

                    // Enqueue multipart upload of signature bitmap
                    val key = UUID.randomUUID().toString()
                    val sigFile = File(cacheDir, "waiver_sig_${key.take(8)}.png")
                    kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                        sigFile.outputStream().use { out ->
                            bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, out)
                        }
                    }
                    multipartUpload.enqueue(
                        localPath = sigFile.absolutePath,
                        targetUrl = "/api/v1/tickets/$ticketId/signatures/${response.data?.id ?: 0}/attachment",
                        fields = mapOf("template_id" to request.templateId),
                        idempotencyKey = key,
                        contentType = "image/png",
                    )

                    _state.value = _state.value.copy(
                        isSubmitting = false,
                        actionMessage = "Waiver signed successfully",
                    )
                    load()
                } else {
                    _state.value = _state.value.copy(
                        isSubmitting = false,
                        actionMessage = "Failed to submit signature",
                    )
                }
            } catch (e: HttpException) {
                val msg = if (e.code() == 404) "Waiver submission not supported by server" else "Submission failed: ${e.message}"
                Timber.tag("WaiverList").w(e, "submitSignature failed (HTTP %d)", e.code())
                _state.value = _state.value.copy(isSubmitting = false, actionMessage = msg)
            } catch (e: Exception) {
                Timber.tag("WaiverList").e(e, "submitSignature failed")
                _state.value = _state.value.copy(isSubmitting = false, actionMessage = "Submission failed: ${e.message}")
            }
        }
    }

    fun clearActionMessage() {
        _state.value = _state.value.copy(actionMessage = null)
    }

    /** ID of the currently active CRM user session. */
    val actorUserId: Long get() = authPreferences.userId
}

// ─── Composable ──────────────────────────────────────────────────────────────

/**
 * WaiverListScreen — §4.14 L780-L786 (plan:L780-L786)
 *
 * Displays the list of required waivers for a ticket, showing signed/pending
 * status. Tapping a pending (or re-sign required) row opens [WaiverSheet].
 *
 * Accessed from [TicketDetailScreen] via the "Waivers" overflow action (hidden
 * on 404 from [WaiverApi.getRequiredTemplates]).
 *
 * @param ticketId      Server ticket ID (matches route parameter "ticketId").
 * @param onBack        Navigate up callback.
 * @param viewModel     Hilt-injected [WaiverListViewModel].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WaiverListScreen(
    ticketId: Long,
    onBack: () -> Unit,
    viewModel: WaiverListViewModel = androidx.hilt.navigation.compose.hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

    LaunchedEffect(state.actionMessage) {
        state.actionMessage?.let { msg ->
            snackbarHostState.showSnackbar(msg)
            viewModel.clearActionMessage()
        }
    }

    // Sign sheet for the currently active template
    state.activeTemplate?.let { template ->
        WaiverSheet(
            template = template,
            actorUserId = viewModel.actorUserId,
            onSubmit = { request, bitmap ->
                viewModel.submitSignature(request, bitmap, context.cacheDir)
            },
            onDismiss = { viewModel.dismissSheet() },
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text("Waivers") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { viewModel.load() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh waivers")
                    }
                },
            )
        },
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
        ) {
            when {
                state.isLoading -> {
                    CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
                }

                state.error != null -> {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(16.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Text(state.error ?: "Unknown error", style = MaterialTheme.typography.bodyMedium)
                        Spacer(Modifier.height(8.dp))
                        Button(onClick = { viewModel.load() }) { Text("Retry") }
                    }
                }

                state.rows.isEmpty() -> {
                    Text(
                        text = "No waivers required for this ticket.",
                        modifier = Modifier
                            .align(Alignment.Center)
                            .padding(16.dp),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }

                else -> {
                    LazyColumn(
                        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        items(state.rows, key = { it.template.id }) { row ->
                            WaiverRowCard(
                                row = row,
                                isSubmitting = state.isSubmitting,
                                onSign = { viewModel.openSheet(row.template) },
                            )
                        }
                    }
                }
            }
        }
    }
}

// ─── Row card ────────────────────────────────────────────────────────────────

/**
 * Single waiver row — shows template title, signed/pending badge, and a Sign
 * button for pending or re-sign-required rows.
 */
@Composable
private fun WaiverRowCard(
    row: WaiverRowState,
    isSubmitting: Boolean,
    onSign: () -> Unit,
) {
    Surface(
        shape = MaterialTheme.shapes.medium,
        tonalElevation = 2.dp,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // Status icon
            if (row.isSigned) {
                Icon(
                    imageVector = Icons.Default.CheckCircle,
                    contentDescription = "Signed",
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(24.dp),
                )
            } else {
                Icon(
                    imageVector = Icons.Default.HourglassEmpty,
                    contentDescription = if (row.isReSignRequired) "Re-sign required" else "Pending",
                    tint = MaterialTheme.colorScheme.error,
                    modifier = Modifier.size(24.dp),
                )
            }

            // Title + status label
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = row.template.title,
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = androidx.compose.ui.text.font.FontWeight.Medium,
                )
                val statusLabel = when {
                    row.isSigned -> "Signed"
                    row.isReSignRequired -> "Re-sign required (template updated)"
                    else -> "Pending signature"
                }
                Text(
                    text = statusLabel,
                    style = MaterialTheme.typography.bodySmall,
                    color = if (row.isSigned) MaterialTheme.colorScheme.primary
                    else MaterialTheme.colorScheme.error,
                )
            }

            // Sign button for pending / re-sign
            if (!row.isSigned || row.isReSignRequired) {
                Spacer(Modifier.width(4.dp))
                Button(
                    onClick = onSign,
                    enabled = !isSubmitting,
                ) {
                    Text(if (row.isReSignRequired) "Re-sign" else "Sign")
                }
            }
        }
    }
}
