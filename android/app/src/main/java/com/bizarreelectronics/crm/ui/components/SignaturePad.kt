package com.bizarreelectronics.crm.ui.components

import android.graphics.Bitmap
import android.graphics.Paint as AndroidPaint
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.R
import kotlin.math.hypot

// ---------------------------------------------------------------------------
// Data model — immutable value types
// ---------------------------------------------------------------------------

/**
 * A single (x, y) sample captured during a pointer drag gesture.
 * Coordinates are in the local Canvas pixel space.
 */
data class SignaturePoint(val x: Float, val y: Float)

/**
 * One continuous stroke: the sequence of [SignaturePoint]s collected from a
 * single pointer-down → drag → pointer-up gesture.
 */
data class SignatureStroke(val points: List<SignaturePoint>)

// ---------------------------------------------------------------------------
// Minimum path threshold used by [isSignatureValid] and kept visible for
// callers that want to apply a different threshold.
// ---------------------------------------------------------------------------
private const val DEFAULT_MIN_PATH_PX = 50f

// Ink style constants
private val INK_STROKE_WIDTH_DP = 3.5.dp

// ---------------------------------------------------------------------------
// Composable
// ---------------------------------------------------------------------------

/**
 * Freeform signature pad rendered on a [Canvas].
 *
 * The user drags to draw a signature expressed as a [List] of [SignatureStroke]s.
 * Caller owns the state; this composable is purely controlled:
 *
 * ```kotlin
 * var strokes by remember { mutableStateOf(emptyList<SignatureStroke>()) }
 * SignaturePad(strokes = strokes, onStrokesChanged = { strokes = it })
 * ```
 *
 * To export the signature call [renderSignatureBitmap] and encode to PNG.
 *
 * ## Accessibility
 * The canvas carries a semantic content description explaining its purpose.
 * Clear and Undo buttons each have descriptive [contentDescription]s.
 *
 * This composable is **not keyboard-accessible** — signature capture is
 * inherently a stylus/finger interaction. Screen-reader users should be
 * informed via the content description that a physical gesture is required.
 *
 * ## Sizing
 * Fixed height of 200 dp; fills maximum available width.
 *
 * ## Visual affordance
 * Rendered on `surfaceVariant` background with an `outline`-coloured border;
 * a centred placeholder text appears when no strokes have been drawn.
 */
@Composable
fun SignaturePad(
    strokes: List<SignatureStroke>,
    onStrokesChanged: (List<SignatureStroke>) -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String = "Sign here",
) {
    // Accumulate the points of the stroke currently being drawn.  We keep
    // this in local remembered state rather than passing it up to avoid
    // triggering a recomposition mid-stroke on every pointer sample.
    var currentStrokePoints by remember { mutableStateOf<List<SignaturePoint>>(emptyList()) }
    val context = LocalContext.current

    val outlineColor = MaterialTheme.colorScheme.outline
    val inkColor = MaterialTheme.colorScheme.onSurface
    val placeholderColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
    val surfaceVariantColor = MaterialTheme.colorScheme.surfaceVariant
    val strokeWidthPx = INK_STROKE_WIDTH_DP

    Column(modifier = modifier) {
        // ---- Canvas --------------------------------------------------------
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(200.dp)
                .border(1.dp, outlineColor, MaterialTheme.shapes.small),
            contentAlignment = Alignment.Center,
        ) {
            Canvas(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(200.dp)
                    .semantics {
                        // §26 — use a11y_* string resource; never raw literals on TalkBack-facing surfaces
                        contentDescription = context.getString(R.string.a11y_signature_pad)
                    }
                    .pointerInput(Unit) {
                        awaitPointerEventScope {
                            while (true) {
                                val event = awaitPointerEvent()
                                when (event.type) {
                                    PointerEventType.Press -> {
                                        val pos = event.changes.firstOrNull()?.position
                                            ?: continue
                                        currentStrokePoints =
                                            listOf(SignaturePoint(pos.x, pos.y))
                                    }
                                    PointerEventType.Move -> {
                                        val pos = event.changes.firstOrNull()?.position
                                            ?: continue
                                        currentStrokePoints =
                                            currentStrokePoints +
                                            SignaturePoint(pos.x, pos.y)
                                    }
                                    PointerEventType.Release -> {
                                        val pos = event.changes.firstOrNull()?.position
                                        val finalPoints = if (pos != null) {
                                            currentStrokePoints +
                                                SignaturePoint(pos.x, pos.y)
                                        } else {
                                            currentStrokePoints
                                        }
                                        if (finalPoints.isNotEmpty()) {
                                            onStrokesChanged(
                                                strokes + SignatureStroke(finalPoints),
                                            )
                                        }
                                        currentStrokePoints = emptyList()
                                    }
                                    else -> Unit
                                }
                            }
                        }
                    },
            ) {
                // Background fill
                drawRect(color = surfaceVariantColor)

                val strokeStyle = Stroke(width = strokeWidthPx.toPx())

                // Draw committed strokes
                for (stroke in strokes) {
                    if (stroke.points.isEmpty()) continue
                    val path = strokeToPath(stroke)
                    drawPath(path, color = inkColor, style = strokeStyle)
                }

                // Draw the in-progress stroke (not yet committed)
                if (currentStrokePoints.isNotEmpty()) {
                    val path = pointsToPath(currentStrokePoints)
                    drawPath(path, color = inkColor, style = strokeStyle)
                }

                // Placeholder
                if (strokes.isEmpty() && currentStrokePoints.isEmpty()) {
                    drawContext.canvas.nativeCanvas.drawText(
                        placeholder,
                        size.width / 2f,
                        size.height / 2f + PLACEHOLDER_TEXT_SIZE_PX / 3f,
                        placeholderPaint(placeholderColor),
                    )
                }
            }
        }

        // ---- Undo / Clear row ----------------------------------------------
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End),
        ) {
            OutlinedButton(
                onClick = {
                    if (strokes.isNotEmpty()) {
                        onStrokesChanged(strokes.dropLast(1))
                    }
                },
                enabled = strokes.isNotEmpty(),
                modifier = Modifier.semantics {
                    contentDescription = context.getString(R.string.a11y_signature_undo)
                },
            ) {
                Text("Undo")
            }

            OutlinedButton(
                onClick = { onStrokesChanged(emptyList()) },
                enabled = strokes.isNotEmpty(),
                modifier = Modifier.semantics {
                    contentDescription = context.getString(R.string.a11y_signature_clear)
                },
            ) {
                Text("Clear")
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Pure helpers — no Compose state, no Android framework (except Bitmap export)
// ---------------------------------------------------------------------------

/**
 * Render [strokes] into a white-background [Bitmap] of [widthPx] × [heightPx].
 *
 * The resulting bitmap can be compressed to PNG by the caller:
 * ```kotlin
 * val bmp = renderSignatureBitmap(strokes, 800, 400)
 * bmp.compress(Bitmap.CompressFormat.PNG, 100, outputStream)
 * ```
 *
 * This function requires the Android runtime (`android.graphics`) and therefore
 * cannot be tested in pure JVM unit tests.  Exclude it from coverage accordingly.
 */
fun renderSignatureBitmap(
    strokes: List<SignatureStroke>,
    widthPx: Int,
    heightPx: Int,
): Bitmap {
    val bmp = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
    val canvas = android.graphics.Canvas(bmp)
    canvas.drawColor(android.graphics.Color.WHITE)

    if (strokes.isEmpty()) return bmp

    val paint = AndroidPaint().apply {
        color = android.graphics.Color.BLACK
        strokeWidth = 6f
        style = AndroidPaint.Style.STROKE
        strokeCap = AndroidPaint.Cap.ROUND
        strokeJoin = AndroidPaint.Join.ROUND
        isAntiAlias = true
    }

    for (stroke in strokes) {
        if (stroke.points.isEmpty()) continue
        val path = android.graphics.Path()
        val first = stroke.points.first()
        path.moveTo(first.x, first.y)
        for (point in stroke.points.drop(1)) {
            path.lineTo(point.x, point.y)
        }
        canvas.drawPath(path, paint)
    }

    return bmp
}

/**
 * Determine whether a set of [strokes] constitutes a valid (non-trivial)
 * signature.
 *
 * A signature is considered valid when **at least one** of these conditions
 * holds:
 * - There is at least one stroke with ≥ 3 points, **or**
 * - The aggregate Euclidean path length across all strokes exceeds
 *   [minTotalPathPx].
 *
 * This is intentionally permissive — a strict minimum will reject quick
 * initials; a zero minimum allows accidental taps to pass.
 *
 * This function is `internal` so it can be accessed directly from the
 * unit-test class in the same module without reflective tricks.
 */
internal fun isSignatureValid(
    strokes: List<SignatureStroke>,
    minTotalPathPx: Float = DEFAULT_MIN_PATH_PX,
): Boolean {
    if (strokes.isEmpty()) return false

    // Condition 1: at least one stroke with 3+ points
    val hasLongStroke = strokes.any { it.points.size >= 3 }
    if (hasLongStroke) return true

    // Condition 2: aggregate path length exceeds the minimum
    var totalLength = 0f
    for (stroke in strokes) {
        val pts = stroke.points
        for (i in 1 until pts.size) {
            val dx = pts[i].x - pts[i - 1].x
            val dy = pts[i].y - pts[i - 1].y
            totalLength += hypot(dx, dy)
        }
    }
    return totalLength > minTotalPathPx
}

// ---------------------------------------------------------------------------
// Private drawing helpers
// ---------------------------------------------------------------------------

private fun strokeToPath(stroke: SignatureStroke): Path = pointsToPath(stroke.points)

private fun pointsToPath(points: List<SignaturePoint>): Path {
    val path = Path()
    if (points.isEmpty()) return path
    val first = points.first()
    path.moveTo(first.x, first.y)
    for (point in points.drop(1)) {
        path.lineTo(point.x, point.y)
    }
    return path
}

// Approximate text size for placeholder, matching body-large (~16sp → ~43px at 2.75 density)
private const val PLACEHOLDER_TEXT_SIZE_PX = 44f

private fun placeholderPaint(color: Color): AndroidPaint = AndroidPaint().apply {
    textSize = PLACEHOLDER_TEXT_SIZE_PX
    textAlign = AndroidPaint.Align.CENTER
    this.color = android.graphics.Color.argb(
        (color.alpha * 255).toInt(),
        (color.red * 255).toInt(),
        (color.green * 255).toInt(),
        (color.blue * 255).toInt(),
    )
    isAntiAlias = true
}
