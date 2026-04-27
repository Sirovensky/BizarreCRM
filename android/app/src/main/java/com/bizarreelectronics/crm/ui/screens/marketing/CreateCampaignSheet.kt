package com.bizarreelectronics.crm.ui.screens.marketing

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.data.remote.api.CreateCampaignRequest
import com.bizarreelectronics.crm.data.remote.api.SegmentDto

private val BrandCream = Color(0xFFFDEED0)

private val CAMPAIGN_TYPES = listOf(
    "custom" to "Custom",
    "birthday" to "Birthday",
    "winback" to "Win-back",
    "review_request" to "Review request",
    "churn_warning" to "Churn warning",
    "service_subscription" to "Service subscription",
)

private val CAMPAIGN_CHANNELS = listOf(
    "sms" to "SMS",
    "email" to "Email",
    "both" to "Both",
)

/**
 * Bottom sheet for creating a new campaign (§37.2 Campaign builder — step 1).
 *
 * Collects: name, type, channel, body template, optional subject (email),
 * and optional target segment.
 *
 * Merge tags shown as hint text: {{first_name}}, {{last_name}}.
 * Per-recipient preview and A/B test variant are deferred
 * (no server endpoint support yet).
 *
 * TCPA note: server enforces opt-in filtering; no UI gate needed here.
 *
 * Plan §37.2.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreateCampaignSheet(
    segments: List<SegmentDto>,
    onDismiss: () -> Unit,
    onCreate: (CreateCampaignRequest) -> Unit,
) {
    var name by remember { mutableStateOf("") }
    var selectedType by remember { mutableStateOf("custom") }
    var selectedChannel by remember { mutableStateOf("sms") }
    var templateBody by remember { mutableStateOf("") }
    var templateSubject by remember { mutableStateOf("") }
    var selectedSegmentId by remember { mutableStateOf<Long?>(null) }
    var typeExpanded by remember { mutableStateOf(false) }
    var channelExpanded by remember { mutableStateOf(false) }
    var segmentExpanded by remember { mutableStateOf(false) }

    val isValid = name.isNotBlank() && templateBody.isNotBlank()

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("New Campaign", style = MaterialTheme.typography.titleMedium)

            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text("Campaign name") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            // Type picker
            ExposedDropdownMenuBox(
                expanded = typeExpanded,
                onExpandedChange = { typeExpanded = it },
            ) {
                OutlinedTextField(
                    value = CAMPAIGN_TYPES.firstOrNull { it.first == selectedType }?.second ?: selectedType,
                    onValueChange = {},
                    readOnly = true,
                    label = { Text("Type") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = typeExpanded) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .menuAnchor(),
                )
                ExposedDropdownMenu(
                    expanded = typeExpanded,
                    onDismissRequest = { typeExpanded = false },
                ) {
                    CAMPAIGN_TYPES.forEach { (key, label) ->
                        DropdownMenuItem(
                            text = { Text(label) },
                            onClick = {
                                selectedType = key
                                typeExpanded = false
                            },
                        )
                    }
                }
            }

            // Channel picker
            ExposedDropdownMenuBox(
                expanded = channelExpanded,
                onExpandedChange = { channelExpanded = it },
            ) {
                OutlinedTextField(
                    value = CAMPAIGN_CHANNELS.firstOrNull { it.first == selectedChannel }?.second ?: selectedChannel,
                    onValueChange = {},
                    readOnly = true,
                    label = { Text("Channel") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = channelExpanded) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .menuAnchor(),
                )
                ExposedDropdownMenu(
                    expanded = channelExpanded,
                    onDismissRequest = { channelExpanded = false },
                ) {
                    CAMPAIGN_CHANNELS.forEach { (key, label) ->
                        DropdownMenuItem(
                            text = { Text(label) },
                            onClick = {
                                selectedChannel = key
                                channelExpanded = false
                            },
                        )
                    }
                }
            }

            // Email subject (only for email/both)
            if (selectedChannel == "email" || selectedChannel == "both") {
                OutlinedTextField(
                    value = templateSubject,
                    onValueChange = { templateSubject = it },
                    label = { Text("Subject line") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            // Message body
            OutlinedTextField(
                value = templateBody,
                onValueChange = { templateBody = it },
                label = { Text("Message body") },
                placeholder = { Text("Hi {{first_name}}, …") },
                minLines = 3,
                maxLines = 8,
                modifier = Modifier.fillMaxWidth(),
            )
            Text(
                text = "Merge tags: {{first_name}}, {{last_name}}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            // Segment picker (optional)
            if (segments.isNotEmpty()) {
                ExposedDropdownMenuBox(
                    expanded = segmentExpanded,
                    onExpandedChange = { segmentExpanded = it },
                ) {
                    OutlinedTextField(
                        value = segments.firstOrNull { it.id == selectedSegmentId }?.name ?: "All opted-in customers",
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("Target segment (optional)") },
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = segmentExpanded) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .menuAnchor(),
                    )
                    ExposedDropdownMenu(
                        expanded = segmentExpanded,
                        onDismissRequest = { segmentExpanded = false },
                    ) {
                        DropdownMenuItem(
                            text = { Text("All opted-in customers") },
                            onClick = {
                                selectedSegmentId = null
                                segmentExpanded = false
                            },
                        )
                        segments.forEach { seg ->
                            DropdownMenuItem(
                                text = { Text(seg.name) },
                                onClick = {
                                    selectedSegmentId = seg.id
                                    segmentExpanded = false
                                },
                            )
                        }
                    }
                }
            }

            Spacer(Modifier.height(4.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                OutlinedButton(
                    onClick = onDismiss,
                    modifier = Modifier.weight(1f),
                ) { Text("Cancel") }
                Button(
                    onClick = {
                        if (isValid) {
                            onCreate(
                                CreateCampaignRequest(
                                    name = name.trim(),
                                    type = selectedType,
                                    channel = selectedChannel,
                                    templateBody = templateBody.trim(),
                                    templateSubject = templateSubject.trim().ifBlank { null },
                                    segmentId = selectedSegmentId,
                                )
                            )
                        }
                    },
                    enabled = isValid,
                    colors = ButtonDefaults.buttonColors(containerColor = BrandCream, contentColor = Color.Black),
                    modifier = Modifier.weight(1f),
                ) { Text("Create") }
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}
