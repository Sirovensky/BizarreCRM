package com.bizarreelectronics.crm.ui.screens.expenses

import androidx.compose.foundation.Image
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import coil3.compose.rememberAsyncImagePainter
import com.bizarreelectronics.crm.ui.components.shared.BrandCard
import com.bizarreelectronics.crm.ui.components.shared.BrandSkeleton
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.screens.expenses.components.ExpenseApprovalBar
import com.bizarreelectronics.crm.util.formatAsMoney

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExpenseDetailScreen(
    onBack: () -> Unit,
    onEdit: (Long) -> Unit,
    viewModel: ExpenseDetailViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.approvalSuccess) {
        val msg = state.approvalSuccess
        if (msg != null) {
            snackbarHostState.showSnackbar(msg)
            viewModel.clearApprovalMessage()
        }
    }
    LaunchedEffect(state.approvalError) {
        val msg = state.approvalError
        if (msg != null) {
            snackbarHostState.showSnackbar(msg)
            viewModel.clearApprovalMessage()
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            BrandTopAppBar(
                title = "Expense Detail",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    val expense = state.expense
                    if (expense != null) {
                        IconButton(onClick = { onEdit(expense.id) }) {
                            Icon(Icons.Default.Edit, contentDescription = "Edit expense")
                        }
                    }
                },
            )
        },
        bottomBar = {
            val expense = state.expense
            if (expense != null) {
                // approval status stub — ExpenseDetail has no status field yet; treat null as "pending"
                val status = "pending"
                ExpenseApprovalBar(
                    isApprover = state.isApprover,
                    currentStatus = status,
                    isLoading = state.isApprovalLoading,
                    onApprove = { comment -> viewModel.approve(comment) },
                    onReject = { comment -> viewModel.reject(comment) },
                )
            }
        },
    ) { padding ->
        when {
            state.isLoading -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .padding(16.dp),
                ) {
                    BrandSkeleton(rows = 8, modifier = Modifier.fillMaxWidth())
                }
            }
            state.error != null -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    ErrorState(
                        message = state.error ?: "Unknown error",
                        onRetry = { viewModel.load() },
                    )
                }
            }
            state.expense != null -> {
                val expense = state.expense!!
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    // Receipt photo — full-width with pinch-zoom
                    if (!expense.receiptPath.isNullOrBlank()) {
                        var scale by remember { mutableStateOf(1f) }
                        var offsetX by remember { mutableStateOf(0f) }
                        var offsetY by remember { mutableStateOf(0f) }

                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(240.dp)
                                .pointerInput(Unit) {
                                    detectTransformGestures { _, pan, zoom, _ ->
                                        scale = (scale * zoom).coerceIn(1f, 5f)
                                        offsetX += pan.x
                                        offsetY += pan.y
                                    }
                                },
                        ) {
                            Image(
                                painter = rememberAsyncImagePainter(expense.receiptPath),
                                contentDescription = "Receipt photo",
                                modifier = Modifier
                                    .fillMaxSize()
                                    .graphicsLayer(
                                        scaleX = scale,
                                        scaleY = scale,
                                        translationX = offsetX,
                                        translationY = offsetY,
                                    ),
                                contentScale = ContentScale.Fit,
                            )
                        }
                    }

                    // Detail fields card
                    BrandCard(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp),
                    ) {
                        Column(
                            modifier = Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            DetailRow(label = "Category", value = expense.category ?: "-")
                            DetailRow(
                                label = "Amount",
                                value = expense.amount
                                    ?.let { ((it * 100).toLong()).formatAsMoney() }
                                    ?: "-",
                                highlight = true,
                            )
                            DetailRow(label = "Date", value = expense.date?.take(10) ?: "-")
                            DetailRow(
                                label = "Vendor / Description",
                                value = expense.description?.takeIf { it.isNotBlank() } ?: "-",
                            )
                            DetailRow(label = "Recorded by", value = expense.userName)
                            DetailRow(label = "Created", value = expense.createdAt?.take(10) ?: "-")
                            DetailRow(label = "Updated", value = expense.updatedAt?.take(10) ?: "-")
                        }
                    }

                    Spacer(Modifier.height(16.dp))
                }
            }
        }
    }
}

@Composable
private fun DetailRow(
    label: String,
    value: String,
    highlight: Boolean = false,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.Top,
    ) {
        Text(
            label,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
        )
        Text(
            value,
            style = if (highlight) {
                MaterialTheme.typography.titleMedium
            } else {
                MaterialTheme.typography.bodyMedium
            },
            fontWeight = if (highlight) FontWeight.SemiBold else FontWeight.Normal,
            color = if (highlight) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.weight(1.5f),
        )
    }
}
