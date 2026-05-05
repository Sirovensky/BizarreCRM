import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - §38.5 Dunning cadence — failed charge retry 3d / 7d / 14d + customer notify

// MARK: - Models

public struct DunningStatus: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let membershipId: String
    public let customerId: Int64
    public let customerName: String?
    public let planName: String
    /// "failed" | "retrying" | "paused" | "cancelled"
    public let status: String
    public let attemptCount: Int
    public let nextRetryAt: String?
    public let failedAt: String
    public let failureReason: String?

    public init(id: Int64, membershipId: String, customerId: Int64, customerName: String? = nil,
                planName: String, status: String, attemptCount: Int,
                nextRetryAt: String? = nil, failedAt: String, failureReason: String? = nil) {
        self.id = id
        self.membershipId = membershipId
        self.customerId = customerId
        self.customerName = customerName
        self.planName = planName
        self.status = status
        self.attemptCount = attemptCount
        self.nextRetryAt = nextRetryAt
        self.failedAt = failedAt
        self.failureReason = failureReason
    }

    enum CodingKeys: String, CodingKey {
        case id, status
        case membershipId  = "membership_id"
        case customerId    = "customer_id"
        case customerName  = "customer_name"
        case planName      = "plan_name"
        case attemptCount  = "attempt_count"
        case nextRetryAt   = "next_retry_at"
        case failedAt      = "failed_at"
        case failureReason = "failure_reason"
    }

    public var statusColor: Color {
        switch status {
        case "failed":    return Color.bizarreError
        case "retrying":  return Color.bizarreWarning
        case "paused":    return Color.bizarreOnSurfaceMuted
        case "cancelled": return Color.bizarreError
        default:          return Color.bizarreOnSurfaceMuted
        }
    }
}

// MARK: - Networking

private struct DunningEmptyRequest: Encodable, Sendable {}

extension APIClient {
    /// `GET /api/v1/memberships/dunning` — memberships with failed payments.
    public func dunningQueue() async throws -> [DunningStatus] {
        try await get("/api/v1/memberships/dunning", as: [DunningStatus].self)
    }

    /// `POST /api/v1/memberships/dunning/:id/retry` — manually trigger retry now.
    @discardableResult
    public func retryDunning(id: Int64) async throws -> DunningStatus {
        try await post("/api/v1/memberships/dunning/\(id)/retry", body: DunningEmptyRequest(), as: DunningStatus.self)
    }

    /// `POST /api/v1/memberships/dunning/:id/cancel` — cancel dunning + pause membership.
    @discardableResult
    public func cancelDunning(id: Int64) async throws -> DunningStatus {
        try await post("/api/v1/memberships/dunning/\(id)/cancel", body: DunningEmptyRequest(), as: DunningStatus.self)
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class MembershipDunningViewModel {
    public private(set) var queue: [DunningStatus] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var actionInProgress: Int64?

    @ObservationIgnored private let api: APIClient
    public init(api: APIClient) { self.api = api }

    public func load() async {
        if queue.isEmpty { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do {
            queue = try await api.dunningQueue()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func retry(id: Int64) async {
        actionInProgress = id
        defer { actionInProgress = nil }
        do {
            let updated = try await api.retryDunning(id: id)
            replace(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func cancel(id: Int64) async {
        actionInProgress = id
        defer { actionInProgress = nil }
        do {
            let updated = try await api.cancelDunning(id: id)
            replace(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func replace(_ updated: DunningStatus) {
        if let idx = queue.firstIndex(where: { $0.id == updated.id }) {
            queue[idx] = updated
        }
    }
}

// MARK: - View

#if canImport(UIKit)

public struct MembershipDunningView: View {
    @State private var vm: MembershipDunningViewModel
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
        _vm = State(wrappedValue: MembershipDunningViewModel(api: api))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            Group {
                if vm.isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = vm.errorMessage {
                    errorView(err)
                } else if vm.queue.isEmpty {
                    emptyState
                } else {
                    dunningList
                }
            }
        }
        .navigationTitle("Failed Payments")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreSuccess)
                .accessibilityHidden(true)
            Text("No failed payments.")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("All memberships are billing successfully.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dunningList: some View {
        List(vm.queue) { item in
            dunningRow(item)
                .listRowBackground(Color.bizarreSurface1)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func dunningRow(_ item: DunningStatus) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.customerName ?? "Customer #\(item.customerId)")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Text(item.planName)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Spacer(minLength: 0)
                Text(item.status.capitalized)
                    .font(.brandLabelSmall())
                    .foregroundStyle(item.statusColor)
                    .padding(.horizontal, BrandSpacing.sm)
                    .padding(.vertical, BrandSpacing.xxs)
                    .background(item.statusColor.opacity(0.1), in: Capsule())
            }

            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "arrow.clockwise.circle")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("Attempt \(item.attemptCount) of 3")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                if let next = item.nextRetryAt {
                    Spacer(minLength: 0)
                    Text("Next: \(String(next.prefix(10)))")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

            if let reason = item.failureReason, !reason.isEmpty {
                Text(reason)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
            }

            // Actions
            let isActioning = vm.actionInProgress == item.id
            HStack(spacing: BrandSpacing.sm) {
                Button {
                    Task { await vm.retry(id: item.id) }
                } label: {
                    Group {
                        if isActioning {
                            ProgressView().tint(.white)
                        } else {
                            Label("Retry now", systemImage: "arrow.clockwise")
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .disabled(isActioning || item.status == "cancelled")

                Button {
                    Task { await vm.cancel(id: item.id) }
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.bordered)
                .tint(.bizarreError)
                .disabled(isActioning || item.status == "cancelled")
            }
        }
        .padding(.vertical, BrandSpacing.sm)
        .accessibilityElement(children: .combine)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text(msg)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#endif
