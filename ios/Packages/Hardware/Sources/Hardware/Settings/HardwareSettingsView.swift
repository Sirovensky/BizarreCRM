#if canImport(SwiftUI)
import SwiftUI
import Core

// MARK: - HardwareSettingsView
//
// Aggregator settings page: single admin entry that lists all hardware subsections.
//
// Navigation: Settings → Hardware (this view).
// Each section links to its dedicated settings view.
//
// iPhone: compact List layout (TabView shell calls this from Settings tab).
// iPad:   NavigationSplitView sidebar; this view is the list column.
//         Detail column is seeded with the first row (Printers) on appear.
//
// Liquid Glass on navigation chrome only (toolbarBackground).
// Full a11y: every interactive element has .accessibilityLabel + .accessibilityHint.
//
// RootView wiring snippet:
// ```swift
// NavigationLink("Hardware") { HardwareSettingsView() }
//     .accessibilityLabel("Hardware Settings")
// ```

public struct HardwareSettingsView: View {

    // MARK: - State

    @State private var selectedSection: HardwareSection? = nil
    @Environment(\.horizontalSizeClass) private var hSizeClass

    public init() {}

    // MARK: - Body

    public var body: some View {
        if hSizeClass == .regular {
            ipadLayout
        } else {
            iphoneLayout
        }
    }

    // MARK: - iPhone layout (compact)

    private var iphoneLayout: some View {
        List {
            allSections
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Hardware")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }

    // MARK: - iPad layout (regular — NavigationSplitView sidebar + detail)

    private var ipadLayout: some View {
        NavigationSplitView {
            List(HardwareSection.allCases, selection: $selectedSection) { section in
                NavigationLink(value: section) {
                    HardwareRow(
                        icon: section.icon,
                        title: section.title,
                        subtitle: section.subtitle
                    )
                }
                .accessibilityLabel(section.accessibilityLabel)
                .accessibilityHint(section.accessibilityHint)
            }
            .listStyle(.sidebar)
            .navigationTitle("Hardware")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        } detail: {
            if let section = selectedSection {
                detailView(for: section)
            } else {
                ContentUnavailableView(
                    "Select a hardware category",
                    systemImage: "gearshape.2",
                    description: Text("Choose a category from the sidebar.")
                )
            }
        }
        .onAppear {
            if selectedSection == nil { selectedSection = .printers }
        }
    }

    // MARK: - Sections list (shared between iPhone and iPad list column)

    @ViewBuilder
    private var allSections: some View {
        Section("PRINTING") {
            NavigationLink {
                PrinterSettingsView()
            } label: {
                HardwareRow(icon: "printer", title: "Printers",
                            subtitle: "Receipt printers, label printers")
            }
            .accessibilityLabel("Printers settings")
            .accessibilityHint("Configure receipt and label printers")
        }

        Section("BLUETOOTH") {
            NavigationLink {
                BluetoothSettingsView()
            } label: {
                HardwareRow(icon: "dot.radiowaves.left.and.right",
                            title: "Bluetooth Devices",
                            subtitle: "Scanners, scales, peripherals")
            }
            .accessibilityLabel("Bluetooth devices settings")
            .accessibilityHint("Discover and pair Bluetooth hardware")
        }

        Section("SCALES") {
            NavigationLink {
                ScaleSettingsView()
            } label: {
                HardwareRow(icon: "scalemass", title: "Weight Scales",
                            subtitle: "Deli scales, postal scales")
            }
            .accessibilityLabel("Weight scale settings")
            .accessibilityHint("Configure connected weight scales")
        }

        Section("CASH DRAWER") {
            NavigationLink {
                DrawerSettingsPlaceholder()
            } label: {
                HardwareRow(icon: "tray.full", title: "Cash Drawer",
                            subtitle: "Printer-connected or networked drawer")
            }
            .accessibilityLabel("Cash drawer settings")
            .accessibilityHint("Configure and test the cash drawer")
        }

        Section("PAYMENT TERMINAL") {
            NavigationLink {
                // BlockChypPairingView requires credentials injected by Settings
                // owner. Placeholder navigates until Settings wires real credentials.
                BlockChypPlaceholderDestination()
            } label: {
                HardwareRow(icon: "creditcard", title: "BlockChyp Terminal",
                            subtitle: "Card payment terminal pairing")
            }
            .accessibilityLabel("BlockChyp terminal settings")
            .accessibilityHint("Pair and configure the BlockChyp payment terminal")
        }
    }

    // MARK: - iPad detail router

    @ViewBuilder
    private func detailView(for section: HardwareSection) -> some View {
        switch section {
        case .printers:
            PrinterSettingsView()
        case .bluetooth:
            BluetoothSettingsView()
        case .scales:
            ScaleSettingsView()
        case .drawer:
            DrawerSettingsPlaceholder()
        case .terminal:
            BlockChypPlaceholderDestination()
        }
    }
}

// MARK: - HardwareSection enum (for NavigationSplitView selection)

enum HardwareSection: String, CaseIterable, Identifiable, Hashable {
    case printers, bluetooth, scales, drawer, terminal

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .printers:  return "printer"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        case .scales:    return "scalemass"
        case .drawer:    return "tray.full"
        case .terminal:  return "creditcard"
        }
    }

    var title: String {
        switch self {
        case .printers:  return "Printers"
        case .bluetooth: return "Bluetooth Devices"
        case .scales:    return "Weight Scales"
        case .drawer:    return "Cash Drawer"
        case .terminal:  return "BlockChyp Terminal"
        }
    }

    var subtitle: String {
        switch self {
        case .printers:  return "Receipt printers, label printers"
        case .bluetooth: return "Scanners, scales, peripherals"
        case .scales:    return "Deli scales, postal scales"
        case .drawer:    return "Printer-connected or networked drawer"
        case .terminal:  return "Card payment terminal pairing"
        }
    }

    var accessibilityLabel: String { "\(title) settings" }
    var accessibilityHint: String {
        switch self {
        case .printers:  return "Configure receipt and label printers"
        case .bluetooth: return "Discover and pair Bluetooth hardware"
        case .scales:    return "Configure connected weight scales"
        case .drawer:    return "Configure and test the cash drawer"
        case .terminal:  return "Pair and configure the BlockChyp payment terminal"
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

// MARK: - Sub-destination stubs

/// Scale settings: shows paired BLE scales with status + test-read button.
/// Full implementation wired once ScaleRepository lands (§17.6).
private struct ScaleSettingsPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "Weight Scales",
            systemImage: "scalemass",
            description: Text("Pair a Bluetooth scale via Bluetooth Devices, then it will appear here for configuration.")
        )
        .navigationTitle("Weight Scales")
    }
}

// DrawerSettingsView is defined in Drawer/DrawerSettingsView.swift.
// Placeholder shown when no CashDrawerManager is injected (demo / previews only).
private struct DrawerSettingsPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "Cash Drawer",
            systemImage: "tray.full",
            description: Text("Pair a receipt printer with a drawer RJ-11 port. The drawer is triggered automatically on cash tender.")
        )
        .navigationTitle("Cash Drawer")
    }
}

/// Placeholder shown until Settings owner injects real BlockChyp credentials.
private struct BlockChypPlaceholderDestination: View {
    var body: some View {
        ContentUnavailableView(
            "BlockChyp Terminal",
            systemImage: "creditcard",
            description: Text("Open Settings → Payment to enter your BlockChyp API credentials and pair a terminal.")
        )
        .navigationTitle("BlockChyp Terminal")
    }
}
#endif
