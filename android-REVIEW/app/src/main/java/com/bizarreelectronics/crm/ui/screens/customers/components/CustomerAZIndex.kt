package com.bizarreelectronics.crm.ui.screens.customers.components

import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private val LETTERS = ('A'..'Z').map { it.toString() } + listOf("#")

/**
 * Right-edge A–Z fast scroller for the customer list (plan:L879).
 *
 * Renders a narrow column of letter labels. Tap or drag on a letter calls
 * [onLetterSelected] with the tapped character so the screen can scroll to
 * the first matching customer.
 *
 * @param modifier         Applied to the outermost Column.
 * @param onLetterSelected Called with the letter string ("A".."Z" or "#").
 */
@Composable
fun CustomerAZIndex(
    modifier: Modifier = Modifier,
    onLetterSelected: (String) -> Unit,
) {
    val density = LocalDensity.current
    var columnHeightPx by remember { mutableStateOf(0) }

    Column(
        modifier = modifier
            .width(24.dp)
            .onSizeChanged { columnHeightPx = it.height }
            .pointerInput(Unit) {
                detectTapGestures { offset ->
                    val index = ((offset.y / columnHeightPx) * LETTERS.size)
                        .toInt()
                        .coerceIn(0, LETTERS.lastIndex)
                    onLetterSelected(LETTERS[index])
                }
            }
            .pointerInput(Unit) {
                detectDragGestures { change, _ ->
                    val index = ((change.position.y / columnHeightPx) * LETTERS.size)
                        .toInt()
                        .coerceIn(0, LETTERS.lastIndex)
                    onLetterSelected(LETTERS[index])
                }
            },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        LETTERS.forEach { letter ->
            Text(
                text = letter,
                modifier = Modifier.padding(vertical = 0.5.dp),
                style = MaterialTheme.typography.labelSmall.copy(
                    fontSize = 9.sp,
                    fontWeight = FontWeight.SemiBold,
                ),
                color = MaterialTheme.colorScheme.primary,
            )
        }
    }
}
