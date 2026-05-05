package com.bizarreelectronics.crm.ui.screens.setup.steps

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp

/**
 * §2.10 Step 2 — Owner account.
 *
 * Collects: username (≥3 chars), email, password (≥8 chars).
 *
 * Server contract (step_index=2):
 *   { username: String, email: String, password: String }
 *
 * SECURITY: password is transmitted once to the server for hashing and is
 * never stored locally beyond the lifetime of this Composable's remembered state.
 *
 * [data] — current saved values for this step.
 * [onDataChange] — called with the full updated field map on any change.
 * [inlineError] — §36.4 validation error string to display inline; null when no error.
 */
@Composable
fun OwnerAccountStep(
    data: Map<String, Any>,
    onDataChange: (Map<String, Any>) -> Unit,
    inlineError: String? = null,
    modifier: Modifier = Modifier,
) {
    var username        by remember { mutableStateOf(data["username"]?.toString() ?: "") }
    var email           by remember { mutableStateOf(data["email"]?.toString() ?: "") }
    var password        by remember { mutableStateOf(data["password"]?.toString() ?: "") }
    var passwordVisible by remember { mutableStateOf(false) }

    fun emit() {
        onDataChange(mapOf(
            "username" to username,
            "email"    to email,
            "password" to password,
        ))
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Owner Account", style = MaterialTheme.typography.titleLarge)
        Text(
            "This creates the administrator account for your CRM.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        OutlinedTextField(
            value = username,
            onValueChange = { username = it; emit() },
            label = { Text("Username *") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            supportingText = { Text("Minimum 3 characters") },
        )
        OutlinedTextField(
            value = email,
            onValueChange = { email = it; emit() },
            label = { Text("Email *") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
        )
        OutlinedTextField(
            value = password,
            onValueChange = { password = it; emit() },
            label = { Text("Password *") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            visualTransformation = if (passwordVisible) VisualTransformation.None
                                   else PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            trailingIcon = {
                IconButton(onClick = { passwordVisible = !passwordVisible }) {
                    Icon(
                        imageVector = if (passwordVisible) Icons.Default.Visibility
                                      else Icons.Default.VisibilityOff,
                        contentDescription = if (passwordVisible) "Hide password" else "Show password",
                    )
                }
            },
            supportingText = { Text("Minimum 8 characters") },
        )

        // §36.4 — inline validation error displayed below step fields.
        if (!inlineError.isNullOrBlank()) {
            Text(
                text  = inlineError,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
            )
        }
    }
}
