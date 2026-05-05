#if canImport(UIKit)
import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

/// §4.7 — PATCH /tickets/:id/status action sheet. Lists every status from
/// `/settings/statuses`, highlights the current one, and commits on tap.
///
/// Separate from the general-purpose `TicketEditView` because the server
/// enforces `tickets.change_status` as its own permission + audit path.
@MainActor
@Observable
final class TicketStatusChangeViewModel {
    var statuses: [TicketStatusRow] = []
    var isLoading: Bool = false
    var isSubmitting: Bool = false
    var errorMessage: String?
    var committedStatusId: Int64?

    @ObservationIgnored let ticketId: Int64
    @ObservationIgnored let currentStatusId: Int64?
    @ObservationIgnored private let api: APIClient

    init(ticketId: Int64, currentStatusId: Int64?, api: APIClient) {
        self.ticketId = ticketId
        self.currentStatusId = currentStatusId
        self.api = api
    }

    func load() async {
        isLoading = true; defer { isLoading = false }
        errorMessage = nil
        do {
            statuses = try await api.listTicketStatuses()
        } catch {
            AppLog.ui.error("Status list failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    func commit(_ statusId: Int64) async {
        guard !isSubmitting else { return }
        isSubmitting = true; defer { isSubmitting = false }
        errorMessage = nil
        do {
            _ = try await api.changeTicketStatus(id: ticketId, statusId: statusId)
            committedStatusId = statusId
        } catch {
            AppLog.ui.error("Status change failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

struct TicketStatusChangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: TicketStatusChangeViewModel
    let onCommitted: () -> Void

    init(ticketId: Int64, currentStatusId: Int64?, api: APIClient, onCommitted: @escaping () -> Void) {
        _vm = State(wrappedValue: TicketStatusChangeViewModel(
            ticketId: ticketId,
            currentStatusId: currentStatusId,
            api: api
        ))
        self.onCommitted = onCommitted
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Change status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await vm.load() }
            .onChange(of: vm.committedStatusId) { _, new in
                guard new != nil else { return }
                onCommitted()
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            errorPane(err)
        } else {
            List {
                ForEach(vm.statuses) { status in
                    Button {
                        Task { await vm.commit(status.id) }
                    } label: {
                        HStack(spacing: BrandSpacing.sm) {
                            // §4.7 / §4.13: render server-provided hex color as a
                            // filled circle dot. Falls back to a neutral gray when
                            // no color is supplied (e.g. legacy tenants).
                            Circle()
                                .fill(color(from: status.colorHex))
                                .frame(width: 10, height: 10)
                                .accessibilityHidden(true)

                            Text(status.name)
                                .font(.brandBodyLarge())
                                .foregroundStyle(.bizarreOnSurface)
                            if status.closed {
                                Text("closed")
                                    .font(.brandLabelSmall())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            } else if status.cancelled {
                                Text("cancelled")
                                    .font(.brandLabelSmall())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                            Spacer()
                            if status.id == vm.currentStatusId {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.bizarreOrange)
                                    .accessibilityLabel("Current status")
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.bizarreSurface1)
                    .disabled(vm.isSubmitting)
                    .accessibilityLabel(statusRowA11yLabel(status))
                    .accessibilityIdentifier("ticket.status.\(status.id)")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .overlay {
                if vm.isSubmitting {
                    ProgressView()
                        .padding(BrandSpacing.md)
                        .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // §4.7: resolve a server hex string (e.g. "#3A8FC5" or "3A8FC5") to a
    // SwiftUI Color. Returns a neutral gray when the hex is absent or malformed
    // so the dot is always visible.
    private func color(from hex: String?) -> Color {
        guard let hex else { return Color.bizarreOnSurfaceMuted.opacity(0.4) }
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6,
              let value = UInt64(cleaned, radix: 16) else {
            return Color.bizarreOnSurfaceMuted.opacity(0.4)
        }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8)  & 0xFF) / 255.0
        let b = Double( value        & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    private func statusRowA11yLabel(_ status: TicketStatusRow) -> String {
        var parts = [status.name]
        if status.closed     { parts.append("closed status") }
        if status.cancelled  { parts.append("cancelled status") }
        if status.id == vm.currentStatusId { parts.append("current") }
        return parts.joined(separator: ", ")
    }

    private func errorPane(_ err: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36)).foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load statuses").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center).padding(.horizontal, BrandSpacing.lg)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent).tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#endif
