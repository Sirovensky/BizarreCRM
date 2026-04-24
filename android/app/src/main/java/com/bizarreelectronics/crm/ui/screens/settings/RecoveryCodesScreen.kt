package com.bizarreelectronics.crm.ui.screens.settings

// §2.19 L427-L438 — Recovery Codes settings screen.
//
// States rendered:
//   Idle             → description text + remaining count + "Regenerate codes" button.
//   RequiringPassword → PasswordField + "Confirm" button + "Cancel" link.
//   Regenerating      → centered CircularProgressIndicator.
//   Generated(codes)  → warning banner + BackupCodesDisplay (reused from §2.4)
//                       + Print action + Email-to-self action.
//   NotSupported      → informational card ("server version too old").
//   Error(AppError)   → inline error card with Retry (→ RequiringPassword) + Dismiss.
//
// Print: renders codes as a Bitmap via Canvas, passes to PrintHelper.printBitmap().
//        Falls back gracefully when PrintHelper is unavailable (pre-KitKat or
//        no print services).
// Email: launches ACTION_SENDTO with mailto: URI pre-filled with the current
//        user's email (from UserDto stored in AuthPreferences).

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.net.Uri
import android.os.Bundle
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.PrintManager
import android.util.Log
import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Print
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.screens.auth.BackupCodesDisplay

private const val TAG = "RecoveryCodesScreen"

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecoveryCodesScreen(
    onBack: () -> Unit,
    userEmail: String? = null,
    viewModel: RecoveryCodesViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsState()
    val context = LocalContext.current

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Recovery Codes",
                navigationIcon = {
                    IconButton(onClick = {
                        viewModel.dismiss()
                        onBack()
                    }) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                        )
                    }
                },
            )
        },
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            when (val state = uiState) {
                is RecoveryCodesUiState.Idle -> {
                    IdleContent(
                        onRegenerate = { viewModel.requestRegenerate() },
                    )
                }

                is RecoveryCodesUiState.RequiringPassword -> {
                    PasswordPromptContent(
                        onConfirm = { password -> viewModel.regenerate(password) },
                        onCancel = { viewModel.dismiss() },
                    )
                }

                is RecoveryCodesUiState.Regenerating -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator()
                    }
                }

                is RecoveryCodesUiState.Generated -> {
                    GeneratedContent(
                        codes = state.codes,
                        userEmail = userEmail,
                        context = context,
                        onDismiss = { viewModel.confirmSaved() },
                    )
                }

                is RecoveryCodesUiState.NotSupported -> {
                    NotSupportedContent()
                }

                is RecoveryCodesUiState.Error -> {
                    ErrorContent(
                        message = state.error.message,
                        onRetry = { viewModel.requestRegenerate() },
                        onDismiss = { viewModel.dismiss() },
                    )
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Idle state content
// ---------------------------------------------------------------------------

@Composable
private fun IdleContent(onRegenerate: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    "About recovery codes",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    "Recovery codes are one-time passcodes you can use if you lose access " +
                        "to your authenticator app. Keep them in a safe place — once used, " +
                        "each code is gone.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        Button(
            onClick = onRegenerate,
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(
                containerColor = MaterialTheme.colorScheme.error,
                contentColor = MaterialTheme.colorScheme.onError,
            ),
        ) {
            Text("Regenerate codes")
        }

        Text(
            "Regenerating invalidates all existing codes immediately.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

// ---------------------------------------------------------------------------
// Password prompt state content
// ---------------------------------------------------------------------------

@Composable
private fun PasswordPromptContent(
    onConfirm: (String) -> Unit,
    onCancel: () -> Unit,
) {
    var password by remember { mutableStateOf("") }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            "Confirm your password",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            "For security, enter your current account password to generate new recovery codes. " +
                "All existing codes will be invalidated immediately.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        OutlinedTextField(
            value = password,
            onValueChange = { password = it },
            label = { Text("Current password") },
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )

        Button(
            onClick = { onConfirm(password) },
            enabled = password.isNotBlank(),
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(
                containerColor = MaterialTheme.colorScheme.error,
                contentColor = MaterialTheme.colorScheme.onError,
            ),
        ) {
            Text("Confirm and regenerate")
        }

        TextButton(
            onClick = onCancel,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Cancel")
        }
    }
}

// ---------------------------------------------------------------------------
// Generated state content
// ---------------------------------------------------------------------------

@Composable
private fun GeneratedContent(
    codes: List<String>,
    userEmail: String?,
    context: Context,
    onDismiss: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Warning banner
        Surface(
            color = MaterialTheme.colorScheme.errorContainer,
            shape = MaterialTheme.shapes.small,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Row(
                modifier = Modifier.padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(
                    Icons.Default.Warning,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                    tint = MaterialTheme.colorScheme.onErrorContainer,
                )
                Text(
                    "Save these — they won't show again. " +
                        "Losing them and your authenticator = permanent lockout.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onErrorContainer,
                )
            }
        }

        // Print + Email action row
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            OutlinedButton(
                onClick = { printCodes(context, codes) },
                modifier = Modifier.weight(1f),
            ) {
                Icon(
                    Icons.Default.Print,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp),
                )
                Spacer(Modifier.width(6.dp))
                Text("Print")
            }

            if (userEmail != null) {
                OutlinedButton(
                    onClick = { emailCodesToSelf(context, userEmail, codes) },
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(
                        Icons.Default.Email,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                    )
                    Spacer(Modifier.width(6.dp))
                    Text("Email to self")
                }
            }
        }

        // Reuse BackupCodesDisplay from §2.4 — FlowRow chips + Copy all + checkbox gate + Done CTA
        BackupCodesDisplay(
            codes = codes,
            onDismiss = onDismiss,
        )
    }
}

// ---------------------------------------------------------------------------
// NotSupported state content
// ---------------------------------------------------------------------------

@Composable
private fun NotSupportedContent() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant,
            ),
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    "Not available",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    "Recovery codes management isn't available on this server version. " +
                        "Contact your administrator to update the server.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Error state content
// ---------------------------------------------------------------------------

@Composable
private fun ErrorContent(
    message: String,
    onRetry: () -> Unit,
    onDismiss: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.errorContainer,
            ),
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    "Something went wrong",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onErrorContainer,
                )
                Text(
                    message,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onErrorContainer,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = onRetry) { Text("Retry") }
                    TextButton(onClick = onDismiss) { Text("Dismiss") }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Print helper — renders codes as a Bitmap via Canvas, then prints via the
// native android.print.PrintManager (no external dependency required).
// Falls back to a toast when no print service is available.
// SECURITY: codes are never passed to any logging call here.
// ---------------------------------------------------------------------------

private fun printCodes(context: Context, codes: List<String>) {
    val printManager = context.getSystemService(Context.PRINT_SERVICE) as? PrintManager
    if (printManager == null) {
        Toast.makeText(context, "Printing is not available on this device. Copy and save manually.", Toast.LENGTH_LONG).show()
        return
    }
    try {
        val bitmap = renderCodesBitmap(codes)
        val adapter = BitmapPrintDocumentAdapter(bitmap)
        val attrs = PrintAttributes.Builder()
            .setMediaSize(PrintAttributes.MediaSize.NA_LETTER)
            .setResolution(PrintAttributes.Resolution("default", "Default", 300, 300))
            .setMinMargins(PrintAttributes.Margins.NO_MARGINS)
            .build()
        printManager.print("Bizarre CRM recovery codes", adapter, attrs)
    } catch (e: Exception) {
        Log.w(TAG, "printCodes failed", e)
        Toast.makeText(context, "Print failed. Copy and save manually.", Toast.LENGTH_LONG).show()
    }
}

/**
 * Minimal [PrintDocumentAdapter] that wraps a pre-rendered [Bitmap].
 * Writes the bitmap as a PDF page using [android.graphics.pdf.PdfDocument].
 * One page, A4/letter-sized, black-on-white.
 */
private class BitmapPrintDocumentAdapter(private val bitmap: Bitmap) : PrintDocumentAdapter() {

    override fun onLayout(
        oldAttributes: PrintAttributes?,
        newAttributes: PrintAttributes,
        cancellationSignal: CancellationSignal?,
        callback: LayoutResultCallback,
        extras: Bundle?,
    ) {
        if (cancellationSignal?.isCanceled == true) {
            callback.onLayoutCancelled()
            return
        }
        val info = PrintDocumentInfo.Builder("recovery_codes")
            .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
            .setPageCount(1)
            .build()
        callback.onLayoutFinished(info, oldAttributes != newAttributes)
    }

    override fun onWrite(
        pages: Array<out PageRange>?,
        destination: ParcelFileDescriptor,
        cancellationSignal: CancellationSignal?,
        callback: WriteResultCallback,
    ) {
        if (cancellationSignal?.isCanceled == true) {
            callback.onWriteCancelled()
            return
        }
        try {
            val pdf = android.graphics.pdf.PdfDocument()
            val pageInfo = android.graphics.pdf.PdfDocument.PageInfo.Builder(
                bitmap.width, bitmap.height, 1
            ).create()
            val page = pdf.startPage(pageInfo)
            page.canvas.drawBitmap(bitmap, 0f, 0f, null)
            pdf.finishPage(page)
            java.io.FileOutputStream(destination.fileDescriptor).use { fos ->
                pdf.writeTo(fos)
            }
            pdf.close()
            callback.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
        } catch (e: Exception) {
            callback.onWriteFailed(e.message)
        }
    }
}

/**
 * Renders recovery codes onto a plain white Bitmap using Canvas.
 * Font is monospace-equivalent via Paint.ANTI_ALIAS_FLAG.
 * Black text on white background — suitable for plain-paper printing.
 * SECURITY: bitmap is not persisted to disk here.
 */
private fun renderCodesBitmap(codes: List<String>): Bitmap {
    val width = 800
    val lineHeight = 56
    val topPadding = 80
    val sidePadding = 60
    val titleHeight = 80
    val height = topPadding + titleHeight + codes.size * lineHeight + topPadding

    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    canvas.drawColor(Color.WHITE)

    val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.BLACK
        textSize = 36f
        isFakeBoldText = true
    }
    val codePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.BLACK
        textSize = 30f
        typeface = android.graphics.Typeface.MONOSPACE
    }
    val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.DKGRAY
        textSize = 22f
    }

    canvas.drawText("Bizarre CRM — Recovery Codes", sidePadding.toFloat(), topPadding.toFloat(), titlePaint)
    canvas.drawText("Keep these safe. Each code can only be used once.", sidePadding.toFloat(), (topPadding + 36).toFloat(), labelPaint)

    codes.forEachIndexed { index, code ->
        val y = topPadding + titleHeight + (index + 1) * lineHeight
        canvas.drawText("${index + 1}.  $code", sidePadding.toFloat(), y.toFloat(), codePaint)
    }

    return bitmap
}

// ---------------------------------------------------------------------------
// Email-to-self helper — launches ACTION_SENDTO with mailto: URI.
// Does NOT send the email itself; the user confirms in their email app.
// SECURITY: codes are included in the email body only at user's explicit request.
// ---------------------------------------------------------------------------

private fun emailCodesToSelf(context: Context, email: String, codes: List<String>) {
    val body = buildString {
        appendLine("Bizarre CRM — Recovery Codes")
        appendLine()
        appendLine("Keep these safe. Each code can only be used once.")
        appendLine()
        codes.forEachIndexed { index, code ->
            appendLine("${index + 1}. $code")
        }
        appendLine()
        appendLine("Generated by Bizarre CRM Android app.")
    }

    val intent = Intent(Intent.ACTION_SENDTO).apply {
        data = Uri.parse("mailto:")
        putExtra(Intent.EXTRA_EMAIL, arrayOf(email))
        putExtra(Intent.EXTRA_SUBJECT, "Bizarre CRM — Recovery Codes")
        putExtra(Intent.EXTRA_TEXT, body)
    }

    if (intent.resolveActivity(context.packageManager) != null) {
        context.startActivity(intent)
    } else {
        Toast.makeText(context, "No email app found. Copy and save codes manually.", Toast.LENGTH_LONG).show()
    }
}
