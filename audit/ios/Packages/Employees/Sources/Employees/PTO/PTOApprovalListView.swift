import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - PTOApprovalListViewModel

@MainActor
@Observable
public final class PTOApprovalListViewModel {
    public private(set) var pending: [PTORequest] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let managerId: String

    public init(api: APIClient, managerId: String) {
        self.api = api
        self.managerId = managerId
    }

    public func load() async {
        if pending.isEmpty { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do {
            pending = try await api.listPTORequests(status: .pending)
        } catch {
            AppLog.ui.error("PTOApproval load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func approve(request: PTORequest) async {
        await review(request: request, newStatus: .approved)
    }

    public func deny(request: PTORequest) async {
        await review(request: request, newStatus: .denied)
    }

    private func review(request: PTORequest, newStatus: PTOStatus) {
        let id = request.id
        pending.removeAll { $0.id == id }
        Task {
            do {
                _ = try await api.reviewPTORequest(id: id, ReviewPTORequest(status: newStatus, reviewedBy: managerId))
            } catch {
                AppLog.ui.error("PTOApproval review failed: \(error.localizedDescription, privacy: .public)")
                await load()
            }
        }
    }
}

// MARK: - PTOApprovalListView

public struct PTOApprovalListView: View {
    @State private var vm: PTOApprovalListViewModel

    public init(api: APIClient, managerId: String) {
        _vm = State(wrappedValue: PTOApprovalListViewModel(api: api, managerId: managerId))
    }

    public var body: some View {
        Group {
            if Platform.isCompact { compactLayout } else { regularLayout }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    @ViewBuilder private var compactLayout: some View {
        NavigationStack {
            approvalContent
                .navigationTitle("PTO Requests")
        }
    }

    @ViewBuilder private var regularLayout: some View {
        NavigationSplitView {
            approvalContent
                .navigationTitle("PTO Requests")
        } detail: {
            Text("Select a request").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var approvalContent: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.pending.isEmpty {
            ContentUnavailableView("No Pending Requests",
                                   systemImage: "checkmark.seal",
                                   description: Text("All time-off requests have been reviewed."))
        } else {
            List(vm.pending) { request in
                PTOApprovalRow(request: request) {
                    Task { await vm.approve(request: request) }
                } onDeny: {
                    Task { await vm.deny(request: request) }
                }
            }
        }
    }
}

// MARK: - PTOApprovalRow

private struct PTOApprovalRow: View {
    let request: PTORequest
    let onApprove: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text(request.employeeId)
                    .font(.headline)
                Spacer()
                Text(request.type.displayName)
                    .font(.caption)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .background(.quaternary, in: Capsule())
            }

            Text("\(request.startDate.formatted(date: .abbreviated, time: .omitted)) – \(request.endDate.formatted(date: .abbreviated, time: .omitted))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !request.reason.isEmpty {
                Text(request.reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: DesignTokens.Spacing.lg) {
                Button(action: onApprove) {
                    Label("Approve", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .accessibilityLabel("Approve time-off request for \(request.employeeId)")

                Button(role: .destructive, action: onDeny) {
                    Label("Deny", systemImage: "xmark.circle.fill")
                }
                .accessibilityLabel("Deny time-off request for \(request.employeeId)")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
    }
}

// MARK: - Async review helper

private extension PTOApprovalListViewModel {
    func review(request: PTORequest, newStatus: PTOStatus) async {
        let id = request.id
        pending.removeAll { $0.id == id }
        do {
            _ = try await api.reviewPTORequest(id: id, ReviewPTORequest(status: newStatus, reviewedBy: managerId))
        } catch {
            AppLog.ui.error("PTOApproval review failed: \(error.localizedDescription, privacy: .public)")
            await load()
        }
    }
}
