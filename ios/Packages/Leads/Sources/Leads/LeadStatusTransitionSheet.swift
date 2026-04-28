import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - §9.3 Status workflow transition dropdown

/// Shows allowed next statuses and transitions the lead.
/// "lost" status always requires the `LostReasonSheet` flow.

@MainActor
@Observable
public final class LeadStatusTransitionViewModel {
    public private(set) var isTransitioning = false
    public internal(set) var error: String?

    @ObservationIgnored private let api: APIClient
    let lead: LeadDetail

    public init(api: APIClient, lead: LeadDetail) {
        self.api = api
        self.lead = lead
    }

    /// Available next statuses from the current status.
    /// Terminal states (converted, archived) have no transitions.
    public var availableTransitions: [String] {
        switch lead.status ?? "" {
        case "new":        return ["contacted", "qualified", "lost"]
        case "contacted":  return ["scheduled", "qualified", "lost"]
        case "scheduled":  return ["qualified", "proposal", "lost"]
        case "qualified":  return ["proposal", "converted", "lost"]
        case "proposal":   return ["converted", "lost"]
        case "lost":       return ["new", "contacted"]  // re-open
        case "converted":  return []
        default:           return LeadStatusTransitionViewModel.allStatuses.filter { $0 != lead.status }
        }
    }

    public static let allStatuses = ["new", "contacted", "scheduled", "qualified", "proposal", "converted", "lost"]

    /// Transition to a new status (non-lost path).
    public func transition(to newStatus: String) async throws -> LeadDetail {
        isTransitioning = true
        error = nil
        defer { isTransitioning = false }
        return try await api.updateLead(
            id: lead.id,
            body: LeadUpdateBody(status: newStatus)
        )
    }
}

// MARK: - View

#if canImport(UIKit)

public struct LeadStatusTransitionSheet: View {
    let api: APIClient
    let lead: LeadDetail
    let onTransitioned: (LeadDetail) -> Void

    @State private var vm: LeadStatusTransitionViewModel
    @State private var showingLostReason = false
    @Environment(\.dismiss) private var dismiss

    public init(api: APIClient, lead: LeadDetail, onTransitioned: @escaping (LeadDetail) -> Void) {
        self.api = api
        self.lead = lead
        self.onTransitioned = onTransitioned
        _vm = State(wrappedValue: LeadStatusTransitionViewModel(api: api, lead: lead))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                    // Current status
                    VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                        Text("Current status")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                        Text((lead.status ?? "unknown").capitalized)
                            .font(.brandTitleMedium())
                            .foregroundStyle(.bizarreOnSurface)
                            .padding(.horizontal, BrandSpacing.md)
                            .padding(.vertical, BrandSpacing.xs)
                            .background(Color.bizarreOrange, in: Capsule())
                            .foregroundStyle(.bizarreOnOrange)
                    }

                    if vm.availableTransitions.isEmpty {
                        Text("No further transitions available for this lead.")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    } else {
                        Text("Move to")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)

                        VStack(spacing: BrandSpacing.sm) {
                            ForEach(vm.availableTransitions, id: \.self) { status in
                                transitionButton(status)
                            }
                        }
                    }

                    if let err = vm.error {
                        Text(err)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreError)
                    }

                    Spacer(minLength: 0)
                }
                .padding(BrandSpacing.lg)

                if vm.isTransitioning {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView()
                }
            }
            .navigationTitle("Change Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel status change")
                }
            }
            .sheet(isPresented: $showingLostReason) {
                LostReasonSheet(api: api, leadId: lead.id) {
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func transitionButton(_ status: String) -> some View {
        let isLost = status == "lost"
        return Button {
            if isLost {
                showingLostReason = true
            } else {
                Task {
                    do {
                        let updated = try await vm.transition(to: status)
                        onTransitioned(updated)
                        dismiss()
                    } catch {
                        vm.error = error.localizedDescription
                    }
                }
            }
        } label: {
            HStack {
                Image(systemName: statusIcon(status))
                    .foregroundStyle(statusColor(status))
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(status.capitalized)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .padding(BrandSpacing.md)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .disabled(vm.isTransitioning)
        .accessibilityLabel("Move to \(status.capitalized)")
    }

    private func statusIcon(_ status: String) -> String {
        switch status {
        case "new":       return "sparkle"
        case "contacted": return "phone.fill"
        case "scheduled": return "calendar"
        case "qualified": return "checkmark.seal"
        case "proposal":  return "doc.text.fill"
        case "converted": return "arrow.right.circle.fill"
        case "lost":      return "xmark.circle.fill"
        default:          return "circle"
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "converted": return .bizarreSuccess
        case "lost":      return .bizarreError
        default:          return .bizarreOrange
        }
    }
}
#endif
