package com.bizarreelectronics.crm.ui.screens.expenses.components

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * Approval action bar shown in ExpenseDetailScreen for approver-role users.
 * Role-gated: only rendered when [isApprover] is true.
 *
 * Emits [onApprove] or [onReject] with an optional comment string.
 */
@Composable
fun ExpenseApprovalBar(
    isApprover: Boolean,
    currentStatus: String,
    isLoading: Boolean,
    onApprove: (comment: String) -> Unit,
    onReject: (comment: String) -> Unit,
) {
    if (!isApprover) return
    if (currentStatus != "pending") return

    var comment by remember { mutableStateOf("") }

    Surface(
        tonalElevation = 4.dp,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                "Approval required",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurface,
            )
            OutlinedTextField(
                value = comment,
                onValueChange = { comment = it },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Comment (optional)") },
                singleLine = true,
                enabled = !isLoading,
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                OutlinedButton(
                    onClick = { onReject(comment.trim()) },
                    modifier = Modifier.weight(1f),
                    enabled = !isLoading,
                    colors = ButtonDefaults.outlinedButtonColors(
                        contentColor = MaterialTheme.colorScheme.error,
                    ),
                ) {
                    Icon(Icons.Default.Close, contentDescription = null)
                    Spacer(Modifier.width(4.dp))
                    Text("Reject")
                }
                Button(
                    onClick = { onApprove(comment.trim()) },
                    modifier = Modifier.weight(1f),
                    enabled = !isLoading,
                ) {
                    if (isLoading) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            strokeWidth = 2.dp,
                            color = MaterialTheme.colorScheme.onPrimary,
                        )
                    } else {
                        Icon(Icons.Default.Check, contentDescription = null)
                        Spacer(Modifier.width(4.dp))
                        Text("Approve")
                    }
                }
            }
        }
    }
}
