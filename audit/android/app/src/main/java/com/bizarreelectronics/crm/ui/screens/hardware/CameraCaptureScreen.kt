package com.bizarreelectronics.crm.ui.screens.hardware

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.camera.core.CameraSelector
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.view.LifecycleCameraController
import androidx.camera.view.PreviewView
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTransformGestures
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
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bizarreelectronics.crm.data.remote.api.TicketApi
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.RequestBody.Companion.toRequestBody
import timber.log.Timber
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import javax.inject.Inject

// §17.1 L1864-L1867 — CameraX capture screen.
//
// Uses LifecycleCameraController + PreviewView for the live viewfinder.
// Features: flash toggle, lens flip, tap-to-focus (FocusMeteringAction),
// pinch-to-zoom (detectTransformGestures → setZoomRatio), shutter capture
// to server via MultipartUpload. Video mode: 30s / 15MB cap.

data class CameraCaptureUiState(
    val hasCameraPermission: Boolean = false,
    val flashEnabled: Boolean = false,
    val isCapturing: Boolean = false,
    val capturedCount: Int = 0,
    val lastError: String? = null,
    val isVideoMode: Boolean = false,
)

@HiltViewModel
class CameraCaptureViewModel @Inject constructor(
    private val ticketApi: TicketApi,
) : ViewModel() {

    private val _state = MutableStateFlow(CameraCaptureUiState())
    val state = _state.asStateFlow()

    fun setPermission(granted: Boolean) {
        _state.value = _state.value.copy(hasCameraPermission = granted)
    }

    fun toggleFlash() {
        _state.value = _state.value.copy(flashEnabled = !_state.value.flashEnabled)
    }

    fun toggleVideoMode() {
        _state.value = _state.value.copy(isVideoMode = !_state.value.isVideoMode)
    }

    fun uploadCapture(context: Context, ticketId: Long, deviceId: Long, file: File, mimeType: String) {
        if (_state.value.isCapturing) return
        viewModelScope.launch {
            _state.value = _state.value.copy(isCapturing = true, lastError = null)
            try {
                val bytes = file.readBytes()
                val ext = if (mimeType.contains("video")) "mp4" else "jpg"
                val fileName = "ticket-${ticketId}-cam-${System.currentTimeMillis()}.$ext"
                val requestBody = bytes.toRequestBody(mimeType.toMediaTypeOrNull())
                val part = MultipartBody.Part.createFormData("photos", fileName, requestBody)
                val typeBody = "pre".toRequestBody("text/plain".toMediaTypeOrNull())
                val deviceIdBody = deviceId.toString().toRequestBody("text/plain".toMediaTypeOrNull())
                ticketApi.uploadTicketPhotos(
                    ticketId = ticketId,
                    photos = listOf(part),
                    type = typeBody,
                    ticketDeviceId = deviceIdBody,
                )
                _state.value = _state.value.copy(
                    isCapturing = false,
                    capturedCount = _state.value.capturedCount + 1,
                )
            } catch (e: Exception) {
                Timber.w(e, "CameraCapture: upload failed")
                _state.value = _state.value.copy(
                    isCapturing = false,
                    lastError = e.message ?: "Upload failed",
                )
            } finally {
                runCatching { file.delete() }
            }
        }
    }

    fun clearError() {
        _state.value = _state.value.copy(lastError = null)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CameraCaptureScreen(
    ticketId: Long,
    deviceId: Long,
    onBack: () -> Unit,
    viewModel: CameraCaptureViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val snackbarHostState = remember { SnackbarHostState() }

    // Permission handling
    var hasCameraPermission by rememberSaveable {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA)
                == PackageManager.PERMISSION_GRANTED
        )
    }
    var showRationale by rememberSaveable { mutableStateOf(false) }
    val cameraPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        hasCameraPermission = granted
        viewModel.setPermission(granted)
        if (!granted) showRationale = true
    }
    LaunchedEffect(Unit) {
        if (!hasCameraPermission) cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
    }

    // CameraX controller
    val cameraController = remember { LifecycleCameraController(context) }
    val cameraExecutor: ExecutorService = remember { Executors.newSingleThreadExecutor() }
    DisposableEffect(Unit) {
        onDispose { cameraExecutor.shutdown() }
    }

    var lensFacing by rememberSaveable { mutableIntStateOf(CameraSelector.LENS_FACING_BACK) }

    LaunchedEffect(hasCameraPermission, lensFacing) {
        if (!hasCameraPermission) return@LaunchedEffect
        cameraController.cameraSelector = CameraSelector.Builder()
            .requireLensFacing(lensFacing)
            .build()
        cameraController.bindToLifecycle(lifecycleOwner)
    }

    LaunchedEffect(state.flashEnabled) {
        cameraController.imageCaptureFlashMode = if (state.flashEnabled)
            ImageCapture.FLASH_MODE_ON else ImageCapture.FLASH_MODE_OFF
    }

    // Error snackbar
    LaunchedEffect(state.lastError) {
        val err = state.lastError
        if (err != null) {
            snackbarHostState.showSnackbar("Error: $err")
            viewModel.clearError()
        }
    }
    LaunchedEffect(state.capturedCount) {
        if (state.capturedCount > 0) snackbarHostState.showSnackbar("Photo uploaded")
    }

    // Permission rationale dialog
    if (showRationale) {
        AlertDialog(
            onDismissRequest = { showRationale = false },
            title = { Text("Camera permission required") },
            text = { Text("Camera access is needed for live photo capture. Open Settings to grant permission.") },
            confirmButton = {
                TextButton(onClick = {
                    showRationale = false
                    val intent = android.content.Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.fromParts("package", context.packageName, null)
                    }
                    context.startActivity(intent)
                }) { Text("Open Settings") }
            },
            dismissButton = {
                TextButton(onClick = { showRationale = false }) { Text("Dismiss") }
            },
        )
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Camera — Ticket #$ticketId",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    // Flash toggle
                    IconButton(onClick = { viewModel.toggleFlash() }) {
                        Icon(
                            if (state.flashEnabled) Icons.Default.FlashOn else Icons.Default.FlashOff,
                            contentDescription = if (state.flashEnabled) "Flash on" else "Flash off",
                        )
                    }
                    // Video mode toggle
                    IconButton(onClick = { viewModel.toggleVideoMode() }) {
                        Icon(
                            if (state.isVideoMode) Icons.Default.Videocam else Icons.Default.Camera,
                            contentDescription = if (state.isVideoMode) "Switch to photo" else "Switch to video",
                        )
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        if (!hasCameraPermission) {
            Box(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Default.CameraAlt, contentDescription = null, modifier = Modifier.size(64.dp))
                    Spacer(Modifier.height(16.dp))
                    Text("Camera permission required", style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.height(8.dp))
                    Button(onClick = { cameraPermissionLauncher.launch(Manifest.permission.CAMERA) }) {
                        Text("Grant Permission")
                    }
                }
            }
            return@Scaffold
        }

        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            // Live viewfinder
            AndroidView(
                factory = { ctx ->
                    PreviewView(ctx).also { previewView ->
                        previewView.controller = cameraController
                        // Tap-to-focus
                        previewView.setOnTouchListener { _, event ->
                            val meteringPoint = previewView.meteringPointFactory
                                .createPoint(event.x, event.y)
                            val action = FocusMeteringAction.Builder(meteringPoint).build()
                            cameraController.cameraControl?.startFocusAndMetering(action)
                            true
                        }
                    }
                },
                modifier = Modifier
                    .fillMaxSize()
                    .pointerInput(Unit) {
                        // Pinch-to-zoom
                        detectTransformGestures { _, _, zoom, _ ->
                            val currentZoom = cameraController.zoomState.value?.zoomRatio ?: 1f
                            val minZoom = cameraController.zoomState.value?.minZoomRatio ?: 1f
                            val maxZoom = cameraController.zoomState.value?.maxZoomRatio ?: 4f
                            val newZoom = (currentZoom * zoom).coerceIn(minZoom, maxZoom)
                            cameraController.setZoomRatio(newZoom)
                        }
                    },
            )

            // Lens flip button
            IconButton(
                onClick = {
                    lensFacing = if (lensFacing == CameraSelector.LENS_FACING_BACK)
                        CameraSelector.LENS_FACING_FRONT else CameraSelector.LENS_FACING_BACK
                },
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(16.dp)
                    .background(Color.Black.copy(alpha = 0.4f), CircleShape),
            ) {
                Icon(Icons.Default.FlipCameraAndroid, contentDescription = "Flip camera", tint = Color.White)
            }

            // Video mode cap info
            if (state.isVideoMode) {
                Text(
                    "Max 30s / 15 MB",
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.White,
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .padding(16.dp)
                        .background(Color.Black.copy(alpha = 0.5f), MaterialTheme.shapes.small)
                        .padding(horizontal = 8.dp, vertical = 4.dp),
                )
            }

            // Capture count badge
            if (state.capturedCount > 0) {
                Badge(
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .padding(top = 16.dp),
                ) {
                    Text("${state.capturedCount} uploaded")
                }
            }

            // Shutter button
            Box(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 32.dp),
            ) {
                if (state.isCapturing) {
                    CircularProgressIndicator(color = Color.White)
                } else {
                    FilledIconButton(
                        onClick = {
                            val outputFile = File(
                                context.cacheDir,
                                "capture_${System.currentTimeMillis()}.jpg",
                            )
                            val outputOptions = ImageCapture.OutputFileOptions.Builder(outputFile).build()
                            cameraController.takePicture(
                                outputOptions,
                                cameraExecutor,
                                object : ImageCapture.OnImageSavedCallback {
                                    override fun onImageSaved(result: ImageCapture.OutputFileResults) {
                                        viewModel.uploadCapture(
                                            context,
                                            ticketId,
                                            deviceId,
                                            outputFile,
                                            "image/jpeg",
                                        )
                                    }

                                    override fun onError(exception: ImageCaptureException) {
                                        Timber.w(exception, "CameraCapture: takePicture failed")
                                    }
                                },
                            )
                        },
                        modifier = Modifier.size(72.dp),
                        colors = IconButtonDefaults.filledIconButtonColors(
                            containerColor = Color.White,
                            contentColor = Color.Black,
                        ),
                    ) {
                        Icon(
                            if (state.isVideoMode) Icons.Default.Videocam else Icons.Default.Camera,
                            contentDescription = if (state.isVideoMode) "Record" else "Capture photo",
                            modifier = Modifier.size(36.dp),
                        )
                    }
                }
            }

            // Uploading overlay
            if (state.isCapturing) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.Black.copy(alpha = 0.3f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        "Uploading...",
                        color = Color.White,
                        style = MaterialTheme.typography.titleMedium,
                        textAlign = TextAlign.Center,
                    )
                }
            }
        }
    }
}
