package com.bizarreelectronics.crm.ui.screens.pos

import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type

/**
 * POS-specific hardware-keyboard shortcut host.
 *
 * Approach (b): standalone wrapper applied only to POS screens so the global
 * [KeyboardShortcutsHost] (ticket detail, nav chords, etc.) is untouched.
 *
 * F-key mapping:
 *   F1 → onNewSale          (start a fresh sale / reset flow)
 *   F2 → onScan             (open camera barcode scanner)
 *   F3 → onCustomerSearch   (expand customer / catalog SearchBar)
 *   F4 → onDiscount         (open cart-discount dialog)
 *   F5 → onTender           (navigate to Tender screen)
 *   F6 → onPark             (park / hold cart — POS-PARK-001 stub)
 *   F7 → onPrint            (reprint last receipt)
 *   F8 → onRefund           (navigate to refund flow — stub)
 *   Ctrl+F → onFocusSearch  (focus the inline search/catalog field)
 *
 * Screens pass `{}` no-ops for actions that have no meaningful target on that
 * screen. Every handled event returns `true` so the key is consumed and does
 * not fall through to focused TextFields.
 *
 * On phones with no physical keyboard the focusRequester never receives focus,
 * so onPreviewKeyEvent never fires — this is a silent no-op on touch-only
 * devices, identical in behaviour to [TicketDetailKeyboardHost].
 */
@Composable
fun PosKeyboardShortcuts(
    /** F1 — New sale: navigate to PosEntry and start over (clear cart state). */
    onNewSale: () -> Unit,
    /** F2 — Scan: open camera barcode scanner. */
    onScan: () -> Unit,
    /** F3 — Customer search: expand SearchBar / focus customer search field. */
    onCustomerSearch: () -> Unit,
    /** F4 — Discount: open cart-discount dialog. */
    onDiscount: () -> Unit,
    /** F5 — Tender: navigate to PosTenderScreen. */
    onTender: () -> Unit,
    /** F6 — Park: park / hold current cart (POS-PARK-001 stub). */
    onPark: () -> Unit,
    /** F7 — Print: reprint last receipt. */
    onPrint: () -> Unit,
    /** F8 — Refund: navigate to refund flow (stub). */
    onRefund: () -> Unit,
    /** Ctrl+F — Focus inline search / catalog search field. */
    onFocusSearch: () -> Unit,
    content: @Composable () -> Unit,
) {
    val focusRequester = remember { FocusRequester() }
    // Claim focus once so onPreviewKeyEvent intercepts keystrokes before
    // focused child TextFields swallow them. runCatching swallows the
    // FocusRequester "no focusable target" exception that fires on recompose
    // before the Box is laid out — same pattern as KeyboardShortcutsHost.
    LaunchedEffect(Unit) {
        runCatching { focusRequester.requestFocus() }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .focusRequester(focusRequester)
            .focusable()
            .onPreviewKeyEvent { event ->
                if (event.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false

                // Ctrl+F — focus inline search. Handled before the bare-F gate
                // because Ctrl is pressed here.
                if (event.isCtrlPressed && event.key == Key.F) {
                    onFocusSearch()
                    return@onPreviewKeyEvent true
                }

                // Bare F-keys — no modifier required.
                if (event.isCtrlPressed) return@onPreviewKeyEvent false

                when (event.key) {
                    Key.F1 -> { onNewSale();        true }
                    Key.F2 -> { onScan();           true }
                    Key.F3 -> { onCustomerSearch(); true }
                    Key.F4 -> { onDiscount();       true }
                    Key.F5 -> { onTender();         true }
                    Key.F6 -> { onPark();           true }
                    Key.F7 -> { onPrint();          true }
                    Key.F8 -> { onRefund();         true }
                    else   ->   false
                }
            },
    ) {
        content()
    }
}
