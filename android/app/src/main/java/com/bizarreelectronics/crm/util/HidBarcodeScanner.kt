package com.bizarreelectronics.crm.util

import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEvent
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.key.utf16CodePoint
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * §17.10 — HID-mode barcode scanner support.
 *
 * HID-mode scanners (USB-C or Bluetooth keyboard profile) emit keystrokes
 * extremely fast — typically < 50 ms between characters — followed by an
 * Enter keypress.  This class sits in the Compose key-event pipeline via
 * [onPreviewKeyEvent] and distinguishes scanner bursts from real typing:
 *
 * Detection heuristic:
 *   - Intra-key gap < [HID_INTRA_KEY_THRESHOLD_MS] (50 ms) for all chars.
 *   - Sequence terminated by [Key.Enter] or [Key.NumPadEnter].
 *   - Minimum barcode length of [MIN_BARCODE_LENGTH] (4 chars) to reject noise.
 *
 * When a barcode is detected, the decoded string is emitted on [barcodeScanned].
 * The consuming ViewModel or composable subscribes to this SharedFlow and
 * routes the value to the active scan target (inventory lookup, POS search, etc.).
 *
 * Usage in a screen:
 * ```kotlin
 * val hidScanner: HidBarcodeScanner = hiltViewModel().hidBarcodeScanner
 * LaunchedEffect(Unit) {
 *     hidScanner.barcodeScanned.collect { barcode ->
 *         onBarcodeDetected(barcode)
 *     }
 * }
 * Box(
 *     modifier = Modifier.onPreviewKeyEvent { hidScanner.onKeyEvent(it) }
 * ) { ... }
 * ```
 *
 * mock-mode wiring: heuristic fires reliably in unit tests; physical-device
 * timing depends on scanner model. Needs physical-device test with a HID
 * scanner to confirm < 50 ms threshold fits real hardware.
 */
@Singleton
class HidBarcodeScanner @Inject constructor() {

    companion object {
        /** Maximum inter-keystroke gap to classify as a scanner burst (ms). */
        const val HID_INTRA_KEY_THRESHOLD_MS = 50L

        /** Minimum chars to accept as a valid barcode (avoids 1-char noise). */
        const val MIN_BARCODE_LENGTH = 4
    }

    private val buffer = StringBuilder()
    private var lastKeyTime = 0L

    private val _barcodeScanned = MutableSharedFlow<String>(extraBufferCapacity = 8)

    /** Emits decoded barcodes when a HID scanner burst is detected. */
    val barcodeScanned: SharedFlow<String> = _barcodeScanned.asSharedFlow()

    /**
     * Call this from `Modifier.onPreviewKeyEvent` on the root composable of any
     * screen that should receive HID scanner input.
     *
     * Returns `true` (event consumed) when the event is part of an active scanner
     * burst so the text field below does not receive the raw characters.
     * Returns `false` for regular keyboard typing (gap ≥ [HID_INTRA_KEY_THRESHOLD_MS]).
     */
    fun onKeyEvent(event: KeyEvent): Boolean {
        if (event.type != KeyEventType.KeyDown) return false

        val now = System.currentTimeMillis()
        val gap = now - lastKeyTime

        // Enter = terminator
        if (event.key == Key.Enter || event.key == Key.NumPadEnter) {
            val barcode = buffer.toString()
            buffer.clear()
            lastKeyTime = 0L
            if (barcode.length >= MIN_BARCODE_LENGTH) {
                _barcodeScanned.tryEmit(barcode)
                return true
            }
            return false
        }

        // Gap too large → not a scanner burst; clear buffer and let the keystroke through
        if (lastKeyTime != 0L && gap > HID_INTRA_KEY_THRESHOLD_MS) {
            buffer.clear()
        }

        lastKeyTime = now

        // Decode printable char from key event
        val cp = event.utf16CodePoint
        if (cp > 0 && cp < 0xFFFF) {
            buffer.append(cp.toChar())
            // While we're mid-burst, consume the event so focused text fields
            // don't receive raw chars that would pollute the active input.
            return buffer.length > 1
        }

        return false
    }

    /** Clears any in-progress buffer (e.g. on screen pause). */
    fun reset() {
        buffer.clear()
        lastKeyTime = 0L
    }
}
