package com.bizarreelectronics.crm.ui.screens.payments

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.data.remote.api.PaymentLinkData
import com.bizarreelectronics.crm.ui.components.WaveDivider
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter

/**
 * §41.1 — Create a new payment link.
 * Shows form: amount + memo + customer + expiry → POST /payment-links.
 * On success displays QR code + copy / share actions.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaymentLinkScreen(
    onBack: () -> Unit,
    onCreated: ((PaymentLinkData) -> Unit)? = null,
    viewModel: PaymentLinkViewModel = hiltViewModel(),
) {
    val state by viewModel.createState.collectAsState()
    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }

    // Show created-link sheet as a bottom sheet once the link is ready
    if (state.createdLink != null) {
        PaymentLinkSuccessSheet(
            link = state.createdLink!!,
            onDismiss = { viewModel.clearCreatedLink(); onBack() },
            onShare = { url -> shareUrl(context, url) },
            onCopy = { url -> copyToClipboard(context, url) },
        )
        return
    }

    LaunchedEffect(state.error) {
        state.error?.let { snackbarHostState.showSnackbar(it); viewModel.clearError() }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            Column {
                BrandTopAppBar(
                    title = "New Payment Link",
                    navigationIcon = {
                        IconButton(onClick = onBack) {
                            Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                        }
                    },
                )
                WaveDivider()
            }
        },
    ) { padding ->
        if (state.notConfigured) {
            NotConfiguredState(modifier = Modifier.padding(padding))
            return@Scaffold
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Spacer(modifier = Modifier.height(8.dp))

            // Amount
            OutlinedTextField(
                value = state.amountText,
                onValueChange = viewModel::onAmountChanged,
                label = { Text("Amount (USD)") },
                leadingIcon = { Icon(Icons.Default.AttachMoney, contentDescription = null) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                singleLine = true,
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics { contentDescription = "Payment amount in dollars" },
            )

            // Memo
            OutlinedTextField(
                value = state.memo,
                onValueChange = viewModel::onMemoChanged,
                label = { Text("Memo (optional)") },
                placeholder = { Text("e.g. iPhone 14 screen repair") },
                singleLine = false,
                maxLines = 3,
                modifier = Modifier.fillMaxWidth(),
            )

            // Expiry picker
            ExpirySelector(
                days = state.expiresInDays,
                onDaysChanged = viewModel::onExpiryDaysChanged,
            )

            // Partial payment toggle
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("Allow partial payment", modifier = Modifier.weight(1f))
                Switch(
                    checked = state.partialAllowed,
                    onCheckedChange = viewModel::onPartialAllowedChanged,
                )
            }

            Spacer(modifier = Modifier.height(8.dp))

            // Create button
            Button(
                onClick = viewModel::createLink,
                enabled = !state.isLoading && state.amountText.isNotBlank(),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp),
            ) {
                if (state.isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary,
                    )
                } else {
                    Icon(Icons.Default.Link, contentDescription = null, modifier = Modifier.size(20.dp))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Create Payment Link", fontWeight = FontWeight.SemiBold)
                }
            }

            Spacer(modifier = Modifier.height(16.dp))
        }
    }
}

// ── Success sheet ─────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PaymentLinkSuccessSheet(
    link: PaymentLinkData,
    onDismiss: () -> Unit,
    onShare: (String) -> Unit,
    onCopy: (String) -> Unit,
) {
    val url = link.short_url.ifBlank { link.url }
    val qrBitmap = remember(url) { generateQrBitmap(url, 512) }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp, vertical = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("Payment Link Created", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)

            // QR code
            if (qrBitmap != null) {
                Image(
                    bitmap = qrBitmap.asImageBitmap(),
                    contentDescription = "QR code for payment link",
                    modifier = Modifier.size(200.dp),
                )
            }

            // URL
            Text(
                url,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.primary,
                maxLines = 2,
            )

            // Action buttons
            Row(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                OutlinedButton(
                    onClick = { onCopy(url) },
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(Icons.Default.ContentCopy, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(6.dp))
                    Text("Copy")
                }
                Button(
                    onClick = { onShare(url) },
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(Icons.Default.Share, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(6.dp))
                    Text("Share")
                }
            }

            TextButton(onClick = onDismiss, modifier = Modifier.padding(bottom = 8.dp)) {
                Text("Done")
            }
        }
    }
}

// ── Expiry selector ───────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ExpirySelector(days: Int, onDaysChanged: (Int) -> Unit) {
    val options = listOf(1 to "24 hours", 3 to "3 days", 7 to "7 days", 14 to "2 weeks", 30 to "30 days")
    var expanded by remember { mutableStateOf(false) }
    val label = options.firstOrNull { it.first == days }?.second ?: "$days days"

    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
        OutlinedTextField(
            value = label,
            onValueChange = {},
            readOnly = true,
            label = { Text("Expires in") },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor(),
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEach { (d, lbl) ->
                DropdownMenuItem(
                    text = { Text(lbl) },
                    onClick = { onDaysChanged(d); expanded = false },
                )
            }
        }
    }
}

// ── Not-configured state ──────────────────────────────────────────────────────

@Composable
private fun NotConfiguredState(modifier: Modifier = Modifier) {
    Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(
                Icons.Default.LinkOff,
                contentDescription = null,
                modifier = Modifier.size(48.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text("Payment links not configured on this server", style = MaterialTheme.typography.bodyLarge)
            Text(
                "Ask your admin to enable the payment-links feature.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

private fun generateQrBitmap(content: String, sizePx: Int): Bitmap? = runCatching {
    val hints = mapOf(EncodeHintType.MARGIN to 1)
    val bits = QRCodeWriter().encode(content, BarcodeFormat.QR_CODE, sizePx, sizePx, hints)
    val bmp = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.RGB_565)
    for (x in 0 until sizePx) for (y in 0 until sizePx) {
        bmp.setPixel(x, y, if (bits[x, y]) Color.BLACK else Color.WHITE)
    }
    bmp
}.getOrNull()

private fun copyToClipboard(context: Context, text: String) {
    val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    cm.setPrimaryClip(ClipData.newPlainText("Payment link", text))
}

private fun shareUrl(context: Context, url: String) {
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_TEXT, url)
        putExtra(Intent.EXTRA_SUBJECT, "Payment request")
    }
    context.startActivity(Intent.createChooser(intent, "Share payment link"))
}
