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
                        HStack {
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
                                    .accessibilityLabel("Current")
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.bizarreSurface1)
                    .disabled(vm.isSubmitting)
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
