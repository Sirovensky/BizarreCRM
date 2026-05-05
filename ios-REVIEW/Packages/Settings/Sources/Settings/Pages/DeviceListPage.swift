import SwiftUI
import Observation
import Core
import DesignSystem

// MARK: - §19 Device Registry — device list page

/// A registered device entry for the tenant fleet.
public struct RegisteredDevice: Identifiable, Sendable {
    public let id: String          // serial / UUID
    public let model: String       // e.g. "iPad Pro 12.9-inch (M4)"
    public let osVersion: String   // e.g. "iPadOS 18.4"
    public let appVersion: String  // e.g. "2.1.4 (603)"
    public let assignedUser: String?
    public let locationName: String?
    public let lastSeen: Date
    public let isCurrentDevice: Bool

    public var isOnline: Bool {
        Date().timeIntervalSince(lastSeen) < 300 // <5 min = online
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class DeviceListViewModel: Sendable {
    public private(set) var devices: [RegisteredDevice] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var searchText: String = ""
    public var remoteSignOutTarget: RegisteredDevice?
    public var showRemoteSignOutConfirm = false

    public init() {}

    public var filteredDevices: [RegisteredDevice] {
        guard !searchText.isEmpty else { return devices }
        return devices.filter {
            $0.model.localizedCaseInsensitiveContains(searchText)
            || ($0.assignedUser?.localizedCaseInsensitiveContains(searchText) ?? false)
            || ($0.locationName?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    public var onlineCount: Int { devices.filter(\.isOnline).count }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        // Stub: replace with APIClient call to GET /api/v1/devices
        try? await Task.sleep(nanoseconds: 300_000_000)
        let now = Date()
        devices = [
            RegisteredDevice(
                id: "dev-1",
                model: "iPad Pro 12.9-inch (M4)",
                osVersion: "iPadOS 18.4",
                appVersion: "2.1.4 (603)",
                assignedUser: "Alejandro R.",
                locationName: "Main St Store",
                lastSeen: now.addingTimeInterval(-60),
                isCurrentDevice: true
            ),
            RegisteredDevice(
                id: "dev-2",
                model: "iPhone 16 Pro",
                osVersion: "iOS 18.4",
                appVersion: "2.1.4 (603)",
                assignedUser: "Maria K.",
                locationName: "Main St Store",
                lastSeen: now.addingTimeInterval(-120),
                isCurrentDevice: false
            ),
            RegisteredDevice(
                id: "dev-3",
                model: "iPad mini (A17 Pro)",
                osVersion: "iPadOS 18.3",
                appVersion: "2.1.2 (591)",
                assignedUser: nil,
                locationName: "Warehouse",
                lastSeen: now.addingTimeInterval(-3600 * 4),
                isCurrentDevice: false
            ),
            RegisteredDevice(
                id: "dev-4",
                model: "iPhone 15",
                osVersion: "iOS 17.7",
                appVersion: "2.0.9 (572)",
                assignedUser: "Dev (unassigned)",
                locationName: nil,
                lastSeen: now.addingTimeInterval(-3600 * 30),
                isCurrentDevice: false
            ),
        ]
    }

    public func remoteSignOut(_ device: RegisteredDevice) async {
        // Stub: POST /api/v1/devices/{id}/sign-out
        try? await Task.sleep(nanoseconds: 200_000_000)
        devices.removeAll { $0.id == device.id }
        AppLog.ui.info("DeviceListVM: remote sign-out \(device.id, privacy: .public)")
    }
}

// MARK: - View

/// §19 Device registry — lists all devices registered to the tenant,
/// shows online status, assigned user, app version, and allows remote sign-out.
public struct DeviceListPage: View {
    @State private var vm = DeviceListViewModel()

    public init() {}

    public var body: some View {
        Group {
            if vm.isLoading && vm.devices.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading devices")
            } else if let err = vm.errorMessage {
                ContentUnavailableView(
                    "Could not load devices",
                    systemImage: "exclamationmark.triangle",
                    description: Text(err)
                )
            } else {
                deviceList
            }
        }
        .navigationTitle("Registered Devices")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .searchable(text: $vm.searchText, prompt: "Search by model, user, or location")
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await vm.load() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("devices.refresh")
            }
        }
        .task { await vm.load() }
        .confirmationDialog(
            "Sign out \(vm.remoteSignOutTarget?.model ?? "device")?",
            isPresented: $vm.showRemoteSignOutConfirm,
            titleVisibility: .visible
        ) {
            if let target = vm.remoteSignOutTarget {
                Button("Sign out remotely", role: .destructive) {
                    Task { await vm.remoteSignOut(target) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The device will be signed out on its next network request. The assigned user will need to sign in again.")
        }
    }

    // MARK: - Device list

    private var deviceList: some View {
        List {
            // Summary header
            Section {
                HStack(spacing: BrandSpacing.lg) {
                    statChip(
                        value: "\(vm.devices.count)",
                        label: "Total",
                        icon: "ipad.and.iphone",
                        color: .bizarreOnSurface
                    )
                    statChip(
                        value: "\(vm.onlineCount)",
                        label: "Online",
                        icon: "circle.fill",
                        color: .bizarreSuccess
                    )
                    statChip(
                        value: "\(vm.devices.count - vm.onlineCount)",
                        label: "Offline",
                        icon: "circle",
                        color: .bizarreOnSurfaceMuted
                    )
                    Spacer()
                }
                .padding(.vertical, BrandSpacing.xs)
                .listRowBackground(Color.bizarreSurface1)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(vm.devices.count) devices total, \(vm.onlineCount) online"
                )
            }

            // Device rows
            Section("Devices") {
                if vm.filteredDevices.isEmpty {
                    Text(vm.searchText.isEmpty ? "No devices registered." : "No results.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .listRowBackground(Color.bizarreSurface1)
                } else {
                    ForEach(vm.filteredDevices) { device in
                        DeviceRow(device: device) {
                            vm.remoteSignOutTarget = device
                            vm.showRemoteSignOutConfirm = true
                        }
                        .listRowBackground(Color.bizarreSurface1)
                    }
                }
            }
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .refreshable { await vm.load() }
    }

    private func statChip(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Text(value)
                    .font(.brandLabelLarge().monospacedDigit())
                    .foregroundStyle(.bizarreOnSurface)
            }
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }
}

// MARK: - Device row

private struct DeviceRow: View {
    let device: RegisteredDevice
    let onRemoteSignOut: () -> Void

    private var lastSeenString: String {
        let interval = Date().timeIntervalSince(device.lastSeen)
        switch interval {
        case ..<60:         return "Just now"
        case ..<3600:       return "\(Int(interval / 60))m ago"
        case ..<86400:      return "\(Int(interval / 3600))h ago"
        default:            return "\(Int(interval / 86400))d ago"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.base) {
            // Online indicator
            Circle()
                .fill(device.isOnline ? Color.bizarreSuccess : Color.bizarreOnSurfaceMuted.opacity(0.4))
                .frame(width: 10, height: 10)
                .padding(.top, 5)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                HStack {
                    Text(device.model)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    if device.isCurrentDevice {
                        Text("This device")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOrange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.bizarreOrange.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Spacer()
                }

                HStack(spacing: BrandSpacing.sm) {
                    Label(device.osVersion, systemImage: "gear")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .labelStyle(.titleAndIcon)
                    Label("App \(device.appVersion)", systemImage: "app.badge")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .labelStyle(.titleOnly)
                }

                if let user = device.assignedUser {
                    Label(user, systemImage: "person")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurface)
                }

                if let loc = device.locationName {
                    Label(loc, systemImage: "mappin.and.ellipse")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

                Text("Last seen: \(lastSeenString)")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !device.isCurrentDevice {
                Button(role: .destructive, action: onRemoteSignOut) {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .accessibilityIdentifier("devices.row.\(device.id).signOut")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(device.model), \(device.isOnline ? "online" : "offline"), "
            + "last seen \(lastSeenString)"
            + (device.isCurrentDevice ? ", this device" : "")
        )
        .accessibilityIdentifier("devices.row.\(device.id)")
    }
}
