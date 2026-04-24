package com.bizarreelectronics.crm.ui.screens.importdata.components

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.screens.importdata.PreviewData

private val CELL_MIN_WIDTH = 100.dp
private val CELL_MAX_WIDTH = 200.dp

/**
 * Horizontally-scrollable preview table showing the first N rows of the
 * imported file. Used in Step PREVIEW.
 */
@Composable
fun ImportPreviewTable(
    preview: PreviewData,
    modifier: Modifier = Modifier,
) {
    val scrollState = rememberScrollState()
    Column(modifier = modifier.horizontalScroll(scrollState)) {
        // Header row
        Row {
            preview.columns.forEach { col ->
                Text(
                    text = col,
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier
                        .widthIn(min = CELL_MIN_WIDTH, max = CELL_MAX_WIDTH)
                        .padding(horizontal = 8.dp, vertical = 4.dp),
                    maxLines = 1,
                )
            }
        }
        HorizontalDivider()
        preview.rows.forEach { row ->
            Row {
                preview.columns.indices.forEach { i ->
                    val cell = row.getOrElse(i) { "" }
                    Text(
                        text = cell,
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier
                            .widthIn(min = CELL_MIN_WIDTH, max = CELL_MAX_WIDTH)
                            .padding(horizontal = 8.dp, vertical = 4.dp),
                        maxLines = 2,
                    )
                }
            }
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
        }
        if (preview.rows.isEmpty()) {
            Text(
                text = "No rows to preview.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(8.dp),
            )
        }
    }
}
