package com.bizarreelectronics.crm.ui.screens.hardware

import android.graphics.Bitmap
import android.view.MotionEvent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Undo
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.input.pointer.pointerInteropFilter
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.core.graphics.createBitmap
import com.bizarreelectronics.crm.util.StylusButtonCallback
import com.bizarreelectronics.crm.util.handleStylusButtonEvent
import com.bizarreelectronics.crm.util.isPalmTouch
import com.bizarreelectronics.crm.util.strokeWidthFromPressure

/**
 * §17.9 — Pressure-sensitive signature canvas.
 *
 * Features:
 *   - Compose [Canvas] with pressure-sensitive stroke width via
 *     [MotionEvent.getPressure] → [strokeWidthFromPressure].
 *   - Palm rejection: finger/eraser events are discarded when stylus is detected.
 *   - S Pen / USI button support via [handleStylusButtonEvent]:
 *       - Primary button single tap → no-op (caller may use for context menu).
 *       - Primary button double tap → undo last stroke.
 *       - Secondary button → no-op (reserved).
 *   - Undo stack: [undo] removes the most recent stroke path.
 *   - [toBitmap] renders all strokes into a [Bitmap] for upload / PDF embed.
 *   - [clear] resets all strokes.
 *
 * Usage:
 * ```kotlin
 * var signatureBitmap by remember { mutableStateOf<Bitmap?>(null) }
 * SignatureCanvas(
 *     modifier = Modifier.fillMaxWidth().height(200.dp),
 *     onSignatureChanged = { hasContent -> /* enable/disable Save button */ },
 * )
 * ```
 *
 * mock-mode wiring: pressure and S Pen work on any pressure-capable digitiser.
 * On a non-stylus touch screen the fallback pressure value (1.0f) produces a
 * uniform 8 dp stroke.  Needs physical stylus test for variable-width stroke.
 */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun SignatureCanvas(
    modifier: Modifier = Modifier,
    strokeColor: Color = Color.Black,
    backgroundColor: Color = Color.White,
    onSignatureChanged: (hasContent: Boolean) -> Unit = {},
    canvasRef: SignatureCanvasController? = null,
) {
    // Each "stroke" is a list of (Offset, strokeWidthDp) pairs
    val strokes = remember { mutableStateListOf<List<StrokeSegment>>() }
    var currentStroke = remember { mutableListOf<StrokeSegment>() }
    var stylusSeen by remember { mutableStateOf(false) }

    // Expose control to caller via optional controller
    canvasRef?.let { ctrl ->
        ctrl.undoFn = {
            if (strokes.isNotEmpty()) {
                strokes.removeAt(strokes.lastIndex)
                onSignatureChanged(strokes.isNotEmpty())
            }
        }
        ctrl.clearFn = {
            strokes.clear()
            currentStroke.clear()
            onSignatureChanged(false)
        }
        ctrl.toBitmapFn = { width, height ->
            renderToBitmap(strokes, strokeColor, width, height)
        }
    }

    val stylusButtonCallback = StylusButtonCallback(
        onPrimaryDoubleTap = {
            if (strokes.isNotEmpty()) {
                strokes.removeAt(strokes.lastIndex)
                onSignatureChanged(strokes.isNotEmpty())
            }
        },
    )

    Column(modifier = modifier) {
        Canvas(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .background(backgroundColor)
                .border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.4f))
                .pointerInteropFilter { event ->
                    // Handle S Pen / stylus hardware buttons (generic motion)
                    if (handleStylusButtonEvent(event, stylusButtonCallback)) return@pointerInteropFilter true

                    // Track stylus presence for palm rejection
                    if (event.getToolType(0) == MotionEvent.TOOL_TYPE_STYLUS) {
                        stylusSeen = true
                    }

                    // Palm rejection: reject non-stylus events when stylus is in range
                    if (event.isPalmTouch(stylusSeen)) return@pointerInteropFilter true

                    when (event.actionMasked) {
                        MotionEvent.ACTION_DOWN -> {
                            currentStroke = mutableListOf()
                            val p = event.pressure.coerceIn(0f, 1f)
                            currentStroke.add(
                                StrokeSegment(
                                    offset = Offset(event.x, event.y),
                                    strokeWidthPx = strokeWidthFromPressure(p).dp.value,
                                )
                            )
                            true
                        }
                        MotionEvent.ACTION_MOVE -> {
                            // Process all historical points for smooth curves
                            for (i in 0 until event.historySize) {
                                val hp = event.getHistoricalPressure(i).coerceIn(0f, 1f)
                                currentStroke.add(
                                    StrokeSegment(
                                        offset = Offset(event.getHistoricalX(i), event.getHistoricalY(i)),
                                        strokeWidthPx = strokeWidthFromPressure(hp).dp.value,
                                    )
                                )
                            }
                            val p = event.pressure.coerceIn(0f, 1f)
                            currentStroke.add(
                                StrokeSegment(
                                    offset = Offset(event.x, event.y),
                                    strokeWidthPx = strokeWidthFromPressure(p).dp.value,
                                )
                            )
                            true
                        }
                        MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                            if (currentStroke.isNotEmpty()) {
                                strokes.add(currentStroke.toList())
                                currentStroke = mutableListOf()
                                onSignatureChanged(true)
                                // Reset palm-rejection on lift; stylus hover will re-trigger
                                if (event.getToolType(0) != MotionEvent.TOOL_TYPE_STYLUS) {
                                    stylusSeen = false
                                }
                            }
                            true
                        }
                        else -> false
                    }
                }
        ) {
            // Draw completed strokes
            for (stroke in strokes) {
                drawPressureStroke(stroke, strokeColor)
            }
            // Draw in-progress stroke
            if (currentStroke.isNotEmpty()) {
                drawPressureStroke(currentStroke, strokeColor)
            }
        }
    }
}

// ── Stroke rendering ──────────────────────────────────────────────────────────

private data class StrokeSegment(val offset: Offset, val strokeWidthPx: Float)

private fun androidx.compose.ui.graphics.drawscope.DrawScope.drawPressureStroke(
    segments: List<StrokeSegment>,
    color: Color,
) {
    if (segments.size < 2) {
        // Single point — draw a dot
        segments.firstOrNull()?.let { s ->
            drawCircle(color = color, radius = s.strokeWidthPx / 2f, center = s.offset)
        }
        return
    }
    // Draw each segment as a line with the pressure-derived width at that point.
    // For maximum smoothness we draw overlapping short lines; a true variable-width
    // Bezier would require a custom path + shader (future enhancement).
    for (i in 1 until segments.size) {
        val prev = segments[i - 1]
        val curr = segments[i]
        val avgWidth = (prev.strokeWidthPx + curr.strokeWidthPx) / 2f
        drawLine(
            color = color,
            start = prev.offset,
            end = curr.offset,
            strokeWidth = avgWidth,
            cap = StrokeCap.Round,
        )
    }
}

// ── Bitmap export ─────────────────────────────────────────────────────────────

private fun renderToBitmap(
    strokes: List<List<StrokeSegment>>,
    strokeColor: Color,
    widthPx: Int,
    heightPx: Int,
): Bitmap {
    val bitmap = createBitmap(widthPx, heightPx)
    val canvas = android.graphics.Canvas(bitmap)
    canvas.drawColor(android.graphics.Color.WHITE)
    val paint = android.graphics.Paint().apply {
        color = android.graphics.Color.BLACK
        isAntiAlias = true
        strokeCap = android.graphics.Paint.Cap.ROUND
        strokeJoin = android.graphics.Paint.Join.ROUND
        style = android.graphics.Paint.Style.STROKE
    }
    for (stroke in strokes) {
        for (i in 1 until stroke.size) {
            val prev = stroke[i - 1]
            val curr = stroke[i]
            paint.strokeWidth = (prev.strokeWidthPx + curr.strokeWidthPx) / 2f
            canvas.drawLine(prev.offset.x, prev.offset.y, curr.offset.x, curr.offset.y, paint)
        }
    }
    return bitmap
}

// ── Controller ────────────────────────────────────────────────────────────────

/**
 * Caller-held controller for [SignatureCanvas].  Pass an instance to
 * [SignatureCanvas] and call [undo], [clear], or [toBitmap] from buttons
 * outside the canvas composable.
 */
class SignatureCanvasController {
    internal var undoFn: (() -> Unit)? = null
    internal var clearFn: (() -> Unit)? = null
    internal var toBitmapFn: ((width: Int, height: Int) -> Bitmap)? = null

    fun undo() { undoFn?.invoke() }
    fun clear() { clearFn?.invoke() }
    fun toBitmap(width: Int = 800, height: Int = 300): Bitmap? = toBitmapFn?.invoke(width, height)
}

// ── Convenience wrapper with undo + clear buttons ─────────────────────────────

/**
 * Wraps [SignatureCanvas] with Undo and Clear action buttons below the pad.
 * Suitable as a drop-in for waiver screens, POS signature capture, etc.
 */
@Composable
fun SignaturePad(
    modifier: Modifier = Modifier,
    height: Dp = 200.dp,
    controller: SignatureCanvasController = remember { SignatureCanvasController() },
    onSignatureChanged: (hasContent: Boolean) -> Unit = {},
) {
    Column(modifier = modifier) {
        SignatureCanvas(
            modifier = Modifier
                .fillMaxWidth()
                .height(height),
            onSignatureChanged = onSignatureChanged,
            canvasRef = controller,
        )
        Spacer(Modifier.height(4.dp))
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextButton(onClick = { controller.undo() }) {
                Icon(
                    Icons.Default.Undo,
                    contentDescription = "Undo last stroke",
                    modifier = Modifier.size(16.dp),
                )
                Spacer(Modifier.width(4.dp))
                Text("Undo")
            }
            TextButton(onClick = { controller.clear() }) {
                Text("Clear", color = MaterialTheme.colorScheme.error)
            }
        }
    }
}
