#if canImport(SwiftUI)
import SwiftUI
import Core

// MARK: - DrawerSettingsView
//
// §17 Cash drawer: "Test Open drawer button" + "Printer-cash-drawer bind"
//
// Settings → Hardware → Cash Drawer
// Shows:
//  - Printer binding picker (which ESC/POS printer drives the drawer RJ11 port)
//  - Enable/disable toggle for auto-kick on cash/check tenders
//  - "Open Drawer" test button (manager PIN gated in production)
//  - Live status badge (open / closed / warning)
//  - Anti-theft & open-warning configuration
//  - USB direct-to-iPad alternate path note
//
// iPhone: compact scrollable Form
// iPad: same form in a NavigationSplitView detail pane (caller provides split)
//
// The drawer and manager are injected by the caller; this view owns none of the
// hardware state itself — all mutations go through CashDrawerManager.

public struct DrawerSettingsView: View {

    // MARK: - Dependencies (injected)

    private let drawerManager: CashDrawerManager

    // MARK: - Printer binding state

    /// Available ESC/POS printers the drawer RJ11 port can be bound to.
    /// The caller injects this list from PrinterSettingsViewModel.
    public var availablePrinters: [PersistedPrinter]
    /// Identifier of the currently bound printer (persisted in UserDefaults).
    @State private var boundPrinterId: String?

    private static let boundPrinterUdKey = "com.bizarrecrm.drawer.boundPrinterId"

    // MARK: - Local UI state

    @State private var showingPinSheet = false
    @State private var pinEntry = ""
    @State private var testResult: TestResult? = nil
    @State private var isTestInFlight = false

    public init(drawerManager: CashDrawerManager, availablePrinters: [PersistedPrinter] = []) {
        self.drawerManager = drawerManager
        self.availablePrinters = availablePrinters
        self._boundPrinterId = State(
            initialValue: UserDefaults.standard.string(forKey: Self.boundPrinterUdKey)
        )
    }

    // MARK: - Body

    public var body: some View {
        Form {
            // Printer binding
            printerBindingSection

            // Status
            statusSection

            // Trigger settings
            triggerSection

            // Test
            testSection

            // Timing / anti-theft
            timingSection

            // Alternate path
            alternatePathSection
        }
        .onChange(of: boundPrinterId) { _, newId in
            // Persist the binding immediately on change.
            if let id = newId {
                UserDefaults.standard.set(id, forKey: Self.boundPrinterUdKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.boundPrinterUdKey)
            }
        }
        .navigationTitle("Cash Drawer")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .sheet(isPresented: $showingPinSheet) {
            ManagerPinSheet(
                isPresented: $showingPinSheet,
                onSubmit: { pin in
                    Task { await runTest(pin: pin) }
                }
            )
        }
        .onChange(of: drawerManager.errorMessage) { _, newValue in
            if let msg = newValue {
                testResult = .failure(msg)
            }
        }
    }

    // MARK: - Sections

    // MARK: Printer binding

    private var printerBindingSection: some View {
        Section {
            if availablePrinters.isEmpty {
                Label(
                    "No receipt printers configured. Add one in Settings → Hardware → Printers.",
                    systemImage: "printer.slash"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("No receipt printers configured.")
            } else {
                Picker(
                    "Bound Printer",
                    selection: Binding(
                        get: { boundPrinterId ?? "" },
                        set: { boundPrinterId = $0.isEmpty ? nil : $0 }
                    )
                ) {
                    Text("None").tag("")
                    ForEach(availablePrinters) { printer in
                        Text(printer.name).tag(printer.id)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Receipt printer that drives this cash drawer via its RJ11 port.")

                if let id = boundPrinterId,
                   let bound = availablePrinters.first(where: { $0.id == id }) {
                    Label("Drawer kicks via \(bound.name)", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .accessibilityLabel("Drawer is bound to \(bound.name). Kick commands route through this printer.")
                }
            }
        } header: {
            Text("Printer Binding (RJ11 Port)")
        } footer: {
            Text("""
            Most receipt printers have an RJ11 cash-drawer port. Binding a printer here \
            routes kick commands through that printer's ESC/POS interface.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Alternate path

    private var alternatePathSection: some View {
        Section {
            Label("USB-connected drawer (via adapter)", systemImage: "cable.connector")
                .font(.subheadline)
                .accessibilityAddTraits(.isHeader)
            Text("""
            Some shops use a USB cash drawer connected directly to the iPad via a \
            USB-C adapter. These drawers typically expose a serial USB interface. \
            On iOS without MFi certification, the most reliable path is to route \
            the kick through a networked or Bluetooth receipt printer with an RJ11 \
            port (the primary path above).

            If you have a USB direct drawer, configure it by binding it to a \
            network-connected printer that provides the RJ11 port, or contact support.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
        } header: {
            Text("USB Direct (Less Common)")
        }
    }

    private var statusSection: some View {
        Section("STATUS") {
            HStack {
                Text("Drawer")
                Spacer()
                DrawerStatusBadge(status: drawerManager.status)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Drawer status: \(drawerManager.status.accessibilityDescription)")

            if let alert = drawerManager.antiTheftAlert {
                Label(alert, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .accessibilityLabel("Anti-theft alert: \(alert)")
            }
        }
    }

    private var triggerSection: some View {
        Section("AUTO-TRIGGER") {
            Toggle(isOn: cashToggle) {
                Label("Cash tender", systemImage: "banknote")
            }
            .accessibilityLabel("Open drawer on cash tender")

            Toggle(isOn: checkToggle) {
                Label("Check tender", systemImage: "checkmark.rectangle")
            }
            .accessibilityLabel("Open drawer on check tender")

            Text("The drawer opens automatically when the selected tender types are used during a sale.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var testSection: some View {
        Section("TEST") {
            Button {
                // Manager PIN gate: in production always requires PIN.
                // Dev builds allow direct test.
                #if DEBUG
                Task { await runTest(pin: "") }
                #else
                showingPinSheet = true
                #endif
            } label: {
                HStack {
                    Label("Open Drawer Now", systemImage: "tray.full")
                        .foregroundStyle(.primary)
                    Spacer()
                    if isTestInFlight {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(isTestInFlight)
            .accessibilityLabel("Test: open cash drawer now")
            .accessibilityHint("Requires manager PIN in production.")

            if let result = testResult {
                TestResultRow(result: result)
            }
        }
    }

    private var timingSection: some View {
        Section("TIMING & SECURITY") {
            Stepper(
                "Open warning: \(Int(drawerManager.openWarningDuration / 60)) min",
                value: Binding(
                    get: { Int(drawerManager.openWarningDuration / 60) },
                    set: { drawerManager.openWarningDuration = Double($0) * 60 }
                ),
                in: 1...30
            )
            .accessibilityLabel("Open warning duration")
            .accessibilityValue("\(Int(drawerManager.openWarningDuration / 60)) minutes")

            Stepper(
                "Anti-theft limit: \(drawerManager.antiTheftOpenLimit) opens",
                value: Binding(
                    get: { drawerManager.antiTheftOpenLimit },
                    set: { drawerManager.antiTheftOpenLimit = $0 }
                ),
                in: 2...10
            )
            .accessibilityLabel("Anti-theft open limit")
            .accessibilityValue("\(drawerManager.antiTheftOpenLimit) opens without a sale")

            Text("Alert fires when the drawer is opened this many times without an intervening sale.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Toggle bindings

    private var cashToggle: Binding<Bool> {
        Binding(
            get: { drawerManager.triggerTenders.contains(.cash) },
            set: { enabled in
                if enabled { drawerManager.triggerTenders.insert(.cash) }
                else { drawerManager.triggerTenders.remove(.cash) }
            }
        )
    }

    private var checkToggle: Binding<Bool> {
        Binding(
            get: { drawerManager.triggerTenders.contains(.check) },
            set: { enabled in
                if enabled { drawerManager.triggerTenders.insert(.check) }
                else { drawerManager.triggerTenders.remove(.check) }
            }
        )
    }

    // MARK: - Test action

    private func runTest(pin: String) async {
        isTestInFlight = true
        testResult = nil
        defer { isTestInFlight = false }
        let ok = await drawerManager.managerOverride(pin: pin, cashierName: "Test")
        if ok {
            testResult = .success("Drawer opened successfully.")
        } else {
            testResult = .failure(drawerManager.errorMessage ?? "Unknown error")
        }
    }
}

// MARK: - DrawerStatusBadge

private struct DrawerStatusBadge: View {
    let status: CashDrawerStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(dotColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var label: String {
        switch status {
        case .unknown:       return "Unknown"
        case .open:          return "Open"
        case .closed:        return "Closed"
        case .warning(let m): return m
        }
    }

    private var dotColor: Color {
        switch status {
        case .unknown:   return .secondary
        case .open:      return .green
        case .closed:    return .blue
        case .warning:   return .orange
        }
    }
}

// MARK: - CashDrawerStatus accessibility

extension CashDrawerStatus {
    fileprivate var accessibilityDescription: String {
        switch self {
        case .unknown:        return "unknown"
        case .open:           return "open"
        case .closed:         return "closed"
        case .warning(let m): return m
        }
    }
}

// MARK: - TestResult

private enum TestResult {
    case success(String)
    case failure(String)
}

private struct TestResultRow: View {
    let result: TestResult

    var body: some View {
        switch result {
        case .success(let msg):
            Label(msg, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
                .accessibilityLabel("Test result: success. \(msg)")
        case .failure(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .accessibilityLabel("Test result: failure. \(msg)")
        }
    }
}

// MARK: - ManagerPinSheet

private struct ManagerPinSheet: View {
    @Binding var isPresented: Bool
    let onSubmit: (String) -> Void

    @State private var pin = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Manager PIN", text: $pin)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("Manager PIN")
                }
                Section {
                    Text("A manager PIN is required to open the drawer without a sale.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Manager PIN")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open Drawer") {
                        let p = pin
                        isPresented = false
                        onSubmit(p)
                    }
                    .disabled(pin.count < 4)
                    .accessibilityLabel("Confirm open drawer with PIN")
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#endif
