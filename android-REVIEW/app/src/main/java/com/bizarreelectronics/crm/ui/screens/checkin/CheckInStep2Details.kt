package com.bizarreelectronics.crm.ui.screens.checkin

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import com.bizarreelectronics.crm.ui.components.shared.brandColors
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage

private const val MAX_CUSTOMER_NOTES = 2000
private const val MAX_INTERNAL_NOTES = 5000

@Composable
fun CheckInStep2Details(
    customerNotes: String,
    internalNotes: String,
    passcodeFormat: PasscodeFormat,
    passcode: String,
    photoUris: List<String>,
    onCustomerNotesChange: (String) -> Unit,
    onInternalNotesChange: (String) -> Unit,
    onPasscodeFormatChange: (PasscodeFormat) -> Unit,
    onPasscodeChange: (String) -> Unit,
    onAddPhoto: (String) -> Unit,
    onRemovePhoto: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item(key = "customer_notes") {
            OutlinedTextField(
                value = customerNotes,
                onValueChange = { if (it.length <= MAX_CUSTOMER_NOTES) onCustomerNotesChange(it) },
                label = { Text("Diagnostic notes (receipt-visible)") },
                placeholder = { Text("What the customer told you…") },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(120.dp)
                    .semantics { contentDescription = "Diagnostic notes, visible on receipt" },
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.Sentences,
                    imeAction = ImeAction.Default,
                ),
                maxLines = 5,
                supportingText = { Text("${customerNotes.length} / $MAX_CUSTOMER_NOTES") },
            )
        }

        item(key = "internal_notes") {
            OutlinedTextField(
                value = internalNotes,
                onValueChange = { if (it.length <= MAX_INTERNAL_NOTES) onInternalNotesChange(it) },
                label = { Text("Internal notes (tech-only)") },
                placeholder = { Text("Notes visible only to staff…") },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(100.dp)
                    .semantics { contentDescription = "Internal notes, visible only to technicians" },
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.Sentences,
                    imeAction = ImeAction.Default,
                ),
                maxLines = 4,
                supportingText = { Text("${internalNotes.length} / $MAX_INTERNAL_NOTES") },
            )
        }

        item(key = "passcode_section") {
            PasscodeSection(
                format = passcodeFormat,
                passcode = passcode,
                onFormatChange = onPasscodeFormatChange,
                onPasscodeChange = onPasscodeChange,
            )
        }

        item(key = "photos_section") {
            PhotoSection(
                uris = photoUris,
                onAdd = onAddPhoto,
                onRemove = onRemovePhoto,
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PasscodeSection(
    format: PasscodeFormat,
    passcode: String,
    onFormatChange: (PasscodeFormat) -> Unit,
    onPasscodeChange: (String) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("Device passcode", style = MaterialTheme.typography.titleSmall)
        Text(
            "Encrypted · auto-deleted when ticket closes",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            contentPadding = PaddingValues(vertical = 4.dp),
        ) {
            items(PasscodeFormat.entries, key = { it.name }) { f ->
                FilterChip(
                    selected = format == f,
                    onClick = { onFormatChange(f) },
                    label = { Text(f.label) },
                    colors = FilterChipDefaults.brandColors(),
                    modifier = Modifier.semantics {
                        contentDescription = "Passcode format: ${f.label}"
                    },
                )
            }
        }

        if (format != PasscodeFormat.NONE) {
            val (keyboardType, visual) = when (format) {
                PasscodeFormat.FOUR_DIGIT, PasscodeFormat.SIX_DIGIT ->
                    KeyboardType.NumberPassword to PasswordVisualTransformation()
                PasscodeFormat.ALPHANUMERIC ->
                    KeyboardType.Password to PasswordVisualTransformation()
                PasscodeFormat.PATTERN ->
                    KeyboardType.Text to VisualTransformation.None
                PasscodeFormat.NONE ->
                    KeyboardType.Text to VisualTransformation.None
            }
            OutlinedTextField(
                value = passcode,
                onValueChange = onPasscodeChange,
                label = { Text("Passcode") },
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics { contentDescription = "Device passcode input" },
                keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
                visualTransformation = visual,
                singleLine = true,
            )
        }
    }
}

@Composable
private fun PhotoSection(
    uris: List<String>,
    onAdd: (String) -> Unit,
    onRemove: (String) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text("Intake photos (${uris.size} / 10)", style = MaterialTheme.typography.titleSmall)
            if (uris.size < 10) {
                IconButton(
                    onClick = { onAdd("picker://launch") },
                    modifier = Modifier.semantics { contentDescription = "Add photo" },
                ) {
                    Icon(Icons.Default.Add, contentDescription = null)
                }
            }
        }

        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            contentPadding = PaddingValues(vertical = 4.dp),
        ) {
            items(uris, key = { it }) { uri ->
                IntakePhotoThumb(uri = uri, onRemove = { onRemove(uri) })
            }
            if (uris.size < 10) {
                item(key = "add_tile") {
                    AddPhotoTile(onClick = { onAdd("picker://launch") })
                }
            }
        }
    }
}

@Composable
private fun IntakePhotoThumb(uri: String, onRemove: () -> Unit) {
    Box(modifier = Modifier.size(88.dp)) {
        AsyncImage(
            model = uri,
            contentDescription = "Intake photo",
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .fillMaxSize()
                .border(1.dp, MaterialTheme.colorScheme.outline, MaterialTheme.shapes.small),
        )
        IconButton(
            onClick = onRemove,
            modifier = Modifier
                .align(Alignment.TopEnd)
                .size(28.dp)
                .semantics { contentDescription = "Remove photo" },
        ) {
            Icon(
                Icons.Default.Close,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.error,
                modifier = Modifier.size(16.dp),
            )
        }
    }
}

@Composable
private fun AddPhotoTile(onClick: () -> Unit) {
    Card(
        modifier = Modifier
            .size(88.dp)
            .clickable(onClick = onClick)
            .semantics { contentDescription = "Add photo from camera or library" },
        shape = MaterialTheme.shapes.small,
    ) {
        Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
            Icon(
                Icons.Default.Add,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(32.dp),
            )
        }
    }
}
