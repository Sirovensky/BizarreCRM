import SwiftUI
import Networking
import Observation
import Core
import DesignSystem

// MARK: - §19.2 Active sessions — list device + last-seen + location (IP); revoke.

// MARK: - Models

public struct ActiveSession: Identifiable, Decodable, Sendable {
    public let id: String
    public let deviceName: String
    public let deviceModel: String
    public let ipAddress: String
    public let location: String?
    public let lastSeenAt: Date
    public let isCurrentDevice: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case deviceName  = "device_name"
        case deviceModel = "device_model"
        case ipAddress   = "ip_address"
        case location
        case lastSeenAt  = "last_seen_at"
        case isCurrentDevice = "is_current_device"
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class ActiveSessionsViewModel {

    public var sessions: [ActiveSession] = []
    public var isLoading: Bool = false
    public var errorMessage: String?
    public var sessionToRevoke: ActiveSession?
    public var showRevokeConfirm: Bool = false

    private let api: APIClient?

    public init(api: APIClient? = nil) {
        self.api = api
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            guard let api else { return }
            let wire = try await api.securityListSessions()
            sessions = wire.map { w in
                ActiveSession(
                    id: w.id,
                    deviceName: w.deviceName,
                    deviceModel: w.deviceModel,
                    ipAddress: w.ipAddress,
                    location: w.location,
                    lastSeenAt: w.lastSeenAt,
                    isCurrentDevice: w.isCurrentDevice
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func requestRevoke(_ session: ActiveSession) {
        sessionToRevoke = session
        showRevokeConfirm = true
    }

    public func confirmRevoke() async {
        guard let session = sessionToRevoke else { return }
        showRevokeConfirm = false
        do {
            try await api?.securityRevokeSession(id: session.id)
            sessions.removeAll { $0.id == session.id }
        } catch {
            errorMessage = error.localizedDescription
        }
        sessionToRevoke = nil
    }

    public func revokeAll() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await api?.securityRevokeAllSessions()
            sessions = sessions.filter(\.isCurrentDevice)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

public struct ActiveSessionsPage: View {

    @State private var vm: ActiveSessionsViewModel
    @State private var showRevokeAllConfirm = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    public init(api: APIClient? = nil) {
        _vm = State(initialValue: ActiveSessionsViewModel(api: api))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()

            if vm.isLoading && vm.sessions.isEmpty {
                ProgressView()
                    .accessibilityLabel("Loading sessions")
            } else {
                List {
                    if let error = vm.errorMessage {
                        Section {
                            Text(error)
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreError)
                                .accessibilityLabel("Error: \(error)")
                        }
                    }

                    ForEach(vm.sessions) { session in
                        sessionRow(session)
                    }

                    if vm.sessions.count > 1 {
                        Section {
                            Button(role: .destructive) {
                                showRevokeAllConfirm = true
                            } label: {
                                Label("Sign out of all other devices", systemImage: "rectangle.portrait.and.arrow.right")
                                    .foregroundStyle(.bizarreError)
                            }
                            .accessibilityIdentifier("sessions.revokeAll")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .refreshable { await vm.load() }
            }
        }
        .navigationTitle("Active Sessions")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await vm.load() }
        .confirmationDialog(
            "Revoke session for \(vm.sessionToRevoke?.deviceName ?? "this device")?",
            isPresented: $vm.showRevokeConfirm,
            titleVisibility: .visible
        ) {
            Button("Sign out device", role: .destructive) {
                Task { await vm.confirmRevoke() }
            }
            Button("Cancel", role: .cancel) {
                vm.sessionToRevoke = nil
            }
        }
        .alert("Sign out all other devices?", isPresented: $showRevokeAllConfirm) {
            Button("Sign out all", role: .destructive) {
                Task { await vm.revokeAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All sessions except this device will be immediately revoked.")
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: ActiveSession) -> some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: deviceIcon(model: session.deviceModel))
                .font(.title3)
                .foregroundStyle(session.isCurrentDevice ? .bizarreOrange : .secondary)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: BrandSpacing.xs) {
                    Text(session.deviceName)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    if session.isCurrentDevice {
                        Text("This device")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOrange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.bizarreOrange.opacity(0.15), in: Capsule())
                    }
                }
                Text("\(session.ipAddress)\(session.location.map { " · \($0)" } ?? "")")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text("Last seen \(Self.relativeFormatter.localizedString(for: session.lastSeenAt, relativeTo: Date()))")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            Spacer()

            if !session.isCurrentDevice {
                Button {
                    vm.requestRevoke(session)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.bizarreError.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Revoke session for \(session.deviceName)")
                .accessibilityIdentifier("sessions.revoke.\(session.id)")
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.bizarreSurface1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(session.deviceName)\(session.isCurrentDevice ? ", this device" : ""), \(session.ipAddress), last seen \(Self.relativeFormatter.localizedString(for: session.lastSeenAt, relativeTo: Date()))"
        )
    }

    private func deviceIcon(model: String) -> String {
        let lower = model.lowercased()
        if lower.contains("ipad")  { return "ipad" }
        if lower.contains("mac")   { return "laptopcomputer" }
        return "iphone"
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        ActiveSessionsPage(api: APIClientImpl())
    }
}
#endif
