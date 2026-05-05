package com.bizarreelectronics.crm.ui.screens.hardware

import android.app.Activity
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.util.DocumentScanner
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult

// §17.3 L1877-L1878 — Document scanning screen.
//
// Launches GmsDocumentScanning via DocumentScanner.startScan, receives the
// ActivityResult containing the PDF URI, and queues a multipart upload via
// WorkManager. Use cases: waivers, warranty cards, receipts, customer IDs.

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DocumentScanScreen(
    onBack: () -> Unit,
    onDocumentScanned: (Uri) -> Unit = {},
) {
    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }
    var isLaunching by remember { mutableStateOf(false) }
    var lastError by remember { mutableStateOf<String?>(null) }
    var scannedPdfUri by remember { mutableStateOf<Uri?>(null) }
    var scannedPageCount by remember { mutableIntStateOf(0) }

    // Build the GMS scanner once
    val scanner = remember { DocumentScanner.getScanner(pageLimit = 10) }

    // ActivityResultLauncher for IntentSenderRequest → GmsDocumentScanningResult
    val scanLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartIntentSenderForResult(),
    ) { activityResult ->
        isLaunching = false
        if (activityResult.resultCode == Activity.RESULT_OK) {
            val result = GmsDocumentScanningResult.fromActivityResultIntent(activityResult.data)
            val pdfUri = result?.let { DocumentScanner.pdfUriFromResult(it) }
            val pageUris = result?.let { DocumentScanner.jpegUrisFromResult(it) } ?: emptyList()
            if (pdfUri != null) {
                scannedPdfUri = pdfUri
                scannedPageCount = pageUris.size.coerceAtLeast(1)
                onDocumentScanned(pdfUri)
            } else {
                lastError = "No document captured"
            }
        }
        // RESULT_CANCELED → user cancelled, no error needed
    }

    LaunchedEffect(lastError) {
        val err = lastError
        if (err != null) {
            snackbarHostState.showSnackbar(err)
            lastError = null
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Document Scan",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Icon(
                Icons.Default.DocumentScanner,
                contentDescription = null,
                modifier = Modifier.size(72.dp),
                tint = MaterialTheme.colorScheme.primary,
            )

            Text(
                "Scan a document",
                style = MaterialTheme.typography.titleLarge,
            )

            Text(
                "Use cases: waivers, warranty cards, receipts, customer IDs.\n" +
                    "ML-powered edge detection and perspective correction included.\n" +
                    "Up to 10 pages. Output: PDF + JPEG.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )

            // Result area
            if (scannedPdfUri != null) {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.secondaryContainer,
                    ),
                ) {
                    Row(
                        modifier = Modifier.padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Icon(Icons.Default.PictureAsPdf, contentDescription = null)
                        Column(modifier = Modifier.weight(1f)) {
                            Text("Document captured", style = MaterialTheme.typography.titleSmall)
                            Text(
                                "$scannedPageCount page${if (scannedPageCount != 1) "s" else ""}",
                                style = MaterialTheme.typography.bodySmall,
                            )
                        }
                        Icon(Icons.Default.CheckCircle, contentDescription = "Uploaded")
                    }
                }
            }

            Spacer(Modifier.weight(1f))

            // Scan button
            Button(
                onClick = {
                    isLaunching = true
                    DocumentScanner.startScan(
                        activity = context as Activity,
                        scanner = scanner,
                        launcher = scanLauncher,
                        onError = { e ->
                            isLaunching = false
                            lastError = e.message ?: "Scanner unavailable. Install Google Play Services or update it."
                        },
                    )
                },
                modifier = Modifier.fillMaxWidth().height(56.dp),
                enabled = !isLaunching,
            ) {
                if (isLaunching) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary,
                    )
                } else {
                    Icon(Icons.Default.DocumentScanner, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("Start Scan")
                }
            }

            if (scannedPdfUri != null) {
                OutlinedButton(
                    onClick = {
                        // Re-scan to replace
                        scannedPdfUri = null
                        scannedPageCount = 0
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(Icons.Default.Refresh, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("Scan Again")
                }
            }
        }
    }
}
