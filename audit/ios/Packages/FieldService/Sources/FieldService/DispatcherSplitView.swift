// §57.4 DispatcherSplitView — iPad dispatcher view: list + map placeholder.
//
// Uses NavigationSplitView (requires iOS 16+; package targets iOS 17).
// Left column: job list with filter toolbar.
// Detail column: map placeholder (MapKit not wired — per spec, "don't wire
// MapKit now unless trivial"; the existing FieldServiceMapView is available
// for future integration via appointments; dispatcher job-pin wiring deferred).
//
// iPhone: collapses to single-column NavigationStack (sidebar auto-hides).
// iPad: side-by-side split view.
//
// A11y: split columns each have distinct accessibility labels.
// Liquid Glass chrome only per §57 constraint.

import SwiftUI
import DesignSystem

// MARK: - DispatcherSplitView

public struct DispatcherSplitView: View {

    @State private var vm: DispatcherViewModel

    public init(vm: DispatcherViewModel) {
        _vm = State(wrappedValue: vm)
    }

    public var body: some View {
        NavigationSplitView {
            listColumn
                .navigationTitle("All Jobs")
                .toolbar { listToolbar }
                .refreshable { await vm.refresh() }
        } detail: {
            detailColumn
        }
        .task { await vm.load() }
    }

    // MARK: - List column

    @ViewBuilder
    private var listColumn: some View {
        switch vm.listState {
        case .loading:
            loadingView

        case .loaded(let jobs):
            List(jobs, selection: Binding(
                get: { vm.selectedJob?.id },
                set: { id in
                    if let id, let job = jobs.first(where: { $0.id == id }) {
                        vm.selectJob(job)
                    } else {
                        vm.selectJob(nil)
                    }
                }
            )) { job in
                DispatcherJobRow(job: job)
                    .tag(job.id)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(dispatchRowA11y(job))
                    .accessibilityAddTraits(vm.selectedJob?.id == job.id ? .isSelected : [])
                    .accessibilityHint("Double-tap to view job on map")
            }
            .listStyle(.sidebar)

        case .empty:
            ContentUnavailableView(
                "No Jobs",
                systemImage: "briefcase.circle",
                description: Text("No jobs match the current filter.")
            )

        case .failed(let msg):
            errorView(msg)
        }
    }

    // MARK: - Detail column

    private var detailColumn: some View {
        Group {
            if let job = vm.selectedJob {
                MapPlaceholderView(job: job)
                    .navigationTitle("Job #\(job.id) — \(job.customerName ?? "Unknown")")
                    #if canImport(UIKit)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
            } else {
                ContentUnavailableView(
                    "Select a Job",
                    systemImage: "map",
                    description: Text("Tap a job in the list to see its location.")
                )
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var listToolbar: some ToolbarContent {
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

    // MARK: - Helpers

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

    private func dispatchRowA11y(_ job: FSJob) -> String {
        var parts: [String] = ["Job \(job.id)"]
        if let customer = job.customerName { parts.append(customer) }
        parts.append(FSJobStatus(rawValue: job.status)?.displayLabel ?? job.status)
        parts.append(job.addressLine)
        if let tech = job.techName { parts.append("Assigned to \(tech)") }
        switch job.priority {
        case "emergency": parts.append("Emergency priority")
        case "high":      parts.append("High priority")
        default:          break
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - DispatcherJobRow

private struct DispatcherJobRow: View {
    let job: FSJob

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            HStack {
                Text(job.customerName ?? "Job #\(job.id)")
                    .font(.brandTitleMedium())
                    .lineLimit(1)
                Spacer()
                StatusDot(status: job.status)
            }
            Text(job.addressLine)
                .font(.brandBodyMedium())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let techName = job.techName {
                Text(techName)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .frame(minHeight: DesignTokens.Touch.minTargetSide)
    }
}

// MARK: - StatusDot

private struct StatusDot: View {
    let status: String

    private var color: Color {
        switch FSJobStatus(rawValue: status) {
        case .enRoute:   return .bizarreOrange
        case .onSite:    return .bizarreSuccess
        case .completed: return .bizarreSuccess
        case .assigned:  return .blue
        case .canceled:  return .bizarreError
        default:         return .secondary
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }
}

// MARK: - MapPlaceholderView

/// Placeholder for the dispatcher map detail.
/// Shows job location info and a pin icon.
/// Full MapKit wiring deferred per §57 spec (non-trivial; appointment map
/// already exists in FieldServiceMapView for tech flow).
private struct MapPlaceholderView: View {
    let job: FSJob

    var body: some View {
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

                Text("Lat: \(String(format: "%.5f", job.lat)), Lng: \(String(format: "%.5f", job.lng))")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Coordinates: \(String(format: "%.5f", job.lat)) latitude, \(String(format: "%.5f", job.lng)) longitude")
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)

            Text("Interactive map coming soon")
                .font(.brandLabelSmall())
                .foregroundStyle(.tertiary)
                .padding(DesignTokens.Spacing.sm)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
