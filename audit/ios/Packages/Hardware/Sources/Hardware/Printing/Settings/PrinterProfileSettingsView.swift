#if canImport(UIKit)
import SwiftUI
import Core

// §17.4 Per-location default printer selection + per-station profile.
//
// Accessible via Settings → Hardware → Printers → "This Station".
// Lets each station (iPad) choose its default receipt and label printer
// independently of other stations in the same location.

// MARK: - PrinterProfileSettingsView

public struct PrinterProfileSettingsView: View {

    @State private var profileStore = PrinterProfileStore()
    @State private var printerStore: PrinterSettingsViewModel
    @State private var profile: PrinterProfile
    @State private var showTestPage = false

    public init(printerStore: PrinterSettingsViewModel) {
        let store = PrinterProfileStore()
        self._printerStore = State(initialValue: printerStore)
        self._profile = State(initialValue: store.currentProfile)
        self._profileStore = State(initialValue: store)
    }

    public var body: some View {
        Form {
            // Station name
            Section("This Station") {
                TextField("Station name (e.g. Front Counter)", text: $profile.stationName)
                    .accessibilityLabel("Station name")
                    .accessibilityHint("A human-readable name for this iPad in the system.")

                LabeledContent("Station ID") {
                    Text(profileStore.currentStationId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Station ID: \(profileStore.currentStationId)")
            }

            // Default receipt printer
            Section("Default Receipt Printer") {
                if printerStore.printers.isEmpty {
                    Text("No printers configured. Add a printer in Settings → Hardware → Printers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Receipt Printer", selection: $profile.defaultReceiptPrinterId) {
                        Text("None").tag(Optional<String>.none)
                        ForEach(printerStore.printers.filter { $0.kind == .thermalReceipt || $0.kind == .documentAirPrint }) { p in
                            Text(p.name).tag(Optional(p.id))
                        }
                    }
                    .accessibilityLabel("Default receipt printer for this station")
                }
            }

            // Default label printer
            Section("Default Label Printer") {
                if printerStore.printers.isEmpty {
                    Text("No printers configured.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Label Printer", selection: $profile.defaultLabelPrinterId) {
                        Text("None").tag(Optional<String>.none)
                        ForEach(printerStore.printers.filter { $0.kind == .label || $0.kind == .documentAirPrint }) { p in
                            Text(p.name).tag(Optional(p.id))
                        }
                    }
                    .accessibilityLabel("Default label printer for this station")
                }
            }

            // Paper size preference
            Section("Paper Size") {
                Picker("Paper size", selection: $profile.paperSize) {
                    ForEach(PrintMediumPreference.allCases, id: \.self) { size in
                        Text(size.rawValue).tag(size)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Paper size preference for this station")
                .accessibilityHint("Overrides the tenant default. Applied when printing receipts and labels.")
            }

            // Test print
            Section {
                Button {
                    showTestPage = true
                } label: {
                    Label("Print Test Page", systemImage: "printer.fill.and.paper.fill")
                }
                .accessibilityLabel("Print test page")
                .accessibilityHint("Sends a diagnostic test page to the default receipt printer for this station.")
            }
        }
        .navigationTitle("Station Profile")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    profileStore.save(profile)
                }
                .accessibilityLabel("Save station profile")
            }
        }
        .sheet(isPresented: $showTestPage) {
            testPageSheet
        }
    }

    // MARK: - Test page sheet

    private var testPageSheet: some View {
        let printerName = profile.defaultReceiptPrinterId
            .flatMap { id in printerStore.printers.first { $0.id == id } }?.name
            ?? "No default printer"

        return NavigationStack {
            ScrollView {
                TestPageView(model: TestPageModel(
                    tenantName: "BizarreCRM",
                    printerName: printerName,
                    printerModel: "ESC/POS Compatible",
                    connection: "Network"
                ))
                .environment(\.printMedium, profile.paperSize.printMedium)
                .padding(16)
                .background(Color.white)
            }
            .navigationTitle("Test Page Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Print") {
                        Task {
                            // Route to default receipt printer
                            if let printerId = profile.defaultReceiptPrinterId,
                               let printer = printerStore.printers.first(where: { $0.id == printerId }) {
                                await printerStore.testPrint(printer)
                            }
                            showTestPage = false
                        }
                    }
                    .accessibilityLabel("Send test page to printer")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showTestPage = false }
                        .accessibilityLabel("Close test page preview")
                }
            }
        }
    }
}
#endif
