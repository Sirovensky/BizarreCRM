package com.bizarreelectronics.crm.ui.screens.communications

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Sms
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.dto.SmsTemplateDto

/**
 * Modal bottom sheet listing SMS templates.
 *
 * Tapping a row expands `{{placeholder}}` tokens from [context] and calls
 * [onTemplateSelected] with the resulting body, then dismisses.
 *
 * State machine:
 *  - [templates] empty + no loading → empty copy with link to Settings.
 *  - [isLoading] true → single CircularProgressIndicator.
 *  - otherwise → LazyColumn of template cards.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SmsTemplatePickerSheet(
    templates: List<SmsTemplateDto>,
    context: Map<String, String>,
    onTemplateSelected: (expandedBody: String) -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    isLoading: Boolean = false,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        modifier = modifier,
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            // Sheet drag handle is provided by ModalBottomSheet itself.
            // Sheet title row.
            Text(
                text = "Insert template",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 8.dp),
            )
            HorizontalDivider()

            when {
                isLoading -> {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(160.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator()
                    }
                }
                templates.isEmpty() -> {
                    TemplateEmptyState()
                }
                else -> {
                    LazyColumn(
                        modifier = Modifier.fillMaxWidth(),
                        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        items(templates, key = { it.id }) { template ->
                            val expandedBody = interpolate(template.body, context)
                            TemplateRow(
                                name = template.name,
                                preview = expandedBody,
                                onClick = { onTemplateSelected(expandedBody) },
                            )
                        }
                        // Bottom padding so last item clears nav bar.
                        item { Spacer(modifier = Modifier.height(8.dp)) }
                    }
                }
            }
        }
    }
}

@Composable
private fun TemplateRow(
    name: String,
    preview: String,
    onClick: () -> Unit,
) {
    // Defensive HTML-escape for preview display.  SMS bodies are plaintext
    // but a malicious template could contain < or & characters.
    val safePreview = preview
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")

    Card(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .semantics {
                contentDescription = "Template: $name, preview: $safePreview"
                role = Role.Button
            },
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                text = name,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = preview,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun TemplateEmptyState() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(160.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                imageVector = Icons.Default.Sms,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(40.dp),
            )
            Text(
                text = "No templates yet.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = "Add from Settings \u2192 SMS Templates.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.primary,
            )
        }
    }
}

/**
 * Replace `{{key}}` tokens in [template] with values from [context].
 * Tokens with no matching key are left as-is (not stripped).
 */
internal fun interpolate(template: String, context: Map<String, String>): String {
    val pattern = Regex("\\{\\{([a-zA-Z0-9_]+)\\}\\}")
    return pattern.replace(template) { match ->
        context[match.groupValues[1]] ?: match.value
    }
}
