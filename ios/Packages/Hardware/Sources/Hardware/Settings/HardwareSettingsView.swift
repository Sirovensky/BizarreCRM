#if canImport(SwiftUI)
import SwiftUI
import Core

// MARK: - HardwareSettingsView

/// Aggregator settings page: single admin entry that lists all hardware subsections.
///
/// Navigation: Settings → Hardware (this view).
/// Each section contains a `NavigationLink` to its own dedicated settings view.
///
/// Liquid Glass applied to navigation chrome only.
/// Full a11y: labels and hints on all interactive elements.
///
/// RootView wiring snippet (add inside Settings navigation destination):
/// ```swift
/// NavigationLink("Hardware") {
///     HardwareSettingsView()
/// }
/// .accessibilityLabel("Hardware Settings")
/// ```
public struct HardwareSettingsView: View {

    // MARK: - State

    @State private var showBluetoothSettings = false

    public init() {}

    // MARK: - Body

    public var body: some View {
        List {
            printersSection
            bluetoothSection
            scalesSection
            drawerSection
            blockChypSection
        }
        #if !os(macOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("Hardware")
        #if !os(macOS)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        #endif
        .navigationDestination(isPresented: $showBluetoothSettings) {
            BluetoothSettingsView()
        }
    }

    // MARK: - Sections

    private var printersSection: some View {
        Section {
            NavigationLink {
                PrinterSettingsPlaceholderView()
            } label: {
                HardwareRow(
                    icon: "printer",
                    title: "Printers",
                    subtitle: "Receipt printers, label printers"
                )
            }
            .accessibilityLabel("Printers settings")
            .accessibilityHint("Configure receipt and label printers")
        } header: {
            Text("PRINTING")
        }
    }

    private var bluetoothSection: some View {
        Section {
            NavigationLink {
                BluetoothSettingsView()
            } label: {
                HardwareRow(
                    icon: "dot.radiowaves.left.and.right",
                    title: "Bluetooth Devices",
                    subtitle: "Scanners, scales, peripherals"
                )
            }
            .accessibilityLabel("Bluetooth devices settings")
            .accessibilityHint("Discover and pair Bluetooth hardware")
        } header: {
            Text("BLUETOOTH")
        }
    }

    private var scalesSection: some View {
        Section {
            NavigationLink {
                ScaleSettingsPlaceholderView()
            } label: {
                HardwareRow(
                    icon: "scalemass",
                    title: "Weight Scales",
                    subtitle: "Deli scales, postal scales"
                )
            }
            .accessibilityLabel("Weight scale settings")
            .accessibilityHint("Configure connected weight scales")
        } header: {
            Text("SCALES")
        }
    }

    private var drawerSection: some View {
        Section {
            NavigationLink {
                DrawerSettingsPlaceholderView()
            } label: {
                HardwareRow(
                    icon: "tray.full",
                    title: "Cash Drawer",
                    subtitle: "Printer-connected or networked drawer"
                )
            }
            .accessibilityLabel("Cash drawer settings")
            .accessibilityHint("Configure and test the cash drawer")
        } header: {
            Text("CASH DRAWER")
        }
    }

    private var blockChypSection: some View {
        Section {
            NavigationLink {
                BlockChypSettingsPlaceholderView()
            } label: {
                HardwareRow(
                    icon: "creditcard",
                    title: "BlockChyp Terminal",
                    subtitle: "Card payment terminal pairing"
                )
            }
            .accessibilityLabel("BlockChyp terminal settings")
            .accessibilityHint("Pair and configure the BlockChyp payment terminal")
        } header: {
            Text("PAYMENT TERMINAL")
        }
    }
}

// MARK: - HardwareRow

private struct HardwareRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 28)
        }
    }
}

// MARK: - Placeholder views (sibling agents own the real implementations)

private struct PrinterSettingsPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Printer Settings",
            systemImage: "printer",
            description: Text("Managed by the Printing agent (§17.4).")
        )
        .navigationTitle("Printers")
    }
}

private struct ScaleSettingsPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Scale Settings",
            systemImage: "scalemass",
            description: Text("Select a scale under Bluetooth Devices to configure it.")
        )
        .navigationTitle("Weight Scales")
    }
}

private struct DrawerSettingsPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Drawer Settings",
            systemImage: "tray.full",
            description: Text("Pair a receipt printer with a drawer port to enable this.")
        )
        .navigationTitle("Cash Drawer")
    }
}

private struct BlockChypSettingsPlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "BlockChyp Terminal",
            systemImage: "creditcard",
            description: Text("Managed by the BlockChyp terminal agent (§17.3).")
        )
        .navigationTitle("BlockChyp Terminal")
    }
}
#endif
