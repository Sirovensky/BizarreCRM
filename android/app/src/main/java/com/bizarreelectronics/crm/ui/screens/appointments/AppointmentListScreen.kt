package com.bizarreelectronics.crm.ui.screens.appointments

import android.widget.Toast
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.bizarreelectronics.crm.ui.components.shared.BrandTopAppBar
import com.bizarreelectronics.crm.ui.components.shared.EmptyState
import com.bizarreelectronics.crm.ui.components.shared.ErrorState
import com.bizarreelectronics.crm.ui.components.shared.SearchBar
import com.bizarreelectronics.crm.ui.screens.appointments.components.AppointmentAgendaView
import com.bizarreelectronics.crm.ui.screens.appointments.components.AppointmentDayView
import com.bizarreelectronics.crm.ui.screens.appointments.components.AppointmentMonthView
import com.bizarreelectronics.crm.ui.screens.appointments.components.AppointmentWeekView
import com.bizarreelectronics.crm.ui.screens.appointments.components.FilterChipRow
import java.time.LocalDate

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppointmentListScreen(
    onAppointmentClick: (Long) -> Unit,
    onCreateClick: () -> Unit,
    viewModel: AppointmentListViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    val listState = rememberLazyListState()

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
                title = "Appointments",
                actions = {
                    // Today button (L1424)
                    IconButton(
                        onClick = { viewModel.jumpToToday() },
                        modifier = Modifier.semantics {
                            contentDescription = "Jump to today"
                        },
                    ) {
                        Icon(Icons.Default.Today, contentDescription = null)
                    }
                    IconButton(onClick = onCreateClick) {
                        Icon(Icons.Default.Add, contentDescription = "New appointment")
                    }
                },
            )
        },
        floatingActionButton = {
            FloatingActionButton(onClick = onCreateClick) {
                Icon(Icons.Default.Add, contentDescription = "New appointment")
            }
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            // §18.2 — scoped search bar
            SearchBar(
                query = state.searchQuery,
                onQueryChange = viewModel::updateSearchQuery,
                placeholder = "Search by title, customer, employee…",
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )

            // View-mode segmented button: Agenda / Day / Week / Month (L1419)
            ViewModeSelector(
                current = state.viewMode,
                onSelect = viewModel::setViewMode,
                modifier = Modifier
                    .padding(horizontal = 16.dp, vertical = 8.dp)
                    .fillMaxWidth(),
            )

            // Filter chip row (L1425)
            FilterChipRow(
                filter = state.filter,
                onFilterChange = viewModel::setFilter,
                modifier = Modifier
                    .padding(horizontal = 16.dp)
                    .fillMaxWidth(),
            )

            val reduceMotion = false // wired to AppPreferences in a follow-up

            AnimatedContent(
                targetState = state.viewMode,
                transitionSpec = {
                    val durationMs = if (reduceMotion) 0 else 220
                    fadeIn(tween(durationMs)) togetherWith fadeOut(tween(durationMs))
                },
                label = "appointment_view",
            ) { mode ->
                when (mode) {
                    AppointmentViewMode.Agenda -> AppointmentAgendaView(
                        appointments = state.filtered,
                        isLoading = state.isLoading,
                        error = state.error,
                        onAppointmentClick = onAppointmentClick,
                        listState = listState,
                    )
                    AppointmentViewMode.Day -> AppointmentDayView(
                        appointments = state.filtered,
                        selectedDate = state.selectedDate,
                        isLoading = state.isLoading,
                        error = state.error,
                        onAppointmentClick = onAppointmentClick,
                        onDateChange = viewModel::setSelectedDate,
                    )
                    AppointmentViewMode.Week -> AppointmentWeekView(
                        appointments = state.filtered,
                        selectedDate = state.selectedDate,
                        isLoading = state.isLoading,
                        error = state.error,
                        onAppointmentClick = onAppointmentClick,
                        onDateChange = viewModel::setSelectedDate,
                    )
                    AppointmentViewMode.Month -> AppointmentMonthView(
                        appointments = state.filtered,
                        selectedMonth = state.selectedDate,
                        isLoading = state.isLoading,
                        error = state.error,
                        onDayClick = { date ->
                            viewModel.setSelectedDate(date)
                            viewModel.setViewMode(AppointmentViewMode.Day)
                        },
                    )
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Segmented button for view mode (L1419)
// ---------------------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ViewModeSelector(
    current: AppointmentViewMode,
    onSelect: (AppointmentViewMode) -> Unit,
    modifier: Modifier = Modifier,
) {
    val modes = AppointmentViewMode.entries
    SingleChoiceSegmentedButtonRow(modifier = modifier) {
        modes.forEachIndexed { idx, mode ->
            SegmentedButton(
                selected = current == mode,
                onClick = { onSelect(mode) },
                shape = SegmentedButtonDefaults.itemShape(index = idx, count = modes.size),
                label = { Text(mode.label) },
                icon = {},
            )
        }
    }
}
