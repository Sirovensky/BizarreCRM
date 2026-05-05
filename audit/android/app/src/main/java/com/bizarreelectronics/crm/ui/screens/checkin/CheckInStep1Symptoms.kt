package com.bizarreelectronics.crm.ui.screens.checkin

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private val SYMPTOMS = listOf(
    SymptomTile("Cracked screen", "💔"),
    SymptomTile("Battery drain", "🔋"),
    SymptomTile("Won't charge", "⚡"),
    SymptomTile("Liquid damage", "💧"),
    SymptomTile("No sound", "🔇"),
    SymptomTile("Camera", "📷"),
    SymptomTile("Buttons", "🔘"),
    SymptomTile("Other", "❓"),
)

private data class SymptomTile(val label: String, val emoji: String)

@Composable
fun CheckInStep1Symptoms(
    selected: Set<String>,
    onToggle: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            "What's broken?",
            style = MaterialTheme.typography.titleLarge,
        )
        Text(
            "Select all that apply. At least one is required to continue.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        LazyVerticalGrid(
            columns = GridCells.Fixed(2),
            modifier = Modifier.fillMaxWidth(),
            contentPadding = PaddingValues(vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(SYMPTOMS, key = { it.label }) { tile ->
                SymptomTileCard(
                    tile = tile,
                    isSelected = tile.label in selected,
                    onClick = { onToggle(tile.label) },
                )
            }
        }
    }
}

@Composable
private fun SymptomTileCard(
    tile: SymptomTile,
    isSelected: Boolean,
    onClick: () -> Unit,
) {
    val borderColor = if (isSelected) {
        MaterialTheme.colorScheme.primary
    } else {
        MaterialTheme.colorScheme.outlineVariant
    }

    // Geometry matches FlowTile (96dp fixed, surface bg, 10dp rounded, 1dp
    // outline / 1.5dp primary border on select) so the cashier sees the same
    // tile shape across device-type → make → model → symptoms steps.
    Surface(
        shape = RoundedCornerShape(10.dp),
        color = MaterialTheme.colorScheme.surface,
        modifier = Modifier
            .fillMaxWidth()
            .height(96.dp)
            .border(
                width = if (isSelected) 1.5.dp else 1.dp,
                color = borderColor,
                shape = RoundedCornerShape(10.dp),
            )
            .clickable(onClick = onClick)
            .semantics {
                contentDescription = "${tile.label}, ${if (isSelected) "selected" else "not selected"}"
                role = Role.Checkbox
                selected = isSelected
            },
    ) {
        Box(contentAlignment = Alignment.Center) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
                modifier = Modifier.padding(12.dp),
            ) {
                Text(
                    text = tile.emoji,
                    fontSize = 22.sp,
                )
                Text(
                    text = tile.label,
                    style = MaterialTheme.typography.labelMedium.copy(
                        fontWeight = FontWeight.Bold,
                    ),
                    textAlign = TextAlign.Center,
                    color = if (isSelected) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurface
                    },
                )
            }
        }
    }
}
