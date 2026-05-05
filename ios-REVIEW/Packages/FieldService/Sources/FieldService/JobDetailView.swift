// §57.2 JobDetailView — tech job detail with status transitions.
//
// Status update includes location-based check-in (status=on_site + GPS).
// If location permission is denied, status updates proceed without coords.
// Liquid Glass chrome. iPhone primary layout; adapts naturally on iPad.
//
// A11y: status picker has accessibilityLabel; action button has hint.

import SwiftUI
import DesignSystem

// MARK: - JobDetailView

public struct JobDetailView: View {

    @State private var vm: JobDetailViewModel
    @State private var showStatusPicker: Bool = false
    @State private var pendingStatus: FSJobStatus? = nil

    public init(vm: JobDetailViewModel) {
        _vm = State(wrappedValue: vm)
    }

    public var body: some View {
        Group {
            switch vm.state {
            case .loading:
                ProgressView("Loading job…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .loaded(let job), .updated(let job, _):
                jobDetail(job)

            case .updating:
                ProgressView("Updating status…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .failed(let msg):
                VStack(spacing: DesignTokens.Spacing.lg) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.bizarreError)
                    Text(msg)
                        .font(.brandBodyMedium())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Retry") { Task { await vm.retry() } }
                        .buttonStyle(.brandGlassProminent)
                        .tint(.bizarreOrange)
                }
                .padding(DesignTokens.Spacing.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Job Detail")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await vm.load() }
        .alert("Notice", isPresented: Binding(
            get: { vm.alertMessage != nil },
            set: { if !$0 { vm.dismissAlert() } }
        )) {
            Button("OK") { vm.dismissAlert() }
        } message: {
            Text(vm.alertMessage ?? "")
        }
        .confirmationDialog(
            "Update Status",
            isPresented: $showStatusPicker,
            titleVisibility: .visible
        ) {
            statusPickerActions
        }
    }

    // MARK: - Job detail body

    private func jobDetail(_ job: FSJob) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                headerSection(job)
                addressSection(job)
                if let notes = job.notes, !notes.isEmpty {
                    notesSection("Dispatcher Notes", text: notes)
                }
                if let tech = job.technicianNotes, !tech.isEmpty {
                    notesSection("Technician Notes", text: tech)
                }
                statusSection(job)
            }
            .padding(DesignTokens.Spacing.lg)
        }
    }

    // MARK: - Header

    private func headerSection(_ job: FSJob) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text("Job #\(job.id)")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.secondary)
                    Text(job.customerName ?? "Unknown Customer")
                        .font(.brandTitleLarge())
                        .lineLimit(2)
                }
                Spacer()
                PriorityBadge(priority: job.priority)
            }

            HStack(spacing: DesignTokens.Spacing.sm) {
                StatusChip(status: job.status)
                if let techName = job.techName {
                    Text(techName)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.secondary)
                }
            }

            schedulingRow(job)
        }
        .padding(DesignTokens.Spacing.lg)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private func schedulingRow(_ job: FSJob) -> some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            if let start = job.scheduledWindowStart {
                Label(String(start.prefix(16)), systemImage: "clock")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.secondary)
            }
            if let est = job.estimatedDurationMinutes {
                Label("\(est) min", systemImage: "timer")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Address

    private func addressSection(_ job: FSJob) -> some View {
        let full = [job.addressLine, job.city, job.state, job.postcode]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: ", ")
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("Location")
                .font(.brandLabelSmall())
                .foregroundStyle(.secondary)
            Label(full, systemImage: "location.fill")
                .font(.brandBodyMedium())
                .foregroundStyle(.primary)
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Location: \(full)")
    }

    // MARK: - Notes

    private func notesSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(title)
                .font(.brandLabelSmall())
                .foregroundStyle(.secondary)
            Text(text)
                .font(.brandBodyMedium())
                .foregroundStyle(.primary)
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    // MARK: - Status action

    private func statusSection(_ job: FSJob) -> some View {
        let currentStatus = FSJobStatus(rawValue: job.status)
        let isTerminal = currentStatus == .completed || currentStatus == .canceled

        return VStack(spacing: DesignTokens.Spacing.md) {
            if !isTerminal {
                Button {
                    showStatusPicker = true
                } label: {
                    Label("Update Status", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.brandGlassProminent)
                .tint(.bizarreOrange)
                .frame(minHeight: DesignTokens.Touch.minTargetSide)
                .accessibilityLabel("Update job status")
                .accessibilityHint("Opens a menu to change the current job status")
            } else {
                Label("Job \(currentStatus?.displayLabel ?? "closed")", systemImage: "checkmark.circle.fill")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Status picker actions

    @ViewBuilder
    private var statusPickerActions: some View {
        if case .loaded(let job) = vm.state {
            let current = FSJobStatus(rawValue: job.status) ?? .unassigned
            let allowed = allowedTransitions(from: current)
            ForEach(allowed, id: \.self) { s in
                Button(s.displayLabel) {
                    Task { await vm.updateStatus(to: s) }
                }
            }
        }
        Button("Cancel", role: .cancel) {}
    }

    private func allowedTransitions(from status: FSJobStatus) -> [FSJobStatus] {
        switch status {
        case .unassigned:  return [.assigned, .canceled, .deferred]
        case .assigned:    return [.enRoute, .unassigned, .canceled, .deferred]
        case .enRoute:     return [.onSite, .assigned, .canceled, .deferred]
        case .onSite:      return [.completed, .enRoute, .canceled, .deferred]
        case .completed:   return []
        case .canceled:    return []
        case .deferred:    return [.unassigned, .canceled]
        }
    }
}

// MARK: - StatusChip

private struct StatusChip: View {
    let status: String

    private var statusEnum: FSJobStatus? { FSJobStatus(rawValue: status) }

    private var color: Color {
        switch statusEnum {
        case .enRoute:   return .bizarreOrange
        case .onSite:    return .bizarreSuccess
        case .completed: return .bizarreSuccess
        case .assigned:  return .blue
        case .canceled:  return .bizarreError
        default:         return Color(.secondarySystemFill)
        }
    }

    var body: some View {
        Text(statusEnum?.displayLabel ?? status)
            .font(.brandLabelSmall())
            .foregroundStyle(.white)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .background(color, in: Capsule())
            .accessibilityLabel("Status: \(statusEnum?.displayLabel ?? status)")
    }
}

// MARK: - PriorityBadge (internal reuse)

private struct PriorityBadge: View {
    let priority: String

    private var color: Color {
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
