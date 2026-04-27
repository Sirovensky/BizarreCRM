import SwiftUI
import Observation
import Core
import DesignSystem

// MARK: - §19.2 Login history — recent 50 logins with outcome + IP + user-agent.

// MARK: - Models

public struct LoginRecord: Identifiable, Decodable, Sendable {
    public let id: String
    public let outcome: Outcome
    public let ipAddress: String
    public let userAgent: String
    public let occurredAt: Date
    public let location: String?

    public enum Outcome: String, Decodable, Sendable {
        case success
        case failed
        case blocked
        case twoFARequired = "2fa_required"
        case twoFAPassed   = "2fa_passed"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case outcome
        case ipAddress  = "ip_address"
        case userAgent  = "user_agent"
        case occurredAt = "occurred_at"
        case location
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class LoginHistoryViewModel {

    public var records: [LoginRecord] = []
    public var isLoading: Bool = false
    public var errorMessage: String?

    private let api: APIClientProtocol

    public init(api: APIClientProtocol) {
        self.api = api
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let wire: [LoginRecordWire] = try await api.get("auth/login-history?limit=50")
            records = wire.compactMap(\.toModel)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Wire

private struct LoginRecordWire: Decodable {
    let id: String
    let outcome: String
    let ip_address: String
    let user_agent: String
    let occurred_at: String
    let location: String?

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    var toModel: LoginRecord? {
        guard let outcome = LoginRecord.Outcome(rawValue: outcome),
              let date = Self.iso.date(from: occurred_at) else { return nil }
        return LoginRecord(
            id: id,
            outcome: outcome,
            ipAddress: ip_address,
            userAgent: user_agent,
            occurredAt: date,
            location: location
        )
    }
}

// MARK: - View

public struct LoginHistoryPage: View {

    @State private var vm: LoginHistoryViewModel

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    public init(api: APIClientProtocol) {
        _vm = State(initialValue: LoginHistoryViewModel(api: api))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()

            if vm.isLoading && vm.records.isEmpty {
                ProgressView()
                    .accessibilityLabel("Loading login history")
            } else if vm.records.isEmpty && !vm.isLoading {
                emptyState
            } else {
                recordsList
            }
        }
        .navigationTitle("Login History")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await vm.load() }
    }

    @ViewBuilder
    private var recordsList: some View {
        List(vm.records) { record in
            recordRow(record)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await vm.load() }
    }

    @ViewBuilder
    private func recordRow(_ record: LoginRecord) -> some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: record.outcome.iconName)
                .font(.system(size: 18))
                .foregroundStyle(record.outcome.color)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.outcome.displayName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)

                Text(record.ipAddress + (record.location.map { " · \($0)" } ?? ""))
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)

                Text(Self.dateFormatter.string(from: record.occurredAt))
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)

                Text(record.userAgent.truncated(to: 60))
                    .font(.caption2)
                    .foregroundStyle(.bizarreOnSurfaceMuted.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.bizarreSurface1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(record.outcome.displayName) from \(record.ipAddress) on \(Self.dateFormatter.string(from: record.occurredAt))"
        )
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.largeTitle)
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No login history")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Recent sign-in attempts will appear here.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Outcome helpers

private extension LoginRecord.Outcome {
    var displayName: String {
        switch self {
        case .success:       return "Signed in"
        case .failed:        return "Failed attempt"
        case .blocked:       return "Blocked"
        case .twoFARequired: return "2FA required"
        case .twoFAPassed:   return "2FA passed"
        }
    }

    var iconName: String {
        switch self {
        case .success:       return "checkmark.circle.fill"
        case .failed:        return "xmark.circle.fill"
        case .blocked:       return "hand.raised.fill"
        case .twoFARequired: return "lock.shield"
        case .twoFAPassed:   return "lock.shield.fill"
        }
    }

    var color: Color {
        switch self {
        case .success, .twoFAPassed: return .bizarreSuccess
        case .failed, .blocked:      return .bizarreError
        case .twoFARequired:         return .bizarreOrange
        }
    }
}

private extension String {
    func truncated(to length: Int) -> String {
        count > length ? String(prefix(length)) + "…" : self
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        LoginHistoryPage(api: MockAPIClient())
    }
}
#endif
