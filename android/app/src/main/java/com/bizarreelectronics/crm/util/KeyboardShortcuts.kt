package com.bizarreelectronics.crm.util

import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.isShiftPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type

/**
 * §17.10 — global hardware-keyboard shortcuts for tablet / ChromeOS / Pixel-
 * w/ Magic Keyboard. Wraps the nav graph in a focusable Box that previews
 * key events before they reach focused widgets, so the shortcut fires no
 * matter where the cursor is.
 *
 * Mappings (mirrors the iOS plan + the existing FAB SpeedDial actions):
 *   - Ctrl+N        → onNewTicket
 *   - Ctrl+Shift+N  → onNewCustomer
 *   - Ctrl+Shift+S  → onScanBarcode
 *   - Ctrl+Shift+M  → onNewSms
 *   - Ctrl+F        → onGlobalSearch
 *   - Ctrl+,        → onSettings
 *
 * Returns true from the lambda when handled so the event is not propagated
 * further (otherwise Ctrl+N would also type "n" into the focused TextField).
 *
 * On phones with no keyboard the modifier is a no-op — the focusRequester
 * never receives focus, so onPreviewKeyEvent never fires.
 */
@Composable
fun KeyboardShortcutsHost(
    onNewTicket: () -> Unit,
    onNewCustomer: () -> Unit,
    onScanBarcode: () -> Unit,
    onNewSms: () -> Unit,
    onGlobalSearch: () -> Unit,
    onSettings: () -> Unit,
    content: @Composable () -> Unit,
) {
    val focusRequester = remember { FocusRequester() }
    var showHelp by remember { mutableStateOf(false) }
    // Claim focus once so onPreviewKeyEvent receives keystrokes before the
    // focused TextField swallows them. Safe no-op when no keyboard is
    // attached (the request resolves but no events ever arrive).
    LaunchedEffect(Unit) {
        runCatching { focusRequester.requestFocus() }
    }

    if (showHelp) {
        AlertDialog(
            onDismissRequest = { showHelp = false },
            confirmButton = { TextButton(onClick = { showHelp = false }) { Text("Close") } },
            title = { Text("Keyboard shortcuts") },
            text = { ShortcutHelpTable() },
        )
    }

    Box(
        modifier = Modifier
            .focusRequester(focusRequester)
            .focusable()
            .onPreviewKeyEvent { event ->
                if (event.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                if (!event.isCtrlPressed) return@onPreviewKeyEvent false
                when {
                    event.key == Key.N && event.isShiftPressed -> {
                        onNewCustomer(); true
                    }
                    event.key == Key.N -> {
                        onNewTicket(); true
                    }
                    event.key == Key.S && event.isShiftPressed -> {
                        onScanBarcode(); true
                    }
                    event.key == Key.M && event.isShiftPressed -> {
                        onNewSms(); true
                    }
                    event.key == Key.F -> {
                        onGlobalSearch(); true
                    }
                    event.key == Key.Comma -> {
                        onSettings(); true
                    }
                    event.key == Key.Slash -> {
                        showHelp = !showHelp; true
                    }
                    else -> false
                }
            },
    ) {
        content()
    }
}

@Composable
private fun ShortcutHelpTable() {
    val rows = listOf(
        "Ctrl+N" to "New ticket",
        "Ctrl+Shift+N" to "New customer",
        "Ctrl+Shift+S" to "Scan barcode",
        "Ctrl+Shift+M" to "New SMS",
        "Ctrl+F" to "Global search",
        "Ctrl+," to "Settings",
        "Ctrl+/" to "Show this help",
    )
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        rows.forEach { (chord, label) ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Surface(
                    color = MaterialTheme.colorScheme.surfaceContainerHigh,
                    shape = MaterialTheme.shapes.small,
                ) {
                    Text(
                        text = chord,
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                        style = MaterialTheme.typography.labelMedium,
                        fontFamily = FontFamily.Monospace,
                    )
                }
                Text(
                    text = label,
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}
