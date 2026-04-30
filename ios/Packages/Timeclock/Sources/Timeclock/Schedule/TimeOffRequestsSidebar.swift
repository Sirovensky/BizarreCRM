import SwiftUI
import DesignSystem
import Networking
import Core

// MARK: - TimeOffRequestsSidebar
//
// §14.6 Time-off requests sidebar — approve / deny (manager).
//
// Shown as a trailing sidebar on iPad (NavigationSplitView column) and as a
// bottom sheet on iPhone from the weekly shift grid.
//
// Loads: GET /api/v1/employees/time-off?status=pending
// Approve: POST /api/v1/employees/:id/time-off/:requestId/approve
// Deny:    POST /api/v1/employees/:id/time-off/:requestId/deny

@MainActor
@Observable
public final class TimeOffRequestsSidebarViewModel {
    public enum LoadState: Sendable, Equatable {
        case idle, loading, loaded, failed(String)
    }

    public private(set) var loadState: LoadState = .idle
    public private(set) var pendingRequests: [TimeOffRequest] = []
    public private(set) var actionError: String?

    @ObservationIgnored private let api: APIClient
    /// §14.9 — called when a request is approved so the shift grid can refresh
    /// its PTO blocks and re-run conflict detection.
    @ObservationIgnored public var onApproved: (@MainActor (TimeOffRequest) -> Void)?

    public init(api: APIClient) {
        self.api = api
    }

    public func load() async {
        loadState = .loading
        actionError = nil
        do {
            let all = try await api.listPendingTimeOffRequests()
            pendingRequests = all.filter { $0.status == .pending }
                .sorted { $0.startDate < $1.startDate }
            loadState = .loaded
        } catch {
            AppLog.ui.error("TimeOffSidebar load: \(error.localizedDescription, privacy: .public)")
            loadState = .failed(error.localizedDescription)
        }
    }

    public func approve(_ request: TimeOffRequest) async {
        actionError = nil
        do {
            let approved = try await api.approveTimeOff(id: request.id)
            pendingRequests.removeAll { $0.id == request.id }
            // §14.9 — notify shift grid so it can add a PTO block and re-check conflicts
            onApproved?(approved)
        } catch {
            AppLog.ui.error("Approve PTO failed: \(error.localizedDescription, privacy: .public)")
            actionError = error.localizedDescription
        }
    }

    public func deny(_ request: TimeOffRequest) async {
        actionError = nil
        do {
            _ = try await api.denyTimeOff(id: request.id, reason: nil)
            pendingRequests.removeAll { $0.id == request.id }
        } catch {
            AppLog.ui.error("Deny PTO failed: \(error.localizedDescription, privacy: .public)")
            actionError = error.localizedDescription
        }
    }
}

// MARK: - View

public struct TimeOffRequestsSidebar: View {
    @State private var vm: TimeOffRequestsSidebarViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: TimeOffRequestsSidebarViewModel(api: api))
    }

    init(viewModel: TimeOffRequestsSidebarViewModel) {
        _vm = State(wrappedValue: viewModel)
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            Group {
                switch vm.loadState {
                case .idle, .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let msg):
                    errorView(msg)
                case .loaded:
                    requestsList
                }
            }
        }
        .navigationTitle("Time-Off Requests")
#if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    // MARK: - Content

    @ViewBuilder
    private var requestsList: some View {
        if vm.pendingRequests.isEmpty {
            emptyState
        } else {
            List {
                if let err = vm.actionError {
                    Text(err)
                        .foregroundStyle(.bizarreError)
                        .font(.brandBodyMedium())
                        .listRowBackground(Color.clear)
                }
                ForEach(vm.pendingRequests) { request in
                    TimeOffRequestRow(request: request) {
                        Task { await vm.approve(request) }
                    } onDeny: {
                        Task { await vm.deny(request) }
                    }
                    .listRowBackground(Color.bizarreSurface1)
                    .listRowSeparatorTint(Color.bizarreOutline.opacity(0.3))
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 44))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No Pending Requests")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("All time-off requests have been handled.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36)).foregroundStyle(.bizarreError)
            Text("Couldn't load requests")
                .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            Button("Try Again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent).tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - TimeOffRequestRow

private struct TimeOffRequestRow: View {
    let request: TimeOffRequest
    let onApprove: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(request.employeeDisplayName)
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                    Text(dateRangeLabel)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(request.kind.rawValue.capitalized)
                        .font(.brandLabelSmall())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(typeColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(typeColor)
                }
                Spacer(minLength: BrandSpacing.sm)
            }
            if let reason = request.reason, !reason.isEmpty {
                Text(reason)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(2)
            }
            HStack(spacing: BrandSpacing.sm) {
                Button("Approve") { onApprove() }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .font(.brandLabelSmall())
                    .accessibilityIdentifier("pto.approve.\(request.id)")
                Button("Deny") { onDeny() }
                    .buttonStyle(.bordered)
                    .tint(.bizarreError)
                    .font(.brandLabelSmall())
                    .accessibilityIdentifier("pto.deny.\(request.id)")
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    private var dateRangeLabel: String {
        "\(formatted(request.startDate)) – \(formatted(request.endDate))"
    }

    private func formatted(_ iso: String) -> String {
        guard let d = ISO8601DateFormatter().date(from: iso) else { return iso }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: d)
    }

    private var typeColor: Color {
        switch request.kind {
        case .pto:    return .blue
        case .sick:   return .red
        case .unpaid: return .orange
        }
    }

    private var a11yLabel: String {
        "\(request.employeeDisplayName) requests \(request.kind.rawValue) from \(dateRangeLabel)"
    }
}

// MARK: - API extension

public extension APIClient {
    /// `GET /api/v1/employees/time-off?status=pending` — all pending time-off requests (manager view).
    func listPendingTimeOffRequests() async throws -> [TimeOffRequest] {
        try await get(
            "/api/v1/employees/time-off",
            query: [URLQueryItem(name: "status", value: "pending")],
            as: [TimeOffRequest].self
        )
    }
}
