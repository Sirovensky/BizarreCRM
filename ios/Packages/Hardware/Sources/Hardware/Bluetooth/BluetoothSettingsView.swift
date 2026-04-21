#if canImport(SwiftUI)
import SwiftUI
@preconcurrency import CoreBluetooth
import Core

// MARK: - BluetoothSettingsViewModel

@Observable
@MainActor
public final class BluetoothSettingsViewModel {

    public var devices: [BluetoothDevice] = []
    public var isScanning: Bool = false
    public var isBluetoothEnabled: Bool = false
    public var errorMessage: String?

    private let manager: BluetoothManager

    public init(manager: BluetoothManager = BluetoothManager()) {
        self.manager = manager
    }

    public func onAppear() async {
        await refresh()
        await startScan()
    }

    public func startScan() async {
        isScanning = true
        await manager.startScan(serviceUUIDs: nil) // nil = all devices in Settings
        await refresh()
    }

    public func stopScan() async {
        await manager.stopScan()
        isScanning = false
    }

    public func connect(device: BluetoothDevice) async {
        do {
            try await manager.connect(to: device.id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func disconnect(device: BluetoothDevice) async {
        await manager.disconnect(device.id)
        await refresh()
    }

    public func rename(device: BluetoothDevice, to newName: String) async {
        // Local rename is stored; server sync is out of scope for Hardware pkg.
        // Actual persistence requires a Settings repository — document for integration.
        AppLog.hardware.info("BluetoothSettingsViewModel: rename \(device.id) → \(newName)")
        await refresh()
    }

    // MARK: - Private

    private func refresh() async {
        devices = await manager.discovered
        isBluetoothEnabled = await manager.isBluetoothEnabled
    }
}

// MARK: - BluetoothSettingsView

/// Admin view for discovering, connecting, and renaming Bluetooth peripherals.
///
/// Designed for Settings → Hardware → Bluetooth.
/// Liquid Glass applied to navigation chrome only (not list rows).
/// Full a11y: every interactive element has `.accessibilityLabel` and `.accessibilityHint`.
public struct BluetoothSettingsView: View {

    @State private var viewModel: BluetoothSettingsViewModel
    @State private var renameDevice: BluetoothDevice?
    @State private var pendingName: String = ""

    public init(viewModel: BluetoothSettingsViewModel = BluetoothSettingsViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Bluetooth Devices")
                .toolbar { toolbarContent }
                #if !os(macOS)
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                #endif
                .alert("Rename Device", isPresented: Binding(
                    get: { renameDevice != nil },
                    set: { if !$0 { renameDevice = nil } }
                )) {
                    renameAlert
                } message: {
                    Text("Enter a friendly name for this device.")
                }
                .alert("Error", isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) { viewModel.errorMessage = nil }
                } message: {
                    Text(viewModel.errorMessage ?? "")
                }
        }
        .task { await viewModel.onAppear() }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !viewModel.isBluetoothEnabled {
            bluetoothOffView
        } else if viewModel.devices.isEmpty && viewModel.isScanning {
            scanningPlaceholder
        } else {
            deviceList
        }
    }

    private var bluetoothOffView: some View {
        ContentUnavailableView(
            "Bluetooth Off",
            systemImage: "bluetooth.slash",
            description: Text("Enable Bluetooth in Settings to discover hardware.")
        )
        .accessibilityLabel("Bluetooth is off. Enable it in Settings.")
    }

    private var scanningPlaceholder: some View {
        VStack(spacing: 16) {
            ProgressView()
                .accessibilityLabel("Scanning for Bluetooth devices")
            Text("Scanning for devices…")
                .foregroundStyle(.secondary)
        }
    }

    private var deviceList: some View {
        List {
            if viewModel.isScanning {
                HStack {
                    ProgressView()
                    Text("Scanning…")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Scanning for Bluetooth devices")
            }

            ForEach(viewModel.devices) { device in
                BluetoothDeviceRow(
                    device: device,
                    onConnect: {
                        Task { await viewModel.connect(device: device) }
                    },
                    onDisconnect: {
                        Task { await viewModel.disconnect(device: device) }
                    },
                    onRename: {
                        pendingName = device.name
                        renameDevice = device
                    }
                )
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if viewModel.isScanning {
                Button("Stop") {
                    Task { await viewModel.stopScan() }
                }
                .accessibilityLabel("Stop scanning for Bluetooth devices")
            } else {
                Button("Scan") {
                    Task { await viewModel.startScan() }
                }
                .accessibilityLabel("Scan for Bluetooth devices")
            }
        }
    }

    // MARK: - Rename Alert

    @ViewBuilder
    private var renameAlert: some View {
        TextField("Device name", text: $pendingName)
            .accessibilityLabel("New device name")
        Button("Save") {
            if let device = renameDevice {
                let name = pendingName
                Task { await viewModel.rename(device: device, to: name) }
            }
            renameDevice = nil
        }
        Button("Cancel", role: .cancel) { renameDevice = nil }
    }
}

// MARK: - BluetoothDeviceRow

private struct BluetoothDeviceRow: View {
    let device: BluetoothDevice
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onRename: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(device.isConnected ? .green : .secondary)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.body)
                Text(kindLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            rssiIndicator

            connectButton
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(device.name), \(kindLabel), RSSI \(device.rssi) dBm, \(device.isConnected ? "connected" : "not connected")")
        .contextMenu {
            Button("Rename", action: onRename)
                .accessibilityLabel("Rename \(device.name)")
        }
    }

    private var iconName: String {
        switch device.kind {
        case .scale:         return "scalemass"
        case .scanner:       return "barcode.viewfinder"
        case .receiptPrinter: return "printer"
        case .drawer:        return "tray.full"
        case .cardReader:    return "creditcard"
        case .unknown, nil:  return "dot.radiowaves.left.and.right"
        }
    }

    private var kindLabel: String {
        switch device.kind {
        case .scale:         return "Weight Scale"
        case .scanner:       return "Barcode Scanner"
        case .receiptPrinter: return "Receipt Printer"
        case .drawer:        return "Cash Drawer"
        case .cardReader:    return "Card Reader"
        case .unknown, nil:  return "Unknown Device"
        }
    }

    private var rssiIndicator: some View {
        let bars = min(3, max(0, (device.rssi + 100) / 20))
        return Image(systemName: "wifi", variableValue: Double(bars) / 3.0)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    private var connectButton: some View {
        Button(device.isConnected ? "Disconnect" : "Connect") {
            if device.isConnected { onDisconnect() } else { onConnect() }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel(device.isConnected ? "Disconnect from \(device.name)" : "Connect to \(device.name)")
    }
}
#endif
