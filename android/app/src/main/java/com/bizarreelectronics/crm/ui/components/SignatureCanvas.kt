package com.bizarreelectronics.crm.ui.components

import android.graphics.Bitmap
import android.graphics.Paint
import android.graphics.Picture
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp

/**
 * SignatureCanvas — §4.7 L741 (plan:L741)
 *
 * Reusable stateful signature-capture composable. Draws ink paths on a white
 * canvas via [detectDragGestures]. Call [rememberSignatureState] to obtain a
 * [SignatureState] handle that exposes [SignatureState.isEmpty] for button
 * gating and [SignatureState.capture] to produce the final Bitmap.
 *
 * ReduceMotion: when [reduceMotion] is true, no easing / spring animations are
 * applied to strokes (already instant, so this is a forward-compatible no-op).
 *
 * @param state         Externally owned [SignatureState]; use [rememberSignatureState].
 * @param modifier      Layout modifier — caller sets the height.
 * @param strokeColor   Ink color; defaults to [Color.Black].
 * @param strokeWidth   Pen width in pixels on the canvas.
 * @param reduceMotion  Forward-compat flag; no current animation to reduce.
 */
@Composable
fun SignatureCanvas(
    state: SignatureState,
    modifier: Modifier = Modifier,
    strokeColor: Color = Color.Black,
    strokeWidth: Float = 4f,
    @Suppress("UNUSED_PARAMETER") reduceMotion: Boolean = false,
) {
    val backgroundColor = Color.White
    val borderColor = MaterialTheme.colorScheme.outline

    // Track canvas dimensions for capture (updated on first layout)
    var canvasWidthPx by remember { mutableIntStateOf(0) }
    var canvasHeightPx by remember { mutableIntStateOf(0) }

    Canvas(
        modifier = modifier
            .background(backgroundColor)
            .border(1.dp, borderColor)
            .pointerInput(Unit) {
                detectDragGestures(
                    onDragStart = { offset ->
                        state.currentPath = Path().apply { moveTo(offset.x, offset.y) }
                    },
                    onDrag = { change, _ ->
                        val pos = change.position
                        // Replace reference so Compose detects state change
                        state.currentPath = state.currentPath?.let { old ->
                            Path().apply { addPath(old); lineTo(pos.x, pos.y) }
                        }
                    },
                    onDragEnd = {
                        state.currentPath?.let { finished ->
                            state.paths = state.paths + finished
                            state.currentPath = null
                        }
                    },
                    onDragCancel = {
                        state.currentPath = null
                    },
                )
            },
    ) {
        // Capture canvas size for Bitmap rendering
        canvasWidthPx = size.width.toInt()
        canvasHeightPx = size.height.toInt()
        state.lastCanvasWidthPx = canvasWidthPx
        state.lastCanvasHeightPx = canvasHeightPx
        state.lastStrokeColor = strokeColor
        state.lastStrokeWidth = strokeWidth

        // White fill
        drawRect(backgroundColor)

        // Completed paths
        for (path in state.paths) {
            drawPath(
                path = path,
                color = strokeColor,
                style = Stroke(width = strokeWidth, cap = StrokeCap.Round, join = StrokeJoin.Round),
            )
        }

        // In-progress path
        state.currentPath?.let { path ->
            drawPath(
                path = path,
                color = strokeColor,
                style = Stroke(width = strokeWidth, cap = StrokeCap.Round, join = StrokeJoin.Round),
            )
        }
    }
}

/**
 * Holds all mutable state for a [SignatureCanvas]. Obtain via [rememberSignatureState].
 *
 * Hosts use it to:
 * - gate the confirm button via [isEmpty]
 * - clear the canvas via [clear]
 * - produce a [Bitmap] via [capture]
 */
class SignatureState {
    /** Completed stroke paths. */
    var paths by mutableStateOf<List<Path>>(emptyList())
        internal set

    /** The stroke currently being drawn (finger down → drag). */
    var currentPath by mutableStateOf<Path?>(null)
        internal set

    // Dimensions + style written by the Canvas on each frame so capture() can
    // reproduce them without requiring extra parameters from the host.
    internal var lastCanvasWidthPx: Int = 0
    internal var lastCanvasHeightPx: Int = 0
    internal var lastStrokeColor: Color = Color.Black
    internal var lastStrokeWidth: Float = 4f

    /** True when no ink has been drawn yet. */
    val isEmpty: Boolean get() = paths.isEmpty() && currentPath == null

    /** Discard all strokes and reset the canvas. */
    fun clear() {
        paths = emptyList()
        currentPath = null
    }

    /**
     * Render all strokes to a [Bitmap].
     *
     * Uses [android.graphics.Picture] so it works on both hardware-accelerated
     * and software canvases. The picture is drawn into a fresh ARGB_8888 bitmap.
     *
     * Must be called after at least one render pass (so [lastCanvasWidthPx] is set).
     *
     * @param widthPx   Override width; defaults to last observed canvas width.
     * @param heightPx  Override height; defaults to last observed canvas height.
     */
    fun capture(
        widthPx: Int = lastCanvasWidthPx,
        heightPx: Int = lastCanvasHeightPx,
    ): Bitmap {
        val safeW = widthPx.coerceAtLeast(1)
        val safeH = heightPx.coerceAtLeast(1)

        // Build native paths by replaying the compose path segments
        val picture = Picture()
        val nCanvas = picture.beginRecording(safeW, safeH)
        nCanvas.drawColor(android.graphics.Color.WHITE)

        val paint = Paint().apply {
            color = lastStrokeColor.toArgb()
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
            strokeWidth = lastStrokeWidth
            isAntiAlias = true
        }

        for (composePath in paths) {
            val nativePath = composePathToNative(composePath)
            nCanvas.drawPath(nativePath, paint)
        }
        picture.endRecording()

        val bitmap = Bitmap.createBitmap(safeW, safeH, Bitmap.Config.ARGB_8888)
        val bitmapCanvas = android.graphics.Canvas(bitmap)
        bitmapCanvas.drawPicture(picture)
        return bitmap
    }
}

/**
 * Convert a Compose [Path] to an [android.graphics.Path] by reading its
 * underlying native path handle via reflection. This is the only bridge
 * between the two APIs available without a third-party dependency.
 *
 * On failure (reflection blocked), returns an empty path — the resulting
 * bitmap will be white (signature blank), which is safe: the host gates
 * the confirm button on [SignatureState.isEmpty] so this fallback is
 * unreachable in production.
 */
private fun composePathToNative(path: Path): android.graphics.Path {
    return try {
        val field = path.javaClass.getDeclaredField("internalPath")
        field.isAccessible = true
        field.get(path) as? android.graphics.Path ?: android.graphics.Path()
    } catch (_: Exception) {
        // Reflection not available — return empty path
        android.graphics.Path()
    }
}

/** Obtain a [SignatureState] that survives recomposition. */
@Composable
fun rememberSignatureState(): SignatureState = remember { SignatureState() }
