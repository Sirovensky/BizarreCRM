package com.bizarreelectronics.crm.ui.screens.inventory.components

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Place
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.components.shared.BrandCard

/**
 * Bin location picker with autocomplete (L1076).
 *
 * Presents a text field pre-filled with the item's current bin location. When
 * the user focuses the field the autocomplete dropdown shows matching bins from
 * [availableBins] (loaded via [InventoryApi.getBins]). Saving calls [onSave]
 * with the new bin value.
 *
 * @param currentBin    Existing bin value (may be null/blank).
 * @param availableBins Known bins for autocomplete suggestions.
 * @param isSaving      True while a save request is in-flight.
 * @param onSave        Invoked with the new bin string when the user confirms.
 * @param modifier      Applied to the root [BrandCard].
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InventoryBinPicker(
    currentBin: String?,
    availableBins: List<String>,
    isSaving: Boolean,
    onSave: (bin: String) -> Unit,
    modifier: Modifier = Modifier,
) {
    var binText by rememberSaveable(currentBin) { mutableStateOf(currentBin ?: "") }
    var showDropdown by remember { mutableStateOf(false) }

    val suggestions = remember(binText, availableBins) {
        if (binText.isBlank()) availableBins.take(8)
        else availableBins.filter { it.contains(binText, ignoreCase = true) }.take(8)
    }

    val isDirty = binText != (currentBin ?: "")

    BrandCard(modifier = modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    Icons.Default.Place,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                    tint = MaterialTheme.colorScheme.primary,
                )
                Text("Bin location", style = MaterialTheme.typography.titleSmall)
            }

            ExposedDropdownMenuBox(
                expanded = showDropdown && suggestions.isNotEmpty(),
                onExpandedChange = { showDropdown = it },
            ) {
                OutlinedTextField(
                    value = binText,
                    onValueChange = { v ->
                        binText = v
                        showDropdown = true
                    },
                    label = { Text("Bin / shelf") },
                    singleLine = true,
                    modifier = Modifier
                        .fillMaxWidth()
                        .menuAnchor(MenuAnchorType.PrimaryEditable),
                    trailingIcon = {
                        ExposedDropdownMenuDefaults.TrailingIcon(expanded = showDropdown)
                    },
                )

                ExposedDropdownMenu(
                    expanded = showDropdown && suggestions.isNotEmpty(),
                    onDismissRequest = { showDropdown = false },
                ) {
                    suggestions.forEach { bin ->
                        DropdownMenuItem(
                            text = { Text(bin) },
                            onClick = {
                                binText = bin
                                showDropdown = false
                            },
                        )
                    }
                }
            }

            if (isDirty) {
                Button(
                    onClick = { onSave(binText) },
                    enabled = !isSaving,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    if (isSaving) {
                        CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Saving…")
                    } else {
                        Text("Update bin")
                    }
                }
            }
        }
    }
}
