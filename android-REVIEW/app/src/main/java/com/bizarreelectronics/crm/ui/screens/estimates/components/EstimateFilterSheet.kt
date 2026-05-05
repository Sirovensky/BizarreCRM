package com.bizarreelectronics.crm.ui.screens.estimates.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SheetState
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.components.shared.BrandPrimaryButton
import com.bizarreelectronics.crm.ui.components.shared.BrandTextButton

/**
 * Active filter state for the estimate list.
 *
 * All string fields default to "" (unset). [isActive] returns true when any
 * field is non-blank so the caller can highlight the filter icon.
 */
data class EstimateFilterState(
    val customerQuery: String = "",
    val dateFrom: String = "",   // ISO yyyy-MM-dd
    val dateTo: String = "",
) {
    val isActive: Boolean
        get() = customerQuery.isNotBlank() || dateFrom.isNotBlank() || dateTo.isNotBlank()
}

/**
 * ModalBottomSheet for date-range and customer-name estimate filtering.
 *
 * Pattern mirrors [InvoiceFilterSheet] from wave 15 (commit 2c17758) for consistency.
 * Calls [onApply] when the user taps Apply; [onDismiss] on sheet collapse without apply.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EstimateFilterSheet(
    initial: EstimateFilterState,
    sheetState: SheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    onApply: (EstimateFilterState) -> Unit,
    onDismiss: () -> Unit,
) {
    var customerQuery by rememberSaveable { mutableStateOf(initial.customerQuery) }
    var dateFrom by rememberSaveable { mutableStateOf(initial.dateFrom) }
    var dateTo by rememberSaveable { mutableStateOf(initial.dateTo) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("Filter Estimates", style = MaterialTheme.typography.titleMedium)

            HorizontalDivider()

            // Customer name
            OutlinedTextField(
                value = customerQuery,
                onValueChange = { customerQuery = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Customer name") },
                singleLine = true,
            )

            // Date range
            Text(
                "Created date range",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedTextField(
                    value = dateFrom,
                    onValueChange = { dateFrom = it },
                    modifier = Modifier.weight(1f),
                    label = { Text("From (yyyy-MM-dd)") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                )
                OutlinedTextField(
                    value = dateTo,
                    onValueChange = { dateTo = it },
                    modifier = Modifier.weight(1f),
                    label = { Text("To (yyyy-MM-dd)") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                )
            }

            Spacer(modifier = Modifier.height(4.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                BrandTextButton(
                    onClick = {
                        customerQuery = ""
                        dateFrom = ""
                        dateTo = ""
                    },
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Clear")
                }
                BrandPrimaryButton(
                    onClick = {
                        onApply(
                            EstimateFilterState(
                                customerQuery = customerQuery.trim(),
                                dateFrom = dateFrom.trim(),
                                dateTo = dateTo.trim(),
                            )
                        )
                    },
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Apply")
                }
            }

            Spacer(modifier = Modifier.height(8.dp))
        }
    }
}
