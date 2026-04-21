#if canImport(UIKit)
import SwiftUI
import Core

// MARK: - PrinterSettingsView
//
// Admin settings for hardware printers. Accessible via:
//   Settings → Hardware → Printers
//
// Wiring snippet for RootView.swift (add inside NavigationLink chain):
// ```swift
// NavigationLink("Printers") {
//     PrinterSettingsView()
// }
// ```
//
// Liquid Glass applied to toolbar only (per §30 rule: chrome, not content).

public struct PrinterSettingsView: View {

    @State private var vm = PrinterSettingsViewModel()
    @State private var showAddAirPrint = false
    @State private var showAddNetworkForm = false
    @State private var printerForAction: PersistedPrinter?

    public init() {}

    public var body: some View {
        List {
            if vm.printers.isEmpty {
                emptyStateSection
            } else {
                printerListSection
            }
            addSection
        }
        .navigationTitle("Printers")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            toolbarContent
        }
        .overlay {
            if vm.isLoading {
                loadingOverlay
            }
        }
        .alert("Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .sheet(isPresented: $showAddNetworkForm) {
            addNetworkPrinterSheet
        }
    }

    // MARK: - Sections

    private var emptyStateSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "printer.slash")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("No printers configured")
                    .font(.headline)
                Text("Add an AirPrint printer or enter an ESC/POS network printer IP below.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No printers configured. Use the add buttons below to pair a printer.")
    }

    private var printerListSection: some View {
        Section("Configured Printers") {
            ForEach(vm.printers) { printer in
                PrinterRow(printer: printer) {
                    Task { await vm.testPrint(printer) }
                } onSetDefaultReceipt: {
                    vm.setAsDefaultReceipt(printer)
                } onSetDefaultLabel: {
                    vm.setAsDefaultLabel(printer)
                } onRemove: {
                    vm.remove(printer)
                }
            }
        }
    }

    private var addSection: some View {
        Section("Add Printer") {
            Button {
                showAddAirPrint = true
            } label: {
                Label("Add AirPrint Printer", systemImage: "printer.fill")
            }
            .accessibilityLabel("Add AirPrint printer. Opens printer picker.")

            Button {
                showAddNetworkForm = true
            } label: {
                Label("Add ESC/POS Network Printer", systemImage: "network")
            }
            .accessibilityLabel("Add ESC/POS network printer. Enter IP address and port.")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if #available(iOS 26, *) {
                Menu {
                    menuItems
                } label: {
                    Image(systemName: "plus")
                }
                .glassEffect()
            } else {
                Menu {
                    menuItems
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("Add AirPrint Printer") { showAddAirPrint = true }
        Button("Add ESC/POS Network Printer") { showAddNetworkForm = true }
    }

    // MARK: - Loading overlay

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea()
            ProgressView("Working…")
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Add Network Printer Sheet

    private var addNetworkPrinterSheet: some View {
        NavigationStack {
            Form {
                Section("Printer Details") {
                    TextField("Nickname (optional)", text: $vm.newPrinterNickname)
                        .accessibilityLabel("Printer nickname, optional")
                    TextField("IP Address or Hostname", text: $vm.newPrinterHost)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("Printer IP address or hostname, required")
                    TextField("Port", text: $vm.newPrinterPort)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("Port number, default 9100")
                }
                Section {
                    Button("Test & Save") {
                        Task {
                            await vm.addNetworkPrinter()
                            if vm.errorMessage == nil {
                                showAddNetworkForm = false
                            }
                        }
                    }
                    .disabled(vm.newPrinterHost.trimmingCharacters(in: .whitespaces).isEmpty || vm.isLoading)
                    .accessibilityLabel("Test connection and save printer")
                }
                if let err = vm.errorMessage {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .accessibilityLabel("Error: \(err)")
                    }
                }
            }
            .navigationTitle("ESC/POS Network Printer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddNetworkForm = false }
                }
            }
        }
    }
}

// MARK: - Printer Row

private struct PrinterRow: View {
    let printer: PersistedPrinter
    let onTestPrint: () -> Void
    let onSetDefaultReceipt: () -> Void
    let onSetDefaultLabel: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: printerIcon)
                    .foregroundStyle(printerIconColor)
                    .accessibilityHidden(true)
                Text(printer.name)
                    .font(.headline)
                Spacer()
                defaultBadges
            }
            Text(printer.connection.displayString)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Test Print") { onTestPrint() }
            Divider()
            if !printer.isDefaultReceipt {
                Button("Set as Default Receipt Printer") { onSetDefaultReceipt() }
            }
            if !printer.isDefaultLabel {
                Button("Set as Default Label Printer") { onSetDefaultLabel() }
            }
            Divider()
            Button("Remove", role: .destructive) { onRemove() }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Remove", role: .destructive) { onRemove() }
            Button("Test") { onTestPrint() }
                .tint(.blue)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double-tap to open actions. Swipe left for quick actions.")
    }

    private var accessibilityLabel: String {
        var parts: [String] = [printer.name]
        parts.append(printer.kind.accessibilityDescription)
        parts.append(printer.connection.displayString)
        if printer.isDefaultReceipt { parts.append("Default receipt printer") }
        if printer.isDefaultLabel { parts.append("Default label printer") }
        return parts.joined(separator: ". ")
    }

    @ViewBuilder
    private var defaultBadges: some View {
        if printer.isDefaultReceipt {
            Text("Receipt")
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.blue.opacity(0.15), in: Capsule())
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
        }
        if printer.isDefaultLabel {
            Text("Label")
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.green.opacity(0.15), in: Capsule())
                .foregroundStyle(.green)
                .accessibilityHidden(true)
        }
    }

    private var printerIcon: String {
        switch printer.kind {
        case .thermalReceipt:   return "printer.fill"
        case .label:            return "tag.fill"
        case .documentAirPrint: return "printer"
        }
    }

    private var printerIconColor: Color {
        switch printer.connection {
        case .airPrint:      return .blue
        case .network:       return .orange
        case .bluetoothMFi:  return .purple
        }
    }
}

// MARK: - A11y extensions

private extension PrinterKind {
    var accessibilityDescription: String {
        switch self {
        case .thermalReceipt:   return "Thermal receipt printer"
        case .label:            return "Label printer"
        case .documentAirPrint: return "AirPrint document printer"
        }
    }
}

#endif
