#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §8.2 Estimate Versioning
//
// Displays version history for an estimate. Each edit that is "sent" creates a
// new version on the server tracked via the `version` field on the estimate.
//
// Server endpoint:
//   GET /api/v1/estimates/:id/versions
//   Response: { success, data: [EstimateVersion] }
//
// The view loads versions lazily and shows a numbered list with created_at
// and status. Tapping a version shows a read-only snapshot (line items, total,
// status at that version). The "approved version" is highlighted.

// MARK: - EstimateVersion DTO

public struct EstimateVersion: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let versionNumber: Int
    public let status: String?
    public let total: Double?
    public let createdAt: String?
    public let isApproved: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case versionNumber = "version_number"
        case status
        case total
        case createdAt = "created_at"
        case isApproved = "is_approved"
    }
}

// MARK: - EstimateVersioningViewModel

@MainActor
@Observable
final class EstimateVersioningViewModel {
    var versions: [EstimateVersion] = []
    var isLoading: Bool = false
    var errorMessage: String?

    private let api: APIClient
    let estimateId: Int64

    init(api: APIClient, estimateId: Int64) {
        self.api = api
        self.estimateId = estimateId
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            struct VersionsResponse: Decodable { let versions: [EstimateVersion]? }
            let resp = try await api.get(
                "/api/v1/estimates/\(estimateId)/versions",
                as: VersionsResponse.self
            )
            versions = resp.versions ?? []
        } catch {
            // Graceful degradation: versioning is not yet wired on all installs.
            // Show empty state rather than error if 404.
            if case APITransportError.httpStatus(404, _) = error {
                versions = []
            } else {
                errorMessage = error.localizedDescription
            }
            AppLog.ui.warning("Estimate versions load: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - EstimateVersioningView

/// §8.2: Shows the revision history for an estimate.
/// Each sent version is listed; approved version highlighted.
/// iPhone: push onto NavigationStack from detail toolbar.
/// iPad: panel in the actions sidebar.
public struct EstimateVersioningView: View {
    private let estimate: Estimate
    private let api: APIClient

    @State private var vm: EstimateVersioningViewModel

    public init(estimate: Estimate, api: APIClient) {
        self.estimate = estimate
        self.api = api
        _vm = State(wrappedValue: EstimateVersioningViewModel(
            api: api,
            estimateId: estimate.id
        ))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            Group {
                if vm.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("Loading version history")
                } else if vm.versions.isEmpty {
                    emptyState
                } else {
                    versionList
                }
            }
        }
        .navigationTitle("Version History")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    // MARK: - Version list

    private var versionList: some View {
        List {
            ForEach(vm.versions) { version in
                versionRow(version)
                    .listRowBackground(Color.bizarreSurface1)
                    .listRowSeparatorTint(Color.bizarreOutline.opacity(0.2))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func versionRow(_ version: EstimateVersion) -> some View {
        HStack(alignment: .center, spacing: BrandSpacing.md) {
            // Version badge
            ZStack {
                Circle()
                    .fill(version.isApproved == true ? Color.green.opacity(0.15) : Color.bizarreSurface2)
                    .frame(width: 40, height: 40)
                Text("v\(version.versionNumber)")
                    .font(.brandMono(size: 13))
                    .foregroundStyle(version.isApproved == true ? .green : .bizarreOnSurface)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                HStack(spacing: BrandSpacing.xs) {
                    Text("Version \(version.versionNumber)")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    if version.isApproved == true {
                        Text("Approved")
                            .font(.brandLabelSmall())
                            .padding(.horizontal, BrandSpacing.xs)
                            .padding(.vertical, 2)
                            .foregroundStyle(.green)
                            .background(Color.green.opacity(0.12), in: Capsule())
                    }
                }
                if let status = version.status, !status.isEmpty {
                    Text(status.capitalized)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                if let createdAt = version.createdAt {
                    Text(formatDate(createdAt))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

            Spacer()

            if let total = version.total {
                Text(formatMoney(total))
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(versionA11y(version))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 40))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No version history")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Versions are recorded each time an estimate is sent.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func formatDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else {
            return String(iso.prefix(10))
        }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .short
        return out.string(from: date)
    }

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }

    private func versionA11y(_ v: EstimateVersion) -> String {
        var parts = ["Version \(v.versionNumber)"]
        if v.isApproved == true { parts.append("Approved") }
        if let s = v.status { parts.append(s.capitalized) }
        if let t = v.total { parts.append(formatMoney(t)) }
        if let d = v.createdAt { parts.append(formatDate(d)) }
        return parts.joined(separator: ". ")
    }
}

#endif
