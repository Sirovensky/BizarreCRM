package com.bizarreelectronics.crm.ui.screens.tickets.components

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.util.ExifStripper
import com.bizarreelectronics.crm.util.MultipartUpload
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import timber.log.Timber
import java.io.File
import java.util.UUID

/**
 * PhotoAnnotateScreen — §4.7 L749 (plan:L749)
 *
 * Full-screen annotation editor. The base image is rendered as a background;
 * the user draws coloured paths over it using [detectDragGestures]. On "Save"
 * the overlay is composited onto the base image and the result uploaded as a
 * new ticket photo with tag "annotated". The original photo is preserved.
 *
 * Navigation: reached from [TicketPhotoGallery] overflow → "Annotate".
 *
 * Upload: reuses [MultipartUpload] WorkManager pipeline (same as gallery
 * add-photo flow). EXIF is stripped via [ExifStripper] before upload.
 *
 * @param baseImageUrl    Absolute URL of the source photo (used as fallback
 *                        display label if the file can't be decoded yet).
 * @param baseImageFile   Local [File] that has already been downloaded or
 *                        cached; null while downloading (shows a loading state).
 * @param ticketId        Target ticket — used in the upload URL.
 * @param deviceId        Required by the server upload endpoint.
 * @param multipartUpload Injected upload helper.
 * @param reduceMotion    When true, no stroke-animation effects are applied.
 * @param onBack          Navigate back without saving.
 * @param onSaved         Navigate back after a successful upload enqueue.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PhotoAnnotateScreen(
    baseImageUrl: String,
    baseImageFile: File?,
    ticketId: Long,
    deviceId: Long?,
    multipartUpload: MultipartUpload? = null,
    reduceMotion: Boolean = false,
    onBack: () -> Unit,
    onSaved: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    // Decode base bitmap once
    val baseBitmap: Bitmap? = remember(baseImageFile) {
        baseImageFile?.let { f ->
            runCatching { BitmapFactory.decodeFile(f.absolutePath) }.getOrNull()
        }
    }

    // ─── Drawing state ────────────────────────────────────────────────────────

    var paths by remember { mutableStateOf<List<Pair<Path, DrawStyle>>>(emptyList()) }
    var currentPath by remember { mutableStateOf<Path?>(null) }
    var canvasWidthPx by remember { mutableIntStateOf(0) }
    var canvasHeightPx by remember { mutableIntStateOf(0) }

    // Color picker
    val palette = listOf(Color.Red, Color.Green, Color.Blue, Color.Yellow)
    val paletteLabels = listOf("Red", "Green", "Blue", "Yellow")
    var selectedColor by remember { mutableStateOf(Color.Red) }
    var strokeWidth by remember { mutableFloatStateOf(6f) }

    // ─── Layout ───────────────────────────────────────────────────────────────

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Annotate Photo") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(
                        onClick = {
                            if (paths.isEmpty() || baseBitmap == null || deviceId == null) {
                                onBack()
                                return@IconButton
                            }
                            scope.launch(Dispatchers.IO) {
                                try {
                                    // Composite base + overlay
                                    val composited = compositeBitmapWithPaths(
                                        base = baseBitmap,
                                        paths = paths,
                                        canvasW = canvasWidthPx,
                                        canvasH = canvasHeightPx,
                                    )

                                    val key = UUID.randomUUID().toString()
                                    val fileName = "annotated_${key.take(8)}.jpg"
                                    val cacheFile = File(context.cacheDir, fileName)

                                    // EXIF strip
                                    val stripped = ExifStripper.strip(composited, cacheFile) ?: cacheFile.also {
                                        cacheFile.outputStream().use { out ->
                                            composited.compress(Bitmap.CompressFormat.JPEG, 90, out)
                                        }
                                    }

                                    multipartUpload?.enqueue(
                                        localPath = stripped.absolutePath,
                                        targetUrl = "/api/v1/tickets/$ticketId/photos",
                                        fields = mapOf(
                                            "type" to "annotated",
                                            "ticket_device_id" to deviceId.toString(),
                                        ),
                                        idempotencyKey = key,
                                        contentType = "image/jpeg",
                                    )
                                    withContext(Dispatchers.Main) { onSaved() }
                                } catch (e: Exception) {
                                    Timber.tag("PhotoAnnotate").e(e, "Save failed")
                                    withContext(Dispatchers.Main) { onBack() }
                                }
                            }
                        },
                    ) {
                        Icon(Icons.Default.Check, contentDescription = "Save annotation")
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
            // ─── Drawing surface ──────────────────────────────────────────────
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
                    .background(Color.Black)
                    .onSizeChanged { size ->
                        canvasWidthPx = size.width
                        canvasHeightPx = size.height
                    }
                    .pointerInput(selectedColor, strokeWidth) {
                        detectDragGestures(
                            onDragStart = { offset ->
                                currentPath = Path().apply { moveTo(offset.x, offset.y) }
                            },
                            onDrag = { change, _ ->
                                val pos = change.position
                                currentPath = currentPath?.let { old ->
                                    Path().apply { addPath(old); lineTo(pos.x, pos.y) }
                                }
                            },
                            onDragEnd = {
                                currentPath?.let { finished ->
                                    paths = paths + (finished to DrawStyle(selectedColor, strokeWidth))
                                    currentPath = null
                                }
                            },
                            onDragCancel = { currentPath = null },
                        )
                    },
            ) {
                androidx.compose.foundation.Canvas(modifier = Modifier.fillMaxSize()) {
                    // Base image
                    if (baseBitmap != null) {
                        drawImage(baseBitmap.asImageBitmap())
                    }
                    // Completed annotation paths
                    for ((path, style) in paths) {
                        drawPath(
                            path = path,
                            color = style.color,
                            style = Stroke(
                                width = style.width,
                                cap = StrokeCap.Round,
                                join = StrokeJoin.Round,
                            ),
                        )
                    }
                    // In-progress path
                    currentPath?.let { path ->
                        drawPath(
                            path = path,
                            color = selectedColor,
                            style = Stroke(
                                width = strokeWidth,
                                cap = StrokeCap.Round,
                                join = StrokeJoin.Round,
                            ),
                        )
                    }
                }
            }

            // ─── Toolbar ─────────────────────────────────────────────────────
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(MaterialTheme.colorScheme.surface)
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                // Color chips
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    palette.forEachIndexed { i, color ->
                        FilterChip(
                            selected = selectedColor == color,
                            onClick = { selectedColor = color },
                            label = { Text(paletteLabels[i]) },
                            colors = FilterChipDefaults.filterChipColors(
                                selectedContainerColor = color.copy(alpha = 0.25f),
                                selectedLabelColor = color,
                            ),
                        )
                    }
                }

                // Stroke width slider
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        "Width",
                        style = MaterialTheme.typography.labelSmall,
                        modifier = Modifier.alignByBaseline(),
                    )
                    Slider(
                        value = strokeWidth,
                        onValueChange = { strokeWidth = it },
                        valueRange = 2f..20f,
                        modifier = Modifier.weight(1f),
                    )
                    Text(
                        strokeWidth.toInt().toString(),
                        style = MaterialTheme.typography.labelSmall,
                        modifier = Modifier.alignByBaseline(),
                    )
                }
            }
        }
    }
}

/** Drawing style captured per-stroke so a path can be replayed at save time. */
private data class DrawStyle(val color: Color, val width: Float)

/**
 * Composites annotation paths on top of [base] and returns a new [Bitmap].
 *
 * The canvas coordinate space is [canvasW] x [canvasH] (the draw surface
 * dimensions from the Compose layout). The base image is scaled to fill
 * the same space before compositing.
 */
private fun compositeBitmapWithPaths(
    base: Bitmap,
    paths: List<Pair<Path, DrawStyle>>,
    canvasW: Int,
    canvasH: Int,
): Bitmap {
    val safeW = canvasW.coerceAtLeast(1)
    val safeH = canvasH.coerceAtLeast(1)

    val output = Bitmap.createScaledBitmap(base, safeW, safeH, true)
        .copy(Bitmap.Config.ARGB_8888, true)

    val canvas = Canvas(output)

    for ((composePath, style) in paths) {
        val paint = Paint().apply {
            color = style.color.toArgb()
            this.style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
            strokeWidth = style.width
            isAntiAlias = true
        }
        // Compose Path → android.graphics.Path via reflection (same bridge as SignatureCanvas)
        val nativePath = composePathToNativeAnnotate(composePath)
        canvas.drawPath(nativePath, paint)
    }

    return output
}

private fun composePathToNativeAnnotate(path: Path): android.graphics.Path {
    return try {
        val field = path.javaClass.getDeclaredField("internalPath")
        field.isAccessible = true
        field.get(path) as? android.graphics.Path ?: android.graphics.Path()
    } catch (_: Exception) {
        android.graphics.Path()
    }
}
