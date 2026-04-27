package com.bizarreelectronics.crm.ui.components.shared

import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.VisualTransformation

/**
 * Brand-aligned [OutlinedTextField] wrapper — §30.7.
 *
 * Centralises the consistent visual treatment that all text inputs in the
 * Bizarre CRM app should share:
 *
 *   - Shape  : `MaterialTheme.shapes.small` (4 dp, matching the token table).
 *   - Colors : `surfaceVariant` container + `primary` focused indicator/cursor
 *              + `onSurfaceVariant` label/placeholder (unfocused) so inputs are
 *              quiet until active.
 *   - Error  : `colorScheme.error` indicator + container tint + helper text.
 *   - Helper : optional supporting text below the field (also used as error msg).
 *   - Prefix/Suffix : optional composable slots forwarded to [OutlinedTextField].
 *
 * All [OutlinedTextField] parameters that callers commonly need are exposed;
 * additional parameters can be added as the need arises.
 *
 * ## Usage
 * ```kotlin
 * CommonTextField(
 *     value = phoneNumber,
 *     onValueChange = viewModel::onPhoneChange,
 *     label = "Phone",
 *     isError = phoneError != null,
 *     helperText = phoneError,
 *     prefix = { Text("+1") },
 *     keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
 * )
 * ```
 *
 * ## Migration targets (Wave 3+)
 * Replace all raw [OutlinedTextField] and [TextField] usages that set their
 * own label/error/helper handling with this wrapper so corrections to the
 * design (e.g. shape change, error color tweak) propagate site-wide.
 */
@Composable
fun CommonTextField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    label: String? = null,
    placeholder: String? = null,
    helperText: String? = null,
    isError: Boolean = false,
    enabled: Boolean = true,
    readOnly: Boolean = false,
    singleLine: Boolean = true,
    maxLines: Int = if (singleLine) 1 else Int.MAX_VALUE,
    minLines: Int = 1,
    leadingIcon: (@Composable () -> Unit)? = null,
    trailingIcon: (@Composable () -> Unit)? = null,
    prefix: (@Composable () -> Unit)? = null,
    suffix: (@Composable () -> Unit)? = null,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    keyboardActions: KeyboardActions = KeyboardActions.Default,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier,
        enabled = enabled,
        readOnly = readOnly,
        textStyle = MaterialTheme.typography.bodyMedium,
        label = label?.let { { Text(it, style = MaterialTheme.typography.labelMedium) } },
        placeholder = placeholder?.let {
            {
                Text(
                    it,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        supportingText = helperText?.let {
            {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = if (isError) MaterialTheme.colorScheme.error
                            else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        isError = isError,
        leadingIcon = leadingIcon,
        trailingIcon = trailingIcon,
        prefix = prefix,
        suffix = suffix,
        visualTransformation = visualTransformation,
        keyboardOptions = keyboardOptions,
        keyboardActions = keyboardActions,
        singleLine = singleLine,
        maxLines = maxLines,
        minLines = minLines,
        shape = MaterialTheme.shapes.small,
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor       = MaterialTheme.colorScheme.primary,
            unfocusedBorderColor     = MaterialTheme.colorScheme.outline,
            errorBorderColor         = MaterialTheme.colorScheme.error,
            focusedLabelColor        = MaterialTheme.colorScheme.primary,
            unfocusedLabelColor      = MaterialTheme.colorScheme.onSurfaceVariant,
            errorLabelColor          = MaterialTheme.colorScheme.error,
            cursorColor              = MaterialTheme.colorScheme.primary,
            errorCursorColor         = MaterialTheme.colorScheme.error,
            focusedContainerColor    = MaterialTheme.colorScheme.surfaceVariant,
            unfocusedContainerColor  = MaterialTheme.colorScheme.surfaceVariant,
            disabledContainerColor   = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.38f),
            errorContainerColor      = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.12f),
        ),
    )
}
