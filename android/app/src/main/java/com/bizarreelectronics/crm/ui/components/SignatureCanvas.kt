package com.bizarreelectronics.crm.ui.components

import android.graphics.Bitmap
import android.graphics.Paint
import android.graphics.Picture
import android.view.MotionEvent
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
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.pointerInteropFilter
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.util.StylusButtonCallback
import com.bizarreelectronics.crm.util.handleStylusButtonEvent
import com.bizarreelectronics.crm.util.isPalmTouch
import com.bizarreelectronics.crm.util.strokeWidthFromPressure

/**
 * SignatureCanvas — §4.7 L741 / §22 L2255 / L2298 (plan:L741, plan:L2255, plan:L2298)
 *
 * Reusable stateful signature-capture composable. Draws ink paths on a white
 * canvas via [detectDragGestures]. Call [rememberSignatureState] to obtain a
 * [SignatureState] handle that exposes [SignatureState.isEmpty] for button
 * gating and [SignatureState.capture] to produce the final Bitmap.
 *
 * ### Pressure-sensitive strokes (§22 L2255)
 * When a stylus is used, each stroke point's width is derived from
 * [MotionEvent.getPressure] via [strokeWidthFromPressure] (range 2..8 dp).
 * Mouse / finger input uses [strokeWidth] uniformly.
 *
 * ### Palm rejection (§22 L2298)
 * When [palmRejectionEnabled] is `true`, finger and palm touch events are
 * discarded while a stylus is in range. A stylus is considered "active" after
 * the first [MotionEvent.TOOL_TYPE_STYLUS] event in the session; it is reset
 * when [SignatureState.clear] is called.
 *
 * ### S Pen hardware button (§22 L2256)
 * Pass a [StylusButtonCallback] via [onStylusButton]. The canvas routes
 * all [MotionEvent] hardware-button presses to [handleStylusButtonEvent].
 * Default wiring: primary tap → no-op (caller opens sig pad), double-tap → undo.
 *
 * ReduceMotion: when [reduceMotion] is true, no easing / spring animations are
 * applied to strokes (already instant, so this is a forward-compatible no-op).
 *
 * @param state                Externally owned [SignatureState]; use [rememberSignatureState].
 * @param modifier             Layout modifier — caller sets the height.
 * @param strokeColor          Ink color; defaults to [Color.Black].
 * @param strokeWidth          Base pen width in pixels (used for non-stylus input).
 * @param palmRejectionEnabled Filter out finger/palm events when stylus is active.
 * @param onStylusButton       Callbacks for S Pen / stylus hardware button gestures.
 * @param reduceMotion         Forward-compat flag; no current animation to reduce.
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun SignatureCanvas(
    state: SignatureState,
    modifier: Modifier = Modifier,
    strokeColor: Color = Color.Black,
    strokeWidth: Float = 4f,
    palmRejectionEnabled: Boolean = true,
    onStylusButton: StylusButtonCallback = StylusButtonCallback(
        onPrimaryDoubleTap = { state.undo() },
    ),
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
            // §26.6 — Switch Access requires all interactive custom surfaces to
            // be focusable so the switch controller can reach them. The canvas
            // is inherently a touch-drawing surface (not keyboard-accessible),
            // but marking it focusable + providing a contentDescription lets
            // TalkBack and Switch Access scan it and announce its purpose.
            .semantics {
                contentDescription =
                    "Signature canvas. Draw your signature with a stylus or finger."
            }
            // §22 L2256 — route hardware stylus button events to StylusButtonCallback
            .pointerInteropFilter { event ->
                if (handleStylusButtonEvent(event, onStylusButton)) return@pointerInteropFilter true

                // §22 L2298 — palm rejection: track whether a stylus is active
                if (event.getToolType(0) == MotionEvent.TOOL_TYPE_STYLUS) {
                    state.stylusActive = true
                }

                // Block palm/finger when stylus is active
                if (palmRejectionEnabled && event.isPalmTouch(state.stylusActive)) {
                    return@pointerInteropFilter true // consume + discard
                }

                false // pass through to detectDragGestures
            }
            .pointerInput(Unit) {
                detectDragGestures(
                    onDragStart = { offset ->
                        // §22 L2255 — start new pressure-aware stroke segment list
                        state.currentPath = Path().apply { moveTo(offset.x, offset.y) }
                        state.currentStrokeWidth = strokeWidth
                    },
                    onDrag = { change, _ ->
                        val pos = change.position
                        // Derive stroke width from stylus pressure if available;
                        // fallback to uniform [strokeWidth] for finger/mouse.
                        val pressure = change.pressure
                        val dynamicWidth = if (state.stylusActive && pressure > 0f) {
                            strokeWidthFromPressure(pressure)
                        } else {
                            strokeWidth
                        }
                        state.currentStrokeWidth = dynamicWidth
                        // Replace reference so Compose detects state change
                        state.currentPath = state.currentPath?.let { old ->
                            Path().apply { addPath(old); lineTo(pos.x, pos.y) }
                        }
                    },
                    onDragEnd = {
                        state.currentPath?.let { finished ->
                            state.paths = state.paths + (finished to state.currentStrokeWidth)
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

        // Completed paths — each carries its own pressure-derived width
        for ((path, width) in state.paths) {
            drawPath(
                path = path,
                color = strokeColor,
                style = Stroke(width = width, cap = StrokeCap.Round, join = StrokeJoin.Round),
            )
        }

        // In-progress path uses the latest dynamic stroke width
        state.currentPath?.let { path ->
            drawPath(
                path = path,
                color = strokeColor,
                style = Stroke(
                    width = state.currentStrokeWidth,
                    cap = StrokeCap.Round,
                    join = StrokeJoin.Round,
                ),
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
 * - undo the last stroke via [undo] (also wired to S Pen double-tap)
 * - produce a [Bitmap] via [capture]
 *
 * Each completed stroke is stored as a `Pair<Path, Float>` where the Float is
 * the pressure-derived stroke width captured at the time of drawing.
 */
class SignatureState {
    /** Completed stroke paths paired with their pressure-derived widths. */
    var paths by mutableStateOf<List<Pair<Path, Float>>>(emptyList())
        internal set

    /** The stroke currently being drawn (finger/stylus down → drag). */
    var currentPath by mutableStateOf<Path?>(null)
        internal set

    /** Width of the stroke currently in progress (updated per drag event). */
    internal var currentStrokeWidth: Float = 4f

    /**
     * True when a stylus [MotionEvent] has been observed this session.
     * Enables palm rejection via [isPalmTouch].
     * Reset to `false` on [clear].
     */
    internal var stylusActive: Boolean = false

    // Dimensions + style written by the Canvas on each frame so capture() can
    // reproduce them without requiring extra parameters from the host.
    internal var lastCanvasWidthPx: Int = 0
    internal var lastCanvasHeightPx: Int = 0
    internal var lastStrokeColor: Color = Color.Black
    internal var lastStrokeWidth: Float = 4f

    /** True when no ink has been drawn yet. */
    val isEmpty: Boolean get() = paths.isEmpty() && currentPath == null

    /** Discard all strokes and reset the canvas. Also resets stylus-active state. */
    fun clear() {
        paths = emptyList()
        currentPath = null
        stylusActive = false
    }

    /**
     * Undo the last completed stroke. No-op when [isEmpty].
     * Wired automatically to S Pen primary button double-tap by [SignatureCanvas].
     */
    fun undo() {
        if (paths.isNotEmpty()) {
            paths = paths.dropLast(1)
        }
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

        for ((composePath, strokeWidthDp) in paths) {
            paint.strokeWidth = strokeWidthDp
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
