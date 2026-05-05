package com.bizarreelectronics.crm.ui.screens.stocktake

import androidx.compose.runtime.*
import androidx.hilt.navigation.compose.hiltViewModel

/**
 * §60 Inventory Stocktake — root screen.
 *
 * Owns [StocktakeViewModel] and routes between the three phase screens:
 *   • [StocktakeStartScreen]   — DRAFT    (session not yet started)
 *   • [StocktakeCountScreen]   — ACTIVE   (operator is counting)
 *   • [StocktakeCommittedScreen] — COMMITTED (count submitted)
 *
 * Nav arguments:
 *   [onBack]     — pops back to inventory list when in DRAFT or COMMITTED.
 *   [onScanClick] — navigates to BarcodeScanScreen; result arrives via
 *                  savedStateHandle key "stocktake_barcode".
 */
@Composable
fun StocktakeScreen(
    onBack: () -> Unit,
    onScanClick: () -> Unit,
    /** Called when a barcode result arrives from BarcodeScanScreen. */
    scannedBarcode: String?,
    onBarcodeConsumed: () -> Unit,
    viewModel: StocktakeViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()

    // Consume any barcode delivered from the scanner screen.
    LaunchedEffect(scannedBarcode) {
        if (!scannedBarcode.isNullOrBlank()) {
            viewModel.onBarcodeScanned(scannedBarcode)
            onBarcodeConsumed()
        }
    }

    when (state.phase) {
        StocktakePhase.DRAFT -> {
            StocktakeStartScreen(
                isOffline = state.isOffline,
                onStartSession = { viewModel.startSession() },
                onBack = onBack,
            )
        }

        StocktakePhase.ACTIVE -> {
            StocktakeCountScreen(
                uiState = state,
                onScanClick = onScanClick,
                onSearchQueryChanged = { q -> viewModel.onSearchQueryChanged(q) },
                onAddItemFromSearch = { item ->
                    viewModel.setCount(
                        itemId = item.id,
                        itemName = item.name,
                        sku = item.sku,
                        upcCode = item.upcCode,
                        systemQty = item.inStock,
                        countedQty = 1,
                    )
                    viewModel.clearSearch()
                },
                onQuantityChanged = { itemId, qty ->
                    val line = state.lines.firstOrNull { it.itemId == itemId }
                    if (line != null) {
                        viewModel.setCount(
                            itemId = line.itemId,
                            itemName = line.itemName,
                            sku = line.sku,
                            upcCode = line.upcCode,
                            systemQty = line.systemQty,
                            countedQty = qty,
                        )
                    }
                },
                onRemoveLine = { itemId -> viewModel.removeLine(itemId) },
                onCommitClick = { viewModel.commitSession() },
                onDiscardClick = {
                    viewModel.discardSession()
                    onBack()
                },
                onBack = onBack,
            )
        }

        StocktakePhase.COMMITTED -> {
            StocktakeCommittedScreen(
                lines = state.lines,
                approvalPending = state.approvalPending,
                sessionId = state.sessionId,
                onDone = {
                    viewModel.discardSession()
                    onBack()
                },
            )
        }
    }
}
