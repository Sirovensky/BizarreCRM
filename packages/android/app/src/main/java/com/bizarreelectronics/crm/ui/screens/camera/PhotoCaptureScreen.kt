package com.bizarreelectronics.crm.ui.screens.camera

import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.TicketApi
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.theme.BrandMono
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.ByteArrayOutputStream
import javax.inject.Inject

// U3 / N10 fix: The previous PhotoCaptureScreen was a lie. It incremented a
// local counter and never uploaded anything. Full CameraX integration requires
// build.gradle dependency edits we can't make from the Kotlin source tree, so
// this screen falls back to the minimum viable implementation described in the
// audit: a gallery picker (ActivityResultContracts.GetContent) that uploads the
// selected image to the existing POST /tickets/{id}/photos endpoint.

data class PhotoCaptureUiState(
    val uploadedCount: Int = 0,
    val isUploading: Boolean = false,
    val lastError: String? = null,
)

@HiltViewModel
class PhotoCaptureViewModel @Inject constructor(
    private val ticketApi: TicketApi,
) : ViewModel() {

    private val _state = MutableStateFlow(PhotoCaptureUiState())
    val state = _state.asStateFlow()

    fun uploadImage(
        context: Context,
        ticketId: Long,
        uri: Uri,
        photoType: String,
    ) {
        if (_state.value.isUploading) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isUploading = true, lastError = null)
            try {
                val bytes = readBytesFromUri(context, uri)
                    ?: throw IllegalStateException("Could not read selected image")
                if (bytes.isEmpty()) {
                    throw IllegalStateException("Selected image is empty")
                }

                val mime = context.contentResolver.getType(uri) ?: "image/jpeg"
                val extension = when {
                    mime.contains("png") -> "png"
                    mime.contains("webp") -> "webp"
                    else -> "jpg"
                }
                val fileName = "ticket-${ticketId}-${System.currentTimeMillis()}.$extension"

                val requestBody = bytes.toRequestBody(mime.toMediaTypeOrNull())
                val part = MultipartBody.Part.createFormData("photos", fileName, requestBody)
                val typeBody = photoType.toRequestBody("text/plain".toMediaTypeOrNull())

                ticketApi.uploadTicketPhotos(
                    ticketId = ticketId,
                    photos = listOf(part),
                    type = typeBody,
                )

                _state.value = _state.value.copy(
                    isUploading = false,
                    uploadedCount = _state.value.uploadedCount + 1,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isUploading = false,
                    lastError = e.message ?: "Failed to upload photo",
                )
            }
        }
    }

    fun clearError() {
        _state.value = _state.value.copy(lastError = null)
    }

    private fun readBytesFromUri(context: Context, uri: Uri): ByteArray? {
        return context.contentResolver.openInputStream(uri)?.use { input ->
            val output = ByteArrayOutputStream()
            input.copyTo(output)
            output.toByteArray()
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PhotoCaptureScreen(
    ticketId: Long,
    onBack: () -> Unit,
    viewModel: PhotoCaptureViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }

    // rememberSaveable so selection across rotation is retained.
    var selectedType by rememberSaveable { mutableStateOf("pre") }

    // Gallery picker — single image at a time. We use GetContent("image/*")
    // so the user can pick from gallery OR any registered document provider
    // (Files app, Google Drive, etc.).
    val galleryPicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent(),
    ) { uri: Uri? ->
        if (uri != null) {
            viewModel.uploadImage(
                context = context,
                ticketId = ticketId,
                uri = uri,
                photoType = selectedType,
            )
        }
    }

    // Surface upload errors via snackbar.
    LaunchedEffect(state.lastError) {
        val err = state.lastError
        if (err != null) {
            snackbarHostState.showSnackbar("Upload failed: $err")
            viewModel.clearError()
        }
    }

    // Surface successful uploads via snackbar.
    LaunchedEffect(state.uploadedCount) {
        if (state.uploadedCount > 0) {
            snackbarHostState.showSnackbar("Photo uploaded ($selectedType-condition)")
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Photos - Ticket #$ticketId",
                titleContent = {
                    Text(
                        buildAnnotatedString {
                            append("Photos - Ticket ")
                            withStyle(SpanStyle(fontFamily = BrandMono.fontFamily, fontSize = 14.sp)) {
                                append("#$ticketId")
                            }
                        },
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (state.uploadedCount > 0) {
                        Badge(modifier = Modifier.padding(end = 16.dp)) {
                            Text("${state.uploadedCount}")
                        }
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // Type selector (pre/post condition)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                FilterChip(
                    selected = selectedType == "pre",
                    onClick = { selectedType = "pre" },
                    label = { Text("Pre-Condition") },
                    leadingIcon = if (selectedType == "pre") {
                        { Icon(Icons.Default.Check, contentDescription = null, modifier = Modifier.size(18.dp)) }
                    } else {
                        null
                    },
                    modifier = Modifier.weight(1f),
                )
                FilterChip(
                    selected = selectedType == "post",
                    onClick = { selectedType = "post" },
                    label = { Text("Post-Condition") },
                    leadingIcon = if (selectedType == "post") {
                        { Icon(Icons.Default.Check, contentDescription = null, modifier = Modifier.size(18.dp)) }
                    } else {
                        null
                    },
                    modifier = Modifier.weight(1f),
                )
            }

            // Info / status area.
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
                    .background(MaterialTheme.colorScheme.surfaceContainerLowest),
                contentAlignment = Alignment.Center,
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.padding(24.dp),
                ) {
                    Icon(
                        Icons.Default.PhotoLibrary,
                        contentDescription = null,
                        modifier = Modifier.size(72.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                    )
                    Spacer(modifier = Modifier.height(16.dp))
                    Text(
                        "Pick a photo from your gallery to attach to this ticket",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        "Live camera capture coming soon",
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                        textAlign = TextAlign.Center,
                        style = MaterialTheme.typography.labelSmall,
                    )
                    if (state.isUploading) {
                        Spacer(modifier = Modifier.height(16.dp))
                        CircularProgressIndicator(
                            color = MaterialTheme.colorScheme.primary,
                        )
                        Text(
                            "Uploading...",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            style = MaterialTheme.typography.bodySmall,
                            modifier = Modifier.padding(top = 8.dp),
                        )
                    }
                }
            }

            // Upload controls.
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(24.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Button(
                    onClick = { galleryPicker.launch("image/*") },
                    enabled = !state.isUploading,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(56.dp)
                        .border(
                            width = 2.dp,
                            color = MaterialTheme.colorScheme.primary,
                            shape = CircleShape,
                        ),
                    shape = CircleShape,
                ) {
                    Icon(
                        Icons.Default.PhotoLibrary,
                        contentDescription = "Pick from gallery",
                        modifier = Modifier.size(24.dp),
                    )
                    Spacer(modifier = Modifier.width(12.dp))
                    Text("Pick From Gallery")
                }
            }
        }
    }
}
