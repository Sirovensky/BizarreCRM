// §22 TechRosterSidebar — sidebar column showing technicians with real-time status.
//
// Displays roster of active technicians. Tapping a row filters the job list
// to that technician's jobs. Tapping again deselects (shows all).
//
// Status dots: green=available, orange=en_route, yellow=busy, grey=offline.
// Job-count badge shows how many open jobs that tech has today.
//
// Liquid Glass chrome only (toolbar, navigation bar). Rows are content — no glass.
// .hoverEffect(.highlight) per iPad polish requirement.
// A11y: each row is a combined accessibility element.

import SwiftUI
import DesignSystem
import Core

// MARK: - TechRosterSidebar

struct TechRosterSidebar: View {

    @Bindable var vm: DispatcherConsoleViewModel

    var body: some View {
        Group {
            switch vm.rosterState {
            case .loading:
                loadingView
            case .loaded(let entries):
                rosterList(entries)
            case .empty:
                ContentUnavailableView(
                    "No Technicians",
                    systemImage: "person.slash",
                    description: Text("No active technicians found.")
                )
            case .failed(let msg):
                errorView(msg)
            }
        }
        .toolbar { sidebarToolbar }
    }

    // MARK: - Roster list

    private func rosterList(_ entries: [TechRosterEntry]) -> some View {
        List(entries, selection: Binding(
            get: { vm.filterByTechId },
            set: { newId in
                // Deselect if same tech tapped again.
                vm.filterByTechId = vm.filterByTechId == newId ? nil : newId
                Task { await vm.applyFilters() }
            }
        )) { entry in
            TechRosterRow(entry: entry, isSelected: vm.filterByTechId == entry.id)
                .tag(entry.id)
                .hoverEffect(.highlight)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(rosterRowA11y(entry))
                .accessibilityAddTraits(vm.filterByTechId == entry.id ? .isSelected : [])
        }
        .listStyle(.sidebar)
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ProgressView()
            Text("Loading roster…")
                .font(.brandBodyMedium())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await vm.refresh() } }
                .buttonStyle(.brandGlassProminent)
                .tint(.bizarreOrange)
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if vm.filterByTechId != nil {
                Button("All") {
                    vm.filterByTechId = nil
                    Task { await vm.applyFilters() }
                }
                .font(.brandLabelLarge())
                .tint(.bizarreOrange)
                .accessibilityLabel("Clear technician filter")
            }
        }
    }

    // MARK: - A11y helper

    private func rosterRowA11y(_ entry: TechRosterEntry) -> String {
        var parts: [String] = [entry.tech.displayName, entry.currentStatus.displayLabel]
        if entry.assignedJobCount > 0 {
            parts.append("\(entry.assignedJobCount) job\(entry.assignedJobCount == 1 ? "" : "s")")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - TechRosterRow

struct TechRosterRow: View {
    let entry: TechRosterEntry
    let isSelected: Bool

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            // Avatar / initials circle
            ZStack {
                Circle()
                    .fill(statusColor(entry.currentStatus).opacity(0.2))
                    .frame(width: DesignTokens.Touch.minTargetSide, height: DesignTokens.Touch.minTargetSide)
                Text(entry.tech.initials)
                    .font(.brandTitleMedium())
                    .foregroundStyle(statusColor(entry.currentStatus))
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(entry.tech.displayName)
                    .font(.brandTitleSmall())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(entry.currentStatus.displayLabel)
                    .font(.brandLabelSmall())
                    .foregroundStyle(statusColor(entry.currentStatus))
            }

            Spacer()

            if entry.assignedJobCount > 0 {
                Text("\(entry.assignedJobCount)")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.white)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .background(statusColor(entry.currentStatus), in: Capsule())
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .frame(minHeight: DesignTokens.Touch.minTargetSide)
        .background(
            isSelected
                ? Color.bizarreOrangeContainer.opacity(0.3)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
        )
    }

    private func statusColor(_ status: TechStatus) -> Color {
        switch status {
        case .available: return .bizarreSuccess
        case .enRoute:   return .bizarreOrange
        case .busy:      return .bizarreWarning
        case .offline:   return .secondary
        }
    }
}

// MARK: - DispatcherJobListPane

struct DispatcherJobListPane: View {

    @Bindable var vm: DispatcherConsoleViewModel

    var body: some View {
        Group {
            switch vm.jobsState {
            case .loading:
                loadingView
            case .loaded(let jobs):
                jobList(jobs)
            case .empty:
                ContentUnavailableView(
                    "No Jobs",
                    systemImage: "briefcase.circle",
                    description: Text("No jobs match the current filters.")
                )
            case .failed(let msg):
                errorView(msg)
            }
        }
        .toolbar { jobListToolbar }
        .refreshable { await vm.refresh() }
        .task { await vm.load() }
        .safeAreaInset(edge: .bottom) {
            if vm.hasBatchSelection {
                JobBatchActionsBar(vm: vm)
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                    .padding(.bottom, DesignTokens.Spacing.md)
            }
        }
    }

    // MARK: - List

    private func jobList(_ jobs: [FSJob]) -> some View {
        List(jobs) { job in
            DispatcherJobListRow(
                job: job,
                isSelected: vm.selectedJobIds.contains(job.id),
                isFocused: vm.focusedJob?.id == job.id
            )
            .contentShape(Rectangle())
            .onTapGesture {
                vm.focusJob(job)
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4)
                    .onEnded { _ in vm.toggleJobSelection(job.id) }
            )
            .hoverEffect(.highlight)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(jobRowA11y(job))
            .accessibilityHint("Tap to view on map. Long press to select for batch actions.")
            .contextMenu { jobContextMenu(job) }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func jobContextMenu(_ job: FSJob) -> some View {
        Button {
            vm.toggleJobSelection(job.id)
        } label: {
            let isSelected = vm.selectedJobIds.contains(job.id)
            Label(
                isSelected ? "Deselect" : "Select for Batch",
                systemImage: isSelected ? "checkmark.circle.fill" : "checkmark.circle"
            )
        }
        Button {
            vm.selectAll(jobs: vm.currentJobs)
        } label: {
            Label("Select All", systemImage: "checkmark.circle.badge.checkmark")
        }
        Divider()
        Button(role: .cancel) {
            vm.clearSelection()
        } label: {
            Label("Clear Selection", systemImage: "xmark.circle")
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ProgressView()
            Text("Loading jobs…")
                .font(.brandBodyMedium())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.bizarreError)
            Text(message)
                .font(.brandBodyMedium())
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Retry") { Task { await vm.refresh() } }
                .buttonStyle(.brandGlassProminent)
                .tint(.bizarreOrange)
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var jobListToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Status", selection: $vm.filterByStatus) {
                    Text("All").tag(Optional<FSJobStatus>.none)
                    ForEach(FSJobStatus.allCases, id: \.self) { s in
                        Text(s.displayLabel).tag(Optional(s))
                    }
                }
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    .symbolVariant(vm.filterByStatus != nil ? .fill : .none)
            }
            .onChange(of: vm.filterByStatus) { _, _ in
                Task { await vm.applyFilters() }
            }
        }
        if vm.hasBatchSelection {
            ToolbarItem(placement: .topBarLeading) {
                Button("Select All") {
                    vm.selectAll(jobs: vm.currentJobs)
                }
                .font(.brandLabelLarge())
            }
        }
    }

    // MARK: - A11y

    private func jobRowA11y(_ job: FSJob) -> String {
        var parts: [String] = ["Job \(job.id)"]
        if let customer = job.customerName { parts.append(customer) }
        parts.append(FSJobStatus(rawValue: job.status)?.displayLabel ?? job.status)
        parts.append(job.addressLine)
        if let tech = job.techName { parts.append("Assigned to \(tech)") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - DispatcherJobListRow

struct DispatcherJobListRow: View {
    let job: FSJob
    let isSelected: Bool
    let isFocused: Bool

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.bizarreOrange)
                    .font(.system(size: 18))
                    .accessibilityHidden(true)
            } else {
                statusDot
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                HStack {
                    Text(job.customerName ?? "Job #\(job.id)")
                        .font(.brandTitleMedium())
                        .lineLimit(1)
                    Spacer()
                    priorityBadge
                }
                Text(job.addressLine)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let tech = job.techName {
                    Text(tech)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .frame(minHeight: DesignTokens.Touch.minTargetSide)
        .background(
            isFocused
                ? Color.bizarreOrangeContainer.opacity(0.25)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
        )
    }

    private var statusDot: some View {
        let color: Color
        switch FSJobStatus(rawValue: job.status) {
        case .enRoute:   color = .bizarreOrange
        case .onSite:    color = .bizarreSuccess
        case .completed: color = .bizarreSuccess
        case .assigned:  color = .blue
        case .canceled:  color = .bizarreError
        default:         color = .secondary
        }
        return Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .padding(.top, DesignTokens.Spacing.xxs)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var priorityBadge: some View {
        let color: Color? = {
            switch job.priority {
            case "emergency": return .bizarreError
            case "high":      return .bizarreOrange
            default:          return nil
            }
        }()
        if let color {
            Text(job.priority.capitalized)
                .font(.brandLabelSmall())
                .foregroundStyle(.white)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xxs)
                .background(color, in: Capsule())
        }
    }
}

// MARK: - DispatcherMapPane

struct DispatcherMapPane: View {
    @Bindable var vm: DispatcherConsoleViewModel

    var body: some View {
        if let job = vm.focusedJob {
            jobDetailPane(job)
        } else {
            ContentUnavailableView(
                "Select a Job",
                systemImage: "map",
                description: Text("Tap a job in the list to see its location and details.")
            )
        }
    }

    private func jobDetailPane(_ job: FSJob) -> some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            Image(systemName: "map.fill")
                .font(.system(size: 64))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)

            VStack(spacing: DesignTokens.Spacing.sm) {
                Text(job.customerName ?? "Job #\(job.id)")
                    .font(.brandTitleLarge())
                    .multilineTextAlignment(.center)

                let address = [job.addressLine, job.city, job.state]
                    .compactMap { $0?.isEmpty == false ? $0 : nil }
                    .joined(separator: ", ")
                Text(address)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)

                Text("Lat: \(String(format: "%.5f", job.lat)), Lng: \(String(format: "%.5f", job.lng))")
                    .font(.brandMono())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .accessibilityLabel("Coordinates: \(String(format: "%.5f", job.lat)) latitude, \(String(format: "%.5f", job.lng)) longitude")
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)

            if let tech = job.techName {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(tech)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.secondary)
                }
            }

            Text("Interactive map coming soon")
                .font(.brandLabelSmall())
                .foregroundStyle(.tertiary)
                .padding(DesignTokens.Spacing.sm)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Job #\(job.id)")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .accessibilityElement(children: .combine)
    }
}
