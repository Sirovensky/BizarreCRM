package com.bizarreelectronics.crm.ui.screens.setup.steps

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.UploadFile
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

/**
 * §2.10 Step 8 — First inventory import (stub).
 *
 * CSV upload stub — the actual file-picker + upload flow requires
 * Activity Result contracts and multipart Retrofit which are out of
 * scope for this initial wizard commit.
 *
 * Server contract (step_index=8):
 *   { skipped: "true" }        — skipped (expected in this stub)
 *   { csv_upload_id: String }  — future: server-side CSV job ID after upload
 *
 * TODO: Wire ContentResolver file-picker + MultipartUploadWorker when the
 * inventory import endpoint is finalised (see MultipartUploadWorker.kt).
 *
 * [data] — current saved values.
 * [onDataChange] — called with the field map on any change.
 */
@Composable
fun InventoryImportStep(
    data: Map<String, Any>,
    onDataChange: (Map<String, Any>) -> Unit,
    modifier: Modifier = Modifier,
) {
    // Auto-mark as skipped so validation passes; the stub has no real upload.
    LaunchedEffect(Unit) {
        if (data["skipped"] != "true") {
            onDataChange(mapOf("skipped" to "true"))
        }
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 24.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            imageVector = Icons.Default.UploadFile,
            contentDescription = null,
            modifier = Modifier.size(56.dp),
            tint = MaterialTheme.colorScheme.primary,
        )
        Spacer(Modifier.height(16.dp))
        Text("Inventory Import", style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)
        Spacer(Modifier.height(8.dp))
        Text(
            "CSV inventory import is not yet available in the setup wizard. " +
            "You can import inventory later via Settings → Import.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(24.dp))
        // TODO: Wire file-picker when MultipartUploadWorker supports CSV import.
        OutlinedButton(onClick = { onDataChange(mapOf("skipped" to "true")) }) {
            Text("Skip for now")
        }
    }
}
