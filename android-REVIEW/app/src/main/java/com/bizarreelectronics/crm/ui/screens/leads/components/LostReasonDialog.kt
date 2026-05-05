package com.bizarreelectronics.crm.ui.screens.leads.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * Predefined lost-reason categories (ActionPlan §9 L1393 / L1410).
 *
 * "other" triggers the free-text field. All keys are lowercase for API compatibility.
 */
enum class LostReasonCategory(val key: String, val label: String) {
    Price("price", "Price too high"),
    Timing("timing", "Bad timing"),
    Competitor("competitor", "Chose a competitor"),
    NotAFit("not-a-fit", "Not a good fit"),
    Other("other", "Other (specify below)"),
}

/**
 * Modal dialog that collects a required lost reason before transitioning a lead
 * to the "lost" status (ActionPlan §9 L1393 / L1410).
 *
 * The dialog validates that a reason is selected. "Other" requires a non-blank
 * free-text note. [onConfirm] is called with the final reason string only when
 * validation passes.
 *
 * @param onConfirm Called with the concatenated reason (category label + optional detail).
 * @param onDismiss Called when the user cancels without saving.
 */
@Composable
fun LostReasonDialog(
    onConfirm: (reason: String) -> Unit,
    onDismiss: () -> Unit,
) {
    var selectedCategory by rememberSaveable { mutableStateOf<LostReasonCategory?>(null) }
    var freeText by rememberSaveable { mutableStateOf("") }
    var showCategoryMenu by rememberSaveable { mutableStateOf(false) }
    var validationError by rememberSaveable { mutableStateOf<String?>(null) }

    val isOther = selectedCategory == LostReasonCategory.Other

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                "Mark as Lost",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
        },
        text = {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(
                    "Please select a reason why this lead was not converted.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )

                // Category dropdown
                Box {
                    Surface(
                        onClick = { showCategoryMenu = true },
                        shape = MaterialTheme.shapes.small,
                        color = MaterialTheme.colorScheme.surfaceVariant,
                        modifier = Modifier
                            .fillMaxWidth()
                            .semantics { contentDescription = "Select lost reason category" },
                    ) {
                        androidx.compose.foundation.layout.Row(
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                text = selectedCategory?.label ?: "Select reason…",
                                modifier = Modifier.weight(1f),
                                style = MaterialTheme.typography.bodyMedium,
                                color = if (selectedCategory == null) {
                                    MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                                } else {
                                    MaterialTheme.colorScheme.onSurface
                                },
                            )
                            Icon(
                                Icons.Default.ArrowDropDown,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }

                    DropdownMenu(
                        expanded = showCategoryMenu,
                        onDismissRequest = { showCategoryMenu = false },
                    ) {
                        LostReasonCategory.entries.forEach { category ->
                            DropdownMenuItem(
                                text = { Text(category.label) },
                                onClick = {
                                    selectedCategory = category
                                    showCategoryMenu = false
                                    validationError = null
                                },
                            )
                        }
                    }
                }

                // Free text for "Other"
                if (isOther) {
                    OutlinedTextField(
                        value = freeText,
                        onValueChange = {
                            freeText = it
                            validationError = null
                        },
                        label = { Text("Describe the reason") },
                        modifier = Modifier.fillMaxWidth(),
                        maxLines = 3,
                        isError = validationError != null && freeText.isBlank(),
                    )
                }

                // Validation error
                if (validationError != null) {
                    Spacer(modifier = Modifier.height(2.dp))
                    Text(
                        text = validationError!!,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    when {
                        selectedCategory == null -> {
                            validationError = "Please select a reason."
                        }
                        isOther && freeText.isBlank() -> {
                            validationError = "Please describe the reason."
                        }
                        else -> {
                            val reason = if (isOther && freeText.isNotBlank()) {
                                "${selectedCategory!!.label}: $freeText"
                            } else {
                                selectedCategory!!.label
                            }
                            onConfirm(reason)
                        }
                    }
                },
                colors = ButtonDefaults.textButtonColors(
                    contentColor = MaterialTheme.colorScheme.error,
                ),
            ) {
                Text("Mark as Lost", fontWeight = FontWeight.SemiBold)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        },
    )
}
