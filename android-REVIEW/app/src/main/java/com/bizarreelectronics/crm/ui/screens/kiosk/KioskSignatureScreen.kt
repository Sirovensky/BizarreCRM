package com.bizarreelectronics.crm.ui.screens.kiosk

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.R
import com.bizarreelectronics.crm.ui.components.SignaturePad
import com.bizarreelectronics.crm.ui.components.SignatureStroke
import com.bizarreelectronics.crm.ui.components.isSignatureValid
import com.bizarreelectronics.crm.ui.components.renderSignatureBitmap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import android.util.Base64

/**
 * §57.3 Customer-facing signature screen.
 *
 * The device is physically flipped toward the customer.  The screen shows only
 * the signature pad and an "I agree" confirm button.  The navigation back-arrow
 * is intentionally absent so the customer cannot navigate deeper into the app.
 *
 * Staff cannot back out — the only way to leave is the confirm CTA or the
 * manager-PIN exit route ([onExitRequest]).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun KioskSignatureScreen(
    customerName: String,
    onSignatureConfirmed: () -> Unit,
    onExitRequest: () -> Unit,
    viewModel: KioskViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()
    val scope = rememberCoroutineScope()
    var strokes by remember { mutableStateOf<List<SignatureStroke>>(emptyList()) }

    // Navigate forward once signature is confirmed
    LaunchedEffect(state.signatureCaptured) {
        if (state.signatureCaptured) {
            onSignatureConfirmed()
        }
    }

    // Pause inactivity timer while customer is on this screen
    LaunchedEffect(Unit) {
        viewModel.pauseInactivity()
    }

    Scaffold(
        topBar = {
            // §57.3: no navigation icon — staff cannot back out of the signature screen.
            TopAppBar(
                title = {
                    Text(
                        stringResource(R.string.kiosk_signature_title),
                        style = MaterialTheme.typography.titleLarge,
                    )
                },
            )
        },
    ) { paddingValues ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues),
            contentAlignment = Alignment.Center,
        ) {
            Column(
                modifier = Modifier
                    .widthIn(max = 560.dp)
                    .fillMaxWidth()
                    .padding(horizontal = 24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Text(
                    stringResource(R.string.kiosk_signature_headline),
                    style = MaterialTheme.typography.headlineSmall,
                    textAlign = TextAlign.Center,
                )

                Text(
                    stringResource(R.string.kiosk_signature_terms_summary),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )

                HorizontalDivider()

                OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            stringResource(R.string.kiosk_signature_pad_label),
                            style = MaterialTheme.typography.labelLarge,
                        )
                        SignaturePad(
                            strokes = strokes,
                            onStrokesChanged = { updated ->
                                strokes = updated
                                // Pause inactivity while the customer is drawing
                                viewModel.pauseInactivity()
                            },
                            modifier = Modifier
                                .fillMaxWidth()
                                .semantics { contentDescription = "Customer signature pad" },
                            placeholder = stringResource(R.string.kiosk_signature_placeholder),
                        )
                        Text(
                            customerName,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.fillMaxWidth(),
                            textAlign = TextAlign.End,
                        )
                    }
                }

                FilledTonalButton(
                    onClick = {
                        scope.launch {
                            val base64 = if (isSignatureValid(strokes)) {
                                withContext(Dispatchers.Default) {
                                    val bmp = renderSignatureBitmap(strokes, 800, 300)
                                    val out = ByteArrayOutputStream()
                                    bmp.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, out)
                                    "data:image/png;base64," + Base64.encodeToString(
                                        out.toByteArray(),
                                        Base64.NO_WRAP,
                                    )
                                }
                            } else {
                                // Allow confirming even without a signature (blank waiver)
                                "blank"
                            }
                            viewModel.onSignatureCaptured(base64)
                        }
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .semantics { contentDescription = "Confirm signature and finish" },
                ) {
                    Text(stringResource(R.string.kiosk_signature_confirm_cta))
                }
            }
        }
    }
}
