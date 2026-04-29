package com.bizarreelectronics.crm.ui.screens.performance

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Assessment
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.ConfirmDialog
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import java.time.LocalDate

private val CYCLE_OPTIONS = listOf("Q1-2026", "Q2-2026", "Q3-2026", "Q4-2026", "annual-2025", "annual-2026")

/** Human-readable descriptor for each star level (1–5). */
private val RATING_DESCRIPTORS = mapOf(
    1 to "Poor",
    2 to "Fair",
    3 to "Good",
    4 to "Great",
    5 to "Excellent",
)

/** A draft review pending the "Approve review" confirmation step. */
private data class PendingReview(
    val employeeId: Long,
    val cycle: String,
    val ratings: ReviewRatings,
    val comments: String,
    val date: String,
)

/**
 * §48.2 Performance Reviews screen.
 *
 * Staff: read-only list of their own past reviews.
 * Manager/Admin: full list + FAB to write a new review for any employee.
 * Uses [ConfirmDialog] before submitting ("Approve review").
 *
 * 404-tolerant: shows "not configured on this server" empty state.
 *
 * @param onBack Navigate back.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PerformanceReviewScreen(
    onBack: () -> Unit,
    viewModel: PerformanceReviewViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    /** Holds a completed form draft awaiting manager confirmation before submitting. */
    var pendingReview by remember { mutableStateOf<PendingReview?>(null) }

    LaunchedEffect(state.toastMessage) {
        val msg = state.toastMessage
        if (!msg.isNullOrBlank()) {
            Toast.makeText(context, msg, Toast.LENGTH_SHORT).show()
            viewModel.clearToast()
        }
    }

    Scaffold(
        topBar = {
            BrandTopAppBar(
                title = "Performance Reviews",
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
        floatingActionButton = {
            if (state.isManager) {
                FloatingActionButton(onClick = { viewModel.showCreateDialog() }) {
                    Icon(Icons.Default.Add, contentDescription = "New review")
                }
            }
        },
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            when {
                state.isLoading -> CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))

                state.serverUnsupported -> EmptyState(
                    icon = Icons.Default.Assessment,
                    title = "Reviews not available",
                    subtitle = "Performance reviews are not configured on this server.",
                )

                state.error != null -> ErrorState(
                    message = state.error!!,
                    onRetry = { viewModel.refresh() },
                )

                state.reviews.isEmpty() -> EmptyState(
                    icon = Icons.Default.Assessment,
                    title = "No reviews yet",
                    subtitle = if (state.isManager) "Tap + to write the first review."
                    else "No performance reviews on file.",
                )

                else -> LazyColumn(
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier.fillMaxSize(),
                ) {
                    items(state.reviews, key = { it.id }) { review ->
                        ReviewCard(review = review)
                    }
                }
            }
        }
    }

    // ── Create review dialog (shows form) ────────────────────────────────────
    if (state.showCreateDialog) {
        CreateReviewDialog(
            onDismiss = { viewModel.dismissCreateDialog() },
            onConfirm = { empId, cycle, ratings, comments, date ->
                // Dismiss the form and open the confirmation step
                viewModel.dismissCreateDialog()
                pendingReview = PendingReview(empId, cycle, ratings, comments, date)
            },
        )
    }

    // ── Approve review confirmation ───────────────────────────────────────────
    val draft = pendingReview
    if (draft != null) {
        ConfirmDialog(
            title = "Submit Review",
            message = "Submit this performance review for employee #${draft.employeeId}? " +
                "Overall rating: ${RATING_DESCRIPTORS[draft.ratings.overall] ?: draft.ratings.overall}/5.",
            confirmLabel = "Submit",
            isDestructive = false,
            onConfirm = {
                viewModel.submitReview(
                    draft.employeeId,
                    draft.cycle,
                    draft.ratings,
                    draft.comments,
                    draft.date,
                )
                pendingReview = null
            },
            onDismiss = { pendingReview = null },
        )
    }
}

@Composable
private fun ReviewCard(
    review: PerformanceReview,
    modifier: Modifier = Modifier,
) {
    Card(modifier = modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = review.employeeName.ifBlank { "Employee #${review.employeeId}" },
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = review.cycle,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
            Text(
                text = "Reviewed by ${review.reviewerName} on ${review.reviewDate.take(10)}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(8.dp))
            HorizontalDivider()
            Spacer(Modifier.height(8.dp))
            RatingRow("Quality", review.ratings.quality)
            RatingRow("Speed", review.ratings.speed)
            RatingRow("Attitude", review.ratings.attitude)
            RatingRow("Teamwork", review.ratings.teamwork)
            RatingRow("Overall", review.ratings.overall)
            if (review.managerComments.isNotBlank()) {
                Spacer(Modifier.height(8.dp))
                Text(
                    text = review.managerComments,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun RatingRow(label: String, value: Int) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.weight(1f),
        )
        Row {
            (1..5).forEach { star ->
                Icon(
                    imageVector = if (star <= value) Icons.Default.Star else Icons.Default.StarBorder,
                    contentDescription = null,
                    tint = if (star <= value) MaterialTheme.colorScheme.primary
                    else MaterialTheme.colorScheme.outlineVariant,
                )
            }
        }
    }
}

@Composable
private fun StarRatingInput(
    label: String,
    value: Int,
    onValueChange: (Int) -> Unit,
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(label, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
            Row {
                (1..5).forEach { star ->
                    IconButton(onClick = { onValueChange(star) }) {
                        Icon(
                            imageVector = if (star <= value) Icons.Default.Star else Icons.Default.StarBorder,
                            contentDescription = "Rate $label $star out of 5",
                            tint = if (star <= value) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.outlineVariant,
                        )
                    }
                }
            }
        }
        if (value > 0) {
            Text(
                text = RATING_DESCRIPTORS[value] ?: "",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.align(Alignment.End),
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CreateReviewDialog(
    onDismiss: () -> Unit,
    onConfirm: (employeeId: Long, cycle: String, ratings: ReviewRatings, comments: String, date: String) -> Unit,
) {
    var employeeIdText by remember { mutableStateOf("") }
    var cycle by remember { mutableStateOf(CYCLE_OPTIONS.first()) }
    var quality by remember { mutableIntStateOf(0) }
    var speed by remember { mutableIntStateOf(0) }
    var attitude by remember { mutableIntStateOf(0) }
    var teamwork by remember { mutableIntStateOf(0) }
    var overall by remember { mutableIntStateOf(0) }
    var comments by remember { mutableStateOf("") }
    val today = remember { LocalDate.now().toString() }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("New Performance Review") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                OutlinedTextField(
                    value = employeeIdText,
                    onValueChange = { employeeIdText = it.filter { c -> c.isDigit() } },
                    label = { Text("Employee ID") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = cycle,
                    onValueChange = { cycle = it },
                    label = { Text("Cycle (e.g. Q2-2026)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(4.dp))
                StarRatingInput("Quality", quality) { quality = it }
                StarRatingInput("Speed", speed) { speed = it }
                StarRatingInput("Attitude", attitude) { attitude = it }
                StarRatingInput("Teamwork", teamwork) { teamwork = it }
                StarRatingInput("Overall", overall) { overall = it }
                Spacer(Modifier.height(4.dp))
                OutlinedTextField(
                    value = comments,
                    onValueChange = { comments = it },
                    label = { Text("Comments") },
                    minLines = 2,
                    maxLines = 4,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(onClick = {
                val empId = employeeIdText.toLongOrNull() ?: 0L
                val ratings = ReviewRatings(quality, speed, attitude, teamwork, overall)
                onConfirm(empId, cycle, ratings, comments, today)
            }) { Text("Submit") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}
