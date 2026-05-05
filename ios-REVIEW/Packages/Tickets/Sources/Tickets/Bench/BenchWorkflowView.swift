#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §4.9 — Bench workflow top-level view.
//
// Shows the technician:
//   - Current ticket summary (order id, customer name, current status)
//   - BenchTimerView HUD (local stopwatch, no server call)
//   - Action buttons derived from BenchAction.availableActions(for:)
//     which calls PATCH /api/v1/tickets/:id/status via BenchWorkflowViewModel.
//
// Liquid Glass is applied on chrome-layer elements (toolbar, action button bar).
// List rows and data sections use plain backgrounds per ios/CLAUDE.md.

public struct BenchWorkflowView: View {

    @State private var vm: BenchWorkflowViewModel
    @Environment(\.dismiss) private var dismiss

    public init(ticketId: Int64, api: APIClient) {
        _vm = State(wrappedValue: BenchWorkflowViewModel(ticketId: ticketId, api: api))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Bench")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            .task { await vm.load() }
            // Auto-dismiss is not fired here — callers observe committedAction.
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch vm.loadState {
        case .idle, .loading:
            loadingView
        case .loaded(let detail):
            loadedBody(detail: detail)
        case .failed(let msg):
            errorView(message: msg)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Loading bench workflow")
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: BrandSpacing.base) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await vm.load() } }
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOrange)
        }
        .padding(BrandSpacing.xl)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Loaded body

    private func loadedBody(detail: TicketDetail) -> some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                ticketHeader(detail: detail)
                // §42 — Photos-needed banner: surface when no photos attached.
                if detail.photos.isEmpty {
                    photosNeededBanner
                }
                // §42 — Bench status timer chip + stopwatch HUD.
                BenchTimerView()
                benchStatusChip(detail: detail)
                // §42 — Completed-at copy: surface when ticket is done.
                if let completedAt = completedAtText(for: detail) {
                    completedAtRow(text: completedAt)
                }
                actionSection(detail: detail)
                if let err = vm.errorMessage {
                    errorBanner(err)
                }
            }
            .padding(BrandSpacing.base)
        }
    }

    // MARK: §42 — Photos-needed banner

    private var photosNeededBanner: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "camera.fill")
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("No photos attached")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Add before-repair photos so the customer can verify device condition.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreOrange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.bizarreOrange.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Photos needed. No photos attached. Add before-repair photos so the customer can verify device condition.")
    }

    // MARK: §42 — Bench-status timer chip

    /// A small pill under the timer indicating the current bench phase: Awaiting Parts, In Repair, On Hold.
    private func benchStatusChip(detail: TicketDetail) -> some View {
        let (label, icon, tint) = benchStatusChipContent(detail)
        return HStack(spacing: BrandSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .accessibilityHidden(true)
            Text(label)
                .font(.brandLabelSmall())
        }
        .foregroundStyle(tint)
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.xs)
        .background(tint.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
        .accessibilityLabel("Bench phase: \(label)")
    }

    private func benchStatusChipContent(_ detail: TicketDetail) -> (String, String, Color) {
        let name = detail.status?.name.lowercased() ?? ""
        switch name {
        case let n where n.contains("awaiting parts"):
            return ("Awaiting Parts", "cart.fill", Color.bizarreOrange)
        case let n where n.contains("in repair"):
            return ("In Repair", "wrench.fill", Color.bizarreOrange)
        case let n where n.contains("on hold"):
            return ("On Hold", "pause.circle.fill", Color.bizarreOnSurfaceMuted)
        case let n where n.contains("diagnosing"):
            return ("Diagnosing", "stethoscope", Color.bizarreTeal)
        case let n where n.contains("ready"):
            return ("Ready for Pickup", "hand.raised.fill", Color.bizarreSuccess)
        default:
            return (detail.status?.name ?? "Unknown", "circle.fill", Color.bizarreOnSurfaceMuted)
        }
    }

    // MARK: §42 — Completed-at copy

    private func completedAtText(for detail: TicketDetail) -> String? {
        guard detail.status?.isClosed == true || detail.status?.name.lowercased().contains("completed") == true else {
            return nil
        }
        // Use updatedAt as a proxy for the last-transition timestamp.
        guard let raw = detail.updatedAt else { return "Completed" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        guard let d = date else { return "Completed" }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return "Completed \(fmt.string(from: d))"
    }

    private func completedAtRow(text: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(Color.bizarreSuccess)
                .accessibilityHidden(true)
            Text(text)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            // §42 — Copy-to-clipboard gesture.
            Button {
                UIPasteboard.general.string = text
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .accessibilityLabel("Copy completed date")
            .accessibilityHint("Copies the completion timestamp to the clipboard")
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSuccess.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.bizarreSuccess.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text)
    }

    // MARK: - Ticket header

    private func ticketHeader(detail: TicketDetail) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: BrandSpacing.xs) {
                        Text(detail.orderId)
                            .font(.brandTitleMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        // §42 — Escalation flag UI: flame icon when urgency is high/urgent.
                        if isEscalated(detail: detail) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.bizarreError)
                                .accessibilityLabel("Escalated ticket")
                                .accessibilityHint("This ticket has high urgency and may need priority attention")
                        }
                    }
                    if let name = detail.customer?.displayName {
                        Text(name)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                Spacer()
                statusChip(detail: detail)
            }

            if let device = detail.devices.first {
                Divider()
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "iphone")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text(device.displayName)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    if let imei = device.imei {
                        Text(imei)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ticket \(detail.orderId), \(detail.customer?.displayName ?? "unknown customer")")
    }

    private func statusChip(detail: TicketDetail) -> some View {
        Text(detail.status?.name ?? "—")
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOnSurface)
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.xs)
            // Glass on the chrome-level status badge
            .brandGlass(.clear, in: Capsule())
            .accessibilityLabel("Status: \(detail.status?.name ?? "unknown")")
    }

    // MARK: - Action buttons

    private func actionSection(detail: TicketDetail) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Actions")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .padding(.horizontal, 4)

            if vm.availableActions.isEmpty {
                noActionsView
            } else {
                ForEach(vm.availableActions, id: \.self) { action in
                    actionButton(action)
                }
            }
        }
    }

    private var noActionsView: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "lock.circle")
                .font(.system(size: 28))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No actions available")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(BrandSpacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No bench actions available for current status")
    }

    private func actionButton(_ action: BenchAction) -> some View {
        let isDisabled = vm.isSubmitting

        return Button {
            Task { await vm.perform(action) }
        } label: {
            HStack(spacing: BrandSpacing.md) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 22))
                    .foregroundStyle(.bizarreOrange)
                    .frame(width: 30)
                    .accessibilityHidden(true)

                Text(action.displayName)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)

                Spacer()

                if vm.isSubmitting && vm.committedAction == nil {
                    ProgressView()
                        .tint(.bizarreOrange)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
            .padding(BrandSpacing.base)
            .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
            )
            .opacity(isDisabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        // §42 — Parts-on-hold a11y: provide a richer hint for the partsOrdered action
        // so VoiceOver users understand this transitions the ticket into Awaiting Parts.
        .accessibilityLabel(action == .partsOrdered ? "Parts Ordered — place ticket on hold awaiting parts" : action.displayName)
        .accessibilityHint(action == .partsOrdered
            ? "Marks this ticket as waiting for parts. The ticket moves to Awaiting Parts status."
            : (isDisabled ? "Action unavailable while another action is in progress" : "Tap to \(action.displayName.lowercased())")
        )
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreError)
                .multilineTextAlignment(.leading)
        }
        .padding(BrandSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreError.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.bizarreError.opacity(0.4), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }

    // MARK: - §42 Helpers

    /// Returns true when the ticket urgency field signals high priority.
    private func isEscalated(detail: TicketDetail) -> Bool {
        guard let urgency = detail.urgency?.lowercased() else { return false }
        return urgency == "high" || urgency == "urgent" || urgency == "escalated"
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") { dismiss() }
                .accessibilityLabel("Close bench workflow")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await vm.load() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .accessibilityLabel("Refresh ticket")
            }
            .disabled(vm.isSubmitting)
        }
    }
}

// MARK: - iPad support

extension BenchWorkflowView {
    /// Returns an iPad-friendly full-page variant. On iPhone the sheet detent
    /// handles sizing; on iPad we can expand to fill the detail column.
    public var adaptiveBody: some View {
        self
    }
}

// Preview intentionally omitted — requires a live APIClient instance.
#endif
