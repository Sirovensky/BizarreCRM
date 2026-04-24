// §57.1 JobListView — tech job list (iPhone primary, iPad secondary column).
//
// iPhone: NavigationStack with job rows.
// iPad: left column of NavigationSplitView (caller owns the split).
//
// Liquid Glass chrome only (per §57 constraint — no custom glass inside rows).
// A11y: each row is an accessibility element with combined label.

import SwiftUI
import DesignSystem

// MARK: - JobListView

public struct JobListView: View {

    @State private var vm: JobListViewModel
    public var onSelectJob: ((FSJob) -> Void)?

    public init(vm: JobListViewModel, onSelectJob: ((FSJob) -> Void)? = nil) {
        _vm = State(wrappedValue: vm)
        self.onSelectJob = onSelectJob
    }

    public var body: some View {
        Group {
            switch vm.state {
            case .idle, .loading:
                loadingView
            case .loaded(let jobs):
                jobList(jobs)
            case .empty:
                emptyView
            case .failed(let msg):
                errorView(msg)
            }
        }
        .navigationTitle("My Jobs")
        .toolbar { filterToolbar }
        .refreshable { await vm.refresh() }
        .task { await vm.load() }
    }

    // MARK: - List

    private func jobList(_ jobs: [FSJob]) -> some View {
        List(jobs) { job in
            JobRowView(job: job)
                .contentShape(Rectangle())
                .onTapGesture { onSelectJob?(job) }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(rowA11yLabel(job))
                .accessibilityHint("Double-tap to view job details")
                .listRowInsets(EdgeInsets(
                    top: DesignTokens.Spacing.xs,
                    leading: DesignTokens.Spacing.lg,
                    bottom: DesignTokens.Spacing.xs,
                    trailing: DesignTokens.Spacing.lg
                ))
        }
        .listStyle(.plain)
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

    private var emptyView: some View {
        ContentUnavailableView(
            "No Jobs",
            systemImage: "briefcase.circle",
            description: Text("No jobs match the current filter.")
        )
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
    private var filterToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Status", selection: $vm.selectedStatus) {
                    Text("All").tag(Optional<FSJobStatus>.none)
                    ForEach(FSJobStatus.allCases, id: \.self) { s in
                        Text(s.displayLabel).tag(Optional(s))
                    }
                }
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    .symbolVariant(vm.selectedStatus != nil ? .fill : .none)
            }
            .onChange(of: vm.selectedStatus) { _, _ in
                Task { await vm.applyFilters() }
            }
        }
    }

    // MARK: - A11y helpers

    private func rowA11yLabel(_ job: FSJob) -> String {
        var parts: [String] = []
        parts.append("Job \(job.id)")
        parts.append(FSJobStatus(rawValue: job.status)?.displayLabel ?? job.status)
        if let customer = job.customerName { parts.append(customer) }
        parts.append(job.addressLine)
        if let start = job.scheduledWindowStart { parts.append("Scheduled \(start)") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - JobRowView

struct JobRowView: View {

    let job: FSJob

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
            StatusIndicator(status: job.status)
                .padding(.top, DesignTokens.Spacing.xs)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                HStack {
                    Text(job.customerName ?? "Job #\(job.id)")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    PriorityBadge(priority: job.priority)
                }
                Text(job.addressLine)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let start = job.scheduledWindowStart {
                    Text(start.prefix(16))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .frame(minHeight: DesignTokens.Touch.minTargetSide)
    }
}

// MARK: - StatusIndicator

private struct StatusIndicator: View {
    let status: String

    var color: Color {
        switch FSJobStatus(rawValue: status) {
        case .enRoute:   return .bizarreOrange
        case .onSite:    return .bizarreSuccess
        case .completed: return .bizarreSuccess
        case .assigned:  return .blue
        case .canceled:  return .bizarreError
        case .deferred:  return .secondary
        default:         return .secondary
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }
}

// MARK: - PriorityBadge

private struct PriorityBadge: View {
    let priority: String

    var color: Color {
        switch priority {
        case "emergency": return .bizarreError
        case "high":      return .bizarreOrange
        default:          return .clear
        }
    }

    var body: some View {
        if priority == "emergency" || priority == "high" {
            Text(priority.capitalized)
                .font(.brandLabelSmall())
                .foregroundStyle(.white)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xxs)
                .background(color, in: Capsule())
        }
    }
}
