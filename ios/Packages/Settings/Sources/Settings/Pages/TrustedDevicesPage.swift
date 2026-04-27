import SwiftUI
import Core

// MARK: - §19.2 Trusted devices — mark device to skip 2FA (90-day expiry)
//
// Server: GET  /auth/trusted-devices  → [TrustedDevice]
//         POST /auth/trusted-devices/current → marks current device trusted
//         DELETE /auth/trusted-devices/:id → revokes trust

// MARK: - Model

public struct TrustedDevice: Identifiable, Decodable, Sendable {
    public let id: String
    public let deviceName: String
    public let deviceModel: String
    public let trustedAt: Date
    public let expiresAt: Date
    public let isCurrentDevice: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case deviceName = "device_name"
        case deviceModel = "device_model"
        case trustedAt = "trusted_at"
        case expiresAt = "expires_at"
        case isCurrentDevice = "is_current_device"
    }
}

// MARK: - ViewModel

@MainActor @Observable
public final class TrustedDevicesViewModel {

    public var devices: [TrustedDevice] = []
    public var isLoading: Bool = false
    public var errorMessage: String?
    public var isTrustingCurrent: Bool = false

    private let api: APIClientProtocol
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public init(api: APIClientProtocol) {
        self.api = api
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let data: Data = try await api.get("auth/trusted-devices")
            devices = try decoder.decode([TrustedDevice].self, from: data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func trustCurrentDevice() async {
        isTrustingCurrent = true
        defer { isTrustingCurrent = false }
        do {
            let _: Data = try await api.post("auth/trusted-devices/current", body: EmptyBody())
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func revoke(_ device: TrustedDevice) async {
        do {
            try await api.delete("auth/trusted-devices/\(device.id)")
            devices.removeAll { $0.id == device.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

public struct TrustedDevicesPage: View {

    @State private var vm: TrustedDevicesViewModel

    public init(api: APIClientProtocol) {
        _vm = State(wrappedValue: TrustedDevicesViewModel(api: api))
    }

    public var body: some View {
        List {
            if let error = vm.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.brandBodyMedium())
                }
            }

            // Current device trust section
            let current = vm.devices.first(where: \.isCurrentDevice)
            Section {
                if let device = current {
                    TrustedDeviceRow(device: device, onRevoke: { Task { await vm.revoke(device) } })
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                            Text("This Device")
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreOnSurface)
                            Text("Not trusted — 2FA required each login")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                        Spacer()
                        Button {
                            Task { await vm.trustCurrentDevice() }
                        } label: {
                            if vm.isTrustingCurrent {
                                ProgressView()
                            } else {
                                Text("Trust")
                                    .font(.brandLabelMedium().weight(.semibold))
                                    .foregroundStyle(.bizarreOrange)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(vm.isTrustingCurrent)
                        .accessibilityIdentifier("trustedDevices.trustCurrent")
                    }
                }
            } header: {
                Text("This Device")
            } footer: {
                Text("Trusted devices skip 2FA for 90 days. Revoking trust re-enables 2FA at next login.")
                    .font(.brandLabelSmall())
            }

            // Other trusted devices
            let others = vm.devices.filter { !$0.isCurrentDevice }
            if !others.isEmpty {
                Section("Other Trusted Devices") {
                    ForEach(others) { device in
                        TrustedDeviceRow(device: device, onRevoke: { Task { await vm.revoke(device) } })
                    }
                }
            }
        }
        .navigationTitle("Trusted Devices")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await vm.load() }
        .task { await vm.load() }
        .overlay {
            if vm.isLoading && vm.devices.isEmpty {
                ProgressView()
            }
        }
    }
}

// MARK: - Row

private struct TrustedDeviceRow: View {
    let device: TrustedDevice
    var onRevoke: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private var icon: String {
        device.deviceModel.lowercased().contains("ipad") ? "ipad" : "iphone"
    }

    private var isExpired: Bool { device.expiresAt < .now }

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(device.isCurrentDevice ? .bizarreOrange : .bizarreOnSurfaceMuted)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                HStack(spacing: BrandSpacing.xs) {
                    Text(device.deviceName)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    if device.isCurrentDevice {
                        Text("This device")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurface)
                            .padding(.horizontal, BrandSpacing.xs)
                            .padding(.vertical, 2)
                            .background(.bizarreOrange.opacity(0.15), in: Capsule())
                    }
                    if isExpired {
                        Text("Expired")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.red.opacity(0.8))
                            .padding(.horizontal, BrandSpacing.xs)
                            .padding(.vertical, 2)
                            .background(.red.opacity(0.1), in: Capsule())
                    }
                }

                Text("Trusted \(Self.dateFormatter.string(from: device.trustedAt)) · Expires \(Self.dateFormatter.string(from: device.expiresAt))")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            Spacer()

            Button {
                onRevoke()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityLabel("Revoke trust for \(device.deviceName)")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trustedDevices.revoke.\(device.id)")
        }
    }
}

// MARK: - Helpers

private struct EmptyBody: Encodable {}

#if DEBUG
#Preview("Trusted Devices") {
    NavigationStack {
        TrustedDevicesPage(api: MockAPIClient())
    }
}
#endif
