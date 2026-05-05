import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - ReceivedShoutoutsView
//
// §46.7 Delivery — archive of received shoutouts in recipient profile.
//
// Shown as a section on the employee profile page (self-view or admin-view).
// Loads: GET /api/v1/recognition/shoutouts?employee_id=X
//
// Push notification (§70) for new shoutout delivery is handled by the
// notification category registered in Notifications package; this view
// shows the archive that accumulates on the server.

@MainActor
@Observable
public final class ReceivedShoutoutsViewModel {
    public enum LoadState: Sendable, Equatable {
        case idle, loading, loaded, failed(String)
    }

    public private(set) var loadState: LoadState = .idle
    public private(set) var shoutouts: [RecognitionShoutout] = []

    @ObservationIgnored private let employeeId: String
    @ObservationIgnored private let api: APIClient

    public init(employeeId: String, api: APIClient) {
        self.employeeId = employeeId
        self.api = api
    }

    public func load() async {
        loadState = .loading
        do {
            shoutouts = try await api.listReceivedShoutouts(employeeId: employeeId)
            loadState = .loaded
        } catch {
            AppLog.ui.error("ReceivedShoutouts load: \(error.localizedDescription, privacy: .public)")
            loadState = .failed(error.localizedDescription)
        }
    }
}

// MARK: - View

public struct ReceivedShoutoutsView: View {
    @State private var vm: ReceivedShoutoutsViewModel

    public init(employeeId: String, api: APIClient) {
        _vm = State(wrappedValue: ReceivedShoutoutsViewModel(employeeId: employeeId, api: api))
    }

    init(viewModel: ReceivedShoutoutsViewModel) {
        _vm = State(wrappedValue: viewModel)
    }

    public var body: some View {
        Group {
            switch vm.loadState {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity)
            case .failed(let msg):
                Text(msg).foregroundStyle(.bizarreError).font(.brandBodyMedium())
            case .loaded:
                content
            }
        }
        .task { await vm.load() }
    }

    @ViewBuilder
    private var content: some View {
        if vm.shoutouts.isEmpty {
            VStack(spacing: BrandSpacing.sm) {
                Image(systemName: "hand.thumbsup")
                    .font(.system(size: 32))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("No shoutouts yet.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .padding(BrandSpacing.lg)
        } else {
            LazyVStack(spacing: BrandSpacing.sm) {
                ForEach(vm.shoutouts) { shoutout in
                    ShoutoutCard(shoutout: shoutout)
                }
            }
        }
    }
}

// MARK: - ShoutoutCard

public struct ShoutoutCard: View {
    public let shoutout: RecognitionShoutout

    public init(shoutout: RecognitionShoutout) {
        self.shoutout = shoutout
    }

    public var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            Image(systemName: shoutout.category.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.bizarreOrange)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                HStack {
                    Text(shoutout.category.displayName)
                        .font(.brandTitleSmall())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer(minLength: 0)
                    Text(formattedDate(shoutout.createdAt))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                if let from = shoutout.fromDisplayName {
                    Text("From \(from)")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOrange)
                }
                if !shoutout.message.isEmpty {
                    Text(shoutout.message)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !shoutout.isTeamVisible {
                    Label("Private", systemImage: "lock.fill")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.bizarreOutline.opacity(0.25), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    private var a11yLabel: String {
        let from = shoutout.fromDisplayName.map { "from \($0)" } ?? ""
        return "\(shoutout.category.displayName) shoutout \(from). \(shoutout.message)"
    }
}

// MARK: - API extension

public extension APIClient {
    /// `GET /api/v1/recognition/shoutouts?employee_id=X`
    func listReceivedShoutouts(employeeId: String) async throws -> [RecognitionShoutout] {
        try await get(
            "/api/v1/recognition/shoutouts",
            query: [URLQueryItem(name: "employee_id", value: employeeId)],
            as: [RecognitionShoutout].self
        )
    }
}
