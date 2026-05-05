package com.bizarreelectronics.crm.util

import android.view.MotionEvent

/**
 * StylusPressure — §22 L2255-L2256 / L2298-L2299 (plan:L2255, plan:L2256, plan:L2298)
 *
 * Helpers for stylus-specific MotionEvent handling:
 *   - Pressure-sensitive stroke width calculation
 *   - S Pen hardware button detection (primary + secondary stylus buttons)
 *   - Palm rejection tool-type filtering
 *
 * ## Pressure → stroke width
 * [strokeWidthFromPressure] maps a [MotionEvent.getPressure] value (0f..1f) to a
 * stroke-width Dp in the range 2..8 dp. Integrate via [StylusStrokePoint] which
 * bundles position + width for rendering.
 *
 * ## S Pen buttons (Samsung / stylus hardware buttons)
 * [StylusButtonCallback] receives callbacks for:
 * - Single tap of the primary stylus button → quick signature shortcut
 * - Double tap of the primary stylus button → undo last stroke
 * - Secondary stylus button → open context menu
 *
 * Wire [StylusButtonCallback] to [SignatureCanvas] via its `onStylusButton`
 * parameter (added in the pressure-sensitive edit). Call
 * [handleStylusButtonEvent] from `View.onGenericMotionEvent` or Compose
 * `pointerInteropFilter`.
 *
 * ## Palm rejection
 * [isPalmTouch] returns `true` for any touch that is NOT [MotionEvent.TOOL_TYPE_STYLUS]
 * when stylus mode is active. Use in [SignatureCanvas] to discard finger/palm
 * MotionEvents while a stylus is in range.
 *
 * ## Where to consume
 * - [SignatureCanvas] — primary consumer: pressure width + palm rejection + S Pen undo
 * - POS signature pad — same as above
 * - Note / sketch composables — pressure drawing if added in future
 */

// ── Stroke width ─────────────────────────────────────────────────────────────

private const val MIN_STROKE_DP = 2f
private const val MAX_STROKE_DP = 8f

/**
 * Map stylus [pressure] (0f..1f, clamped) to a stroke width in Dp units.
 *
 * Returns [MIN_STROKE_DP] for 0 pressure (hover) and [MAX_STROKE_DP] for
 * full pressure. The mapping is linear; non-linear curves can be applied
 * by the caller (e.g., square root for perceptual uniformity).
 */
fun strokeWidthFromPressure(pressure: Float): Float {
    val clamped = pressure.coerceIn(0f, 1f)
    return MIN_STROKE_DP + clamped * (MAX_STROKE_DP - MIN_STROKE_DP)
}

/**
 * A single captured stylus point with position and computed stroke width.
 *
 * @param x          Canvas X coordinate in pixels.
 * @param y          Canvas Y coordinate in pixels.
 * @param strokeWidthDp Stroke width in Dp derived from [strokeWidthFromPressure].
 */
data class StylusStrokePoint(
    val x: Float,
    val y: Float,
    val strokeWidthDp: Float,
)

/** Extract a [StylusStrokePoint] from a [MotionEvent] at pointer [pointerIndex]. */
fun MotionEvent.toStylusStrokePoint(pointerIndex: Int = 0): StylusStrokePoint =
    StylusStrokePoint(
        x = getX(pointerIndex),
        y = getY(pointerIndex),
        strokeWidthDp = strokeWidthFromPressure(getPressure(pointerIndex)),
    )

// ── Palm rejection ────────────────────────────────────────────────────────────

/**
 * Returns `true` if the touch tool type is NOT a stylus.
 *
 * When [stylusModeActive] is `true`, callers should discard the event to
 * reject palm / finger touches while the stylus is in range.
 *
 * Accepted tool types when stylus mode is active: only [MotionEvent.TOOL_TYPE_STYLUS].
 * Blocked tool types: [MotionEvent.TOOL_TYPE_FINGER], [MotionEvent.TOOL_TYPE_ERASER],
 * [MotionEvent.TOOL_TYPE_MOUSE] (mice don't draw signatures).
 *
 * @param stylusModeActive True when the stylus has been detected (e.g., ACTION_HOVER_ENTER
 *                         or first stylus ACTION_DOWN observed in the session).
 * @param pointerIndex     Pointer index to check within the event.
 */
fun MotionEvent.isPalmTouch(stylusModeActive: Boolean, pointerIndex: Int = 0): Boolean {
    if (!stylusModeActive) return false
    return getToolType(pointerIndex) != MotionEvent.TOOL_TYPE_STYLUS
}

// ── S Pen / stylus hardware button ───────────────────────────────────────────

/**
 * Callback interface for stylus hardware button gestures.
 *
 * Callers should hold a single instance and pass it to [handleStylusButtonEvent].
 *
 * @param onPrimaryTap        Primary button single tap — shortcut to open sig pad.
 * @param onPrimaryDoubleTap  Primary button double tap — undo last stroke.
 * @param onSecondaryPress    Secondary button press — open context menu at pointer.
 */
data class StylusButtonCallback(
    val onPrimaryTap: () -> Unit = {},
    val onPrimaryDoubleTap: () -> Unit = {},
    val onSecondaryPress: () -> Unit = {},
)

private const val DOUBLE_TAP_THRESHOLD_MS = 300L
private var lastPrimaryTapTime = 0L

/**
 * Process a [MotionEvent] for stylus hardware button presses.
 *
 * Call this from `View.onGenericMotionEvent` (for stylus hover events) or
 * from a Compose `pointerInteropFilter` modifier.
 *
 * Returns `true` if the event was consumed (button event handled).
 *
 * ### Samsung S Pen mapping
 * | Physical button     | MotionEvent button constant           |
 * |---------------------|---------------------------------------|
 * | Side button (press) | [MotionEvent.BUTTON_STYLUS_PRIMARY]   |
 * | Eraser button       | [MotionEvent.BUTTON_STYLUS_SECONDARY] |
 *
 * Note: S Pen double-tap on the button fires two [MotionEvent.ACTION_BUTTON_PRESS]
 * events in quick succession. We detect this via [DOUBLE_TAP_THRESHOLD_MS].
 */
fun handleStylusButtonEvent(
    event: MotionEvent,
    callback: StylusButtonCallback,
): Boolean {
    if (event.getToolType(0) != MotionEvent.TOOL_TYPE_STYLUS) return false

    return when (event.action) {
        MotionEvent.ACTION_BUTTON_PRESS -> {
            when (event.buttonState) {
                MotionEvent.BUTTON_STYLUS_PRIMARY -> {
                    val now = System.currentTimeMillis()
                    val isDouble = (now - lastPrimaryTapTime) < DOUBLE_TAP_THRESHOLD_MS
                    lastPrimaryTapTime = now
                    if (isDouble) {
                        callback.onPrimaryDoubleTap()
                    } else {
                        callback.onPrimaryTap()
                    }
                    true
                }
                MotionEvent.BUTTON_STYLUS_SECONDARY -> {
                    callback.onSecondaryPress()
                    true
                }
                else -> false
            }
        }
        else -> false
    }
}
