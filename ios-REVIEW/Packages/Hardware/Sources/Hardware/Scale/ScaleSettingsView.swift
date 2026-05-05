#if canImport(SwiftUI)
import SwiftUI
import Core

// MARK: - ScaleSettingsView
//
// §17 Scale configuration — Settings → Hardware → Scale
//
// Supported hardware:
//   Primary path — Bluetooth BLE scales implementing the SIG Weight Scale Service
//   (0x181D / 0x2A9D):
//     • Dymo M5 (confirmed in BluetoothWeightScale.swift)
//     • Dymo M10 — same service UUID; supported via the same BLE path
//     • Brecknell B140 / B180 — Bluetooth SPP/BLE, 0x2A9D compatible
//     • Any scale advertising the Weight Scale Service 0x181D
//
//   USB path — scales connected via USB-C adapter to iPad:
//     Some bench scales (e.g. Ohaus Ranger) expose a USB CDC serial interface.
//     These appear as a paired Bluetooth-serial or HID device when bridged via an
//     Apple-certified USB-C dock. Note: a direct USB driver is not available on iOS
//     without MFi certification. Use a Bluetooth-bridged scale as the primary path.
//
// NTEP disclaimer (required by US law for commercial sales by weight):
//   NTEP (National Type Evaluation Program) certification is required by law for
//   scales used in commercial transactions in the United States. The app handles the
//   weighing math correctly, but hardware certification is the tenant's responsibility.
//
// iPhone: compact Form layout.
// iPad: Form in a NavigationSplitView detail pane.

public struct ScaleSettingsView: View {

    @State private var unitStore = WeightUnitStore()
    @State private var selectedUnit: WeightUnit = .grams
    @State private var showNtepInfo = false

    public init() {}

    // MARK: - Body

    public var body: some View {
        Form {
            unitSection
            supportedDevicesSection
            usbSection
            ntepSection
        }
        .navigationTitle("Scale")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .onAppear { selectedUnit = unitStore.selectedUnit }
        .onChange(of: selectedUnit) { _, newUnit in
            unitStore.selectedUnit = newUnit
        }
        .sheet(isPresented: $showNtepInfo) {
            NTEPInfoSheet(isPresented: $showNtepInfo)
        }
    }

    // MARK: - Unit section

    private var unitSection: some View {
        Section("WEIGHT UNIT") {
            Picker("Unit", selection: $selectedUnit) {
                ForEach(WeightUnit.allCases, id: \.self) { unit in
                    Text(unit.displayName).tag(unit)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Preferred weight unit: \(selectedUnit.displayName)")
        }
    }

    // MARK: - Supported devices section

    private var supportedDevicesSection: some View {
        Section {
            SupportedScaleRow(
                model: "Dymo M5",
                connectionNote: "Bluetooth BLE (0x181D)",
                status: .confirmed
            )
            SupportedScaleRow(
                model: "Dymo M10",
                connectionNote: "Bluetooth BLE (0x181D)",
                status: .confirmed
            )
            SupportedScaleRow(
                model: "Brecknell B140",
                connectionNote: "Bluetooth SPP/BLE",
                status: .confirmed
            )
            SupportedScaleRow(
                model: "Brecknell B180",
                connectionNote: "Bluetooth SPP/BLE",
                status: .confirmed
            )
            SupportedScaleRow(
                model: "Any BLE Weight Scale Service scale",
                connectionNote: "UUID 0x181D / 0x2A9D",
                status: .compatible
            )
        } header: {
            Text("Supported Bluetooth Scales")
        } footer: {
            Text("Pair your scale via Settings → Bluetooth before it appears here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - USB section

    private var usbSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("USB via USB-C Adapter", systemImage: "cable.connector")
                    .font(.subheadline.weight(.medium))
                    .accessibilityAddTraits(.isHeader)

                Text("""
                Some bench scales (e.g. Ohaus Ranger, Adam Equipment) can be connected \
                via USB-C when used with an Apple-certified USB-C dock or serial-to-USB-C adapter. \
                These scales typically need a USB-to-Bluetooth bridge dongle to appear as a \
                Bluetooth peripheral on iOS — a direct USB CDC driver is not available without \
                MFi certification.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)

                Text("For the simplest setup, choose a native Bluetooth BLE scale listed above.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("USB connection. Requires a USB-C to Bluetooth bridge dongle on iOS. Bluetooth BLE scales are the recommended path.")
        } header: {
            Text("USB Connection (Less Common)")
        }
    }

    // MARK: - NTEP section

    private var ntepSection: some View {
        Section {
            Button {
                showNtepInfo = true
            } label: {
                HStack {
                    Label("NTEP Certification", systemImage: "checkmark.seal")
                    Spacer()
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
            .accessibilityLabel("NTEP certification requirement. Tap to learn more.")
        } header: {
            Text("Commercial Sales (US)")
        } footer: {
            Text("NTEP-certified hardware is the tenant's responsibility.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - SupportedScaleRow

private struct SupportedScaleRow: View {
    enum CompatStatus {
        case confirmed   // tested with this specific model
        case compatible  // expected to work via standard BLE service
    }

    let model: String
    let connectionNote: String
    let status: CompatStatus

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model)
                    .font(.subheadline)
                Text(connectionNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusChip
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model). \(connectionNote). \(status == .confirmed ? "Confirmed compatible." : "Expected compatible.")")
    }

    private var statusChip: some View {
        Text(status == .confirmed ? "Tested" : "Compatible")
            .font(.caption2.weight(.medium))
            .foregroundStyle(status == .confirmed ? Color.green : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                (status == .confirmed ? Color.green : Color.secondary).opacity(0.12),
                in: Capsule()
            )
    }
}

// MARK: - NTEPInfoSheet

private struct NTEPInfoSheet: View {
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("What is NTEP?")
                        .font(.title2.weight(.semibold))

                    Text("""
                    NTEP (National Type Evaluation Program) is a certification program \
                    administered by the National Conference on Weights and Measures (NCWM). \
                    In the United States, any scale used in a commercial transaction — where \
                    a price is determined by weight — must be NTEP certified.

                    Examples of commercial use requiring NTEP:
                    • Selling produce, meat, or bulk goods by weight.
                    • Charging for scrap metal by weight.
                    • Selling parts or hardware priced per pound/gram.

                    Examples that do NOT require NTEP:
                    • Weighing for shipping estimation only.
                    • Internal stock measurement with no direct customer charge.
                    """)
                    .font(.body)

                    Divider()

                    Text("Tenant Responsibility")
                        .font(.headline)

                    Text("""
                    BizarreCRM correctly records and displays the weight reading from your scale. \
                    Whether the physical hardware itself is NTEP-certified is the tenant's \
                    responsibility. Check your scale's documentation or contact the manufacturer \
                    to confirm NTEP status.
                    """)
                    .font(.body)

                    Text("Look for the NTEP Certificate of Conformance (CoC) number printed on a label on the scale, or in the documentation.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding()
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                }
                .padding()
            }
            .navigationTitle("NTEP Certification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                        .accessibilityLabel("Close NTEP information")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#endif
