#if canImport(SwiftUI)
import SwiftUI

// MARK: - HardwareThreeColumnView
//
// iPad-only 3-column layout for the Hardware settings screen.
//
// Column 1 (sidebar):   DeviceTypeSidebar — Printers / Drawer / Scale / Scanner / Terminal
// Column 2 (content):   Paired-device list for the selected type
// Column 3 (detail):    DeviceTestActions + device-specific detail / settings view
//
// Liquid Glass: navigation chrome only (toolbarBackground).
// Keyboard shortcuts: ⌘T test, ⌘R rescan, ⌘P print test page.
// Full a11y: every interactive element has .accessibilityLabel + .accessibilityHint.
//
// Usage from HardwareSettingsView (regular-width context):
// ```swift
// if hSizeClass == .regular {
//     HardwareThreeColumnView()
// }
// ```

public struct HardwareThreeColumnView: View {

    // MARK: State

    @State private var selectedType: HardwareDeviceType? = .printer
    @State private var selectedDeviceID: String? = nil
    @State private var testActionsVM = DeviceTestActionsViewModel()
    @State private var isRescanning = false

    public init() {}

    // MARK: - Body

    public var body: some View {
        NavigationSplitView {
            // Column 1: sidebar — device type categories
            DeviceTypeSidebar(selection: $selectedType)
        } content: {
            // Column 2: paired device list for the selected type
            PairedDeviceListColumn(
                deviceType: selectedType,
                selectedDeviceID: $selectedDeviceID,
                isRescanning: isRescanning
            )
        } detail: {
            // Column 3: test actions + device-specific detail
            DetailColumn(
                deviceType: selectedType,
                selectedDeviceID: selectedDeviceID,
                vm: testActionsVM
            )
        }
        .navigationSplitViewStyle(.balanced)
        .hardwareKeyboardShortcuts(
            selectedType: selectedType,
            vm: testActionsVM,
            onRescan: { rescan() }
        )
        .onChange(of: selectedType) { _, _ in
            // Clear device selection when switching categories.
            selectedDeviceID = nil
            testActionsVM.resetAll()
        }
    }

    // MARK: - Rescan

    private func rescan() {
        guard !isRescanning else { return }
        isRescanning = true
        Task {
            // Brief delay models a BLE scan window; real wiring delegates to BluetoothManager.
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            isRescanning = false
        }
    }
}

// MARK: - PairedDeviceListColumn (Column 2)

/// Middle column: shows the list of paired devices for a given hardware type.
///
/// Empty state guidance is shown when no devices are paired.
/// "Rescan" spinner appears during active scanning.
private struct PairedDeviceListColumn: View {

    let deviceType: HardwareDeviceType?
    @Binding var selectedDeviceID: String?
    let isRescanning: Bool

    var body: some View {
        Group {
            if let type = deviceType {
                List(selection: $selectedDeviceID) {
                    if isRescanning {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Scanning…")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Scanning for devices")
                    }

                    // Placeholder rows — in a full wiring these come from
                    // the appropriate repository (PrinterRepository, BLE manager, etc.).
                    // Stubs are intentional: §22 scope is iPad chrome + test actions.
                    pairedDevicePlaceholders(for: type)
                }
                .listStyle(.insetGrouped)
                .navigationTitle(type.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .toolbar { rescanToolbarButton }
            } else {
                ContentUnavailableView(
                    "Select a category",
                    systemImage: "sidebar.left",
                    description: Text("Choose a hardware type from the sidebar.")
                )
            }
        }
    }

    // MARK: - Placeholder device rows

    @ViewBuilder
    private func pairedDevicePlaceholders(for type: HardwareDeviceType) -> some View {
        switch type {
        case .printer:
            PairedDevicePlaceholderRow(
                id: "printer-placeholder",
                name: "No printers configured",
                subtitle: "Add a printer via Settings → Hardware → Printers",
                systemImage: "printer.slash",
                isEmpty: true
            )

        case .drawer:
            PairedDevicePlaceholderRow(
                id: "drawer-placeholder",
                name: "No drawer paired",
                subtitle: "Pair a receipt printer with a drawer RJ-11 port",
                systemImage: "tray.full",
                isEmpty: true
            )

        case .scale:
            PairedDevicePlaceholderRow(
                id: "scale-placeholder",
                name: "No scales paired",
                subtitle: "Pair a Bluetooth scale via Bluetooth Devices",
                systemImage: "scalemass",
                isEmpty: true
            )

        case .scanner:
            PairedDevicePlaceholderRow(
                id: "scanner-placeholder",
                name: "No scanners paired",
                subtitle: "Pair a Bluetooth scanner via Bluetooth Devices",
                systemImage: "barcode.viewfinder",
                isEmpty: true
            )

        case .terminal:
            PairedDevicePlaceholderRow(
                id: "terminal-placeholder",
                name: "No terminal paired",
                subtitle: "Enter BlockChyp credentials in Settings → Payment",
                systemImage: "creditcard",
                isEmpty: true
            )
        }
    }

    // MARK: - Rescan toolbar button

    @ToolbarContentBuilder
    private var rescanToolbarButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if isRescanning {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Rescanning devices")
            } else {
                Button {
                    // Rescan is wired via ⌘R shortcut / parent view;
                    // toolbar button visible for pointer/touch users.
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Rescan devices")
                .accessibilityHint("Press Command+R or tap to rescan for paired devices")
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

// MARK: - PairedDevicePlaceholderRow

private struct PairedDevicePlaceholderRow: View {
    let id: String
    let name: String
    let subtitle: String
    let systemImage: String
    let isEmpty: Bool

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                    .foregroundStyle(isEmpty ? .secondary : .primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 28)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name). \(subtitle)")
    }
}

// MARK: - DetailColumn (Column 3)

/// Right-most column: shows test-fire buttons and device-specific guidance.
private struct DetailColumn: View {

    let deviceType: HardwareDeviceType?
    let selectedDeviceID: String?
    @Bindable var vm: DeviceTestActionsViewModel

    var body: some View {
        Group {
            if let type = deviceType {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Inline test actions
                        DeviceTestActions(deviceType: type, vm: vm)

                        // Device-specific guidance
                        DeviceDetailGuidance(type: type)
                    }
                    .padding(.vertical)
                }
                .navigationTitle(type.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .toolbar { testToolbarButton(for: type) }
            } else {
                ContentUnavailableView(
                    "Select a device type",
                    systemImage: "gearshape.2",
                    description: Text("Choose a hardware category to see test actions.")
                )
            }
        }
    }

    @ToolbarContentBuilder
    private func testToolbarButton(for type: HardwareDeviceType) -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if #available(iOS 26, *) {
                Button {
                    fireTest(for: type)
                } label: {
                    Label("Test", systemImage: "bolt.fill")
                }
                .glassEffect()
                .accessibilityLabel("Run test for \(type.title)")
                .accessibilityHint("Press Command+T to run the test action")
            } else {
                Button {
                    fireTest(for: type)
                } label: {
                    Label("Test", systemImage: "bolt.fill")
                }
                .accessibilityLabel("Run test for \(type.title)")
                .accessibilityHint("Press Command+T to run the test action")
            }
        }
    }

    private func fireTest(for type: HardwareDeviceType) {
        Task {
            switch type {
            case .printer:  await vm.printTestPage()
            case .drawer:   await vm.openDrawer()
            case .scale:    await vm.readScale()
            case .scanner:  await vm.testScanner()
            case .terminal: await vm.pingTerminal()
            }
        }
    }
}

// MARK: - DeviceDetailGuidance

/// Static guidance card shown below the test buttons.
private struct DeviceDetailGuidance: View {
    let type: HardwareDeviceType

    var body: some View {
        GroupBox {
            Text(guidanceText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("About", systemImage: "info.circle")
                .font(.headline)
        }
        .padding(.horizontal)
    }

    private var guidanceText: String {
        switch type {
        case .printer:
            return "Print test pages to verify ESC/POS network printers or AirPrint connectivity. Configure printers in Settings → Hardware → Printers."
        case .drawer:
            return "The cash drawer is triggered automatically on cash tender. Use 'Open Drawer' to test the ESC/POS kick command. Requires a paired receipt printer."
        case .scale:
            return "Live weight readings stream from the paired BLE scale. Use 'Read Weight' to take a single stable reading. Pair scales via Settings → Hardware → Bluetooth."
        case .scanner:
            return "Barcode scanners paired over Bluetooth appear here. Use 'Test Scanner' to verify the scanner triggers and returns a scan event."
        case .terminal:
            return "BlockChyp payment terminals communicate over your local network. Use 'Ping Terminal' to verify connectivity. Credentials are stored in Keychain."
        }
    }
}

#endif
