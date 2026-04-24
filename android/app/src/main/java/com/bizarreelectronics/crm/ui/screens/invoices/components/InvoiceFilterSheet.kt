package com.bizarreelectronics.crm.ui.screens.invoices.components

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
 * Active filter state for the invoice list.
 *
 * All fields are optional — null = not filtered on that dimension.
 */
data class InvoiceFilterState(
    val customerQuery: String = "",
    val dateFrom: String = "",   // ISO yyyy-MM-dd
    val dateTo: String = "",
    val amountMin: String = "",  // dollars, inclusive
    val amountMax: String = "",
) {
    val isActive: Boolean
        get() = customerQuery.isNotBlank() || dateFrom.isNotBlank() || dateTo.isNotBlank() ||
            amountMin.isNotBlank() || amountMax.isNotBlank()
}

/**
 * ModalBottomSheet with date-range, customer name, and amount-range filters.
 *
 * Calls [onApply] with the new state when the user taps Apply. Calls [onDismiss]
 * when the sheet is dismissed without applying.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InvoiceFilterSheet(
    initial: InvoiceFilterState,
    sheetState: SheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    onApply: (InvoiceFilterState) -> Unit,
    onDismiss: () -> Unit,
) {
    var customerQuery by rememberSaveable { mutableStateOf(initial.customerQuery) }
    var dateFrom by rememberSaveable { mutableStateOf(initial.dateFrom) }
    var dateTo by rememberSaveable { mutableStateOf(initial.dateTo) }
    var amountMin by rememberSaveable { mutableStateOf(initial.amountMin) }
    var amountMax by rememberSaveable { mutableStateOf(initial.amountMax) }

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
            Text(
                "Filter Invoices",
                style = MaterialTheme.typography.titleMedium,
            )

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
                "Date range",
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

            // Amount range
            Text(
                "Amount range",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedTextField(
                    value = amountMin,
                    onValueChange = { v ->
                        if (v.isEmpty() || v.matches(Regex("^\\d*\\.?\\d{0,2}$"))) amountMin = v
                    },
                    modifier = Modifier.weight(1f),
                    label = { Text("Min ($)") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                )
                OutlinedTextField(
                    value = amountMax,
                    onValueChange = { v ->
                        if (v.isEmpty() || v.matches(Regex("^\\d*\\.?\\d{0,2}$"))) amountMax = v
                    },
                    modifier = Modifier.weight(1f),
                    label = { Text("Max ($)") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
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
                        amountMin = ""
                        amountMax = ""
                    },
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Clear")
                }
                BrandPrimaryButton(
                    onClick = {
                        onApply(
                            InvoiceFilterState(
                                customerQuery = customerQuery.trim(),
                                dateFrom = dateFrom.trim(),
                                dateTo = dateTo.trim(),
                                amountMin = amountMin.trim(),
                                amountMax = amountMax.trim(),
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
