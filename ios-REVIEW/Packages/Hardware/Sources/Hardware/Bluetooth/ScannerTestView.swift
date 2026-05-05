#if canImport(SwiftUI)
import SwiftUI
import Core

// MARK: - ScannerTestView
//
// §17.2 — Dedicated scanner test screen.
//
// Accessed via Settings → Hardware → Scanner → "Test Scanner".
//
// Purpose: Lets operators verify that a paired HID or Bluetooth barcode scanner
// is responding before opening the store. The screen:
//   1. Shows a "Waiting for scan…" state with an animated ring.
//   2. Accepts a barcode from:
//      - The `BarcodeScannerBuffer` (HID wedge / BT external scanner).
//      - A manual-entry text field (fallback for testing without hardware).
//   3. Displays the last scanned barcode string with length + symbology hint.
//   4. Keeps a short history of the last 5 scan events during the session.
//   5. Has a "Clear" button to reset.
//
// Architecture: the view owns a local `BarcodeScannerBuffer` and drives it
// via a `ScannerTestViewModel`. Manual-entry sends the string directly to
// `buffer.flush()` without going through the HID listener, so it works even
// with no hardware attached.

// MARK: - ScannerTestSession (log entry)

public struct ScannerTestEntry: Identifiable, Sendable {
    public let id: UUID
    public let barcode: String
    public let receivedAt: Date
    /// True when the barcode came from the physical scanner; false = manual entry.
    public let isHardwareScan: Bool

    public init(
        id: UUID = UUID(),
        barcode: String,
        receivedAt: Date = Date(),
        isHardwareScan: Bool
    ) {
        self.id = id
        self.barcode = barcode
        self.receivedAt = receivedAt
        self.isHardwareScan = isHardwareScan
    }

    var symbologyHint: String {
        let len = barcode.count
        if len == 13 && barcode.allSatisfy(\.isNumber) { return "EAN-13" }
        if len == 12 && barcode.allSatisfy(\.isNumber) { return "UPC-A" }
        if len == 8  && barcode.allSatisfy(\.isNumber) { return "EAN-8 / UPC-E" }
        if barcode.hasPrefix("GC-") { return "Gift Card" }
        return "Code 128 / other"
    }
}

// MARK: - ScannerTestViewModel

@Observable
@MainActor
public final class ScannerTestViewModel {

    // MARK: - State

    public private(set) var entries: [ScannerTestEntry] = []
    public private(set) var lastEntry: ScannerTestEntry?
    public var manualInput: String = ""
    public private(set) var isWaiting: Bool = true

    // Maximum history entries kept.
    private let historyLimit = 5

    // MARK: - Init

    public init() {}

    // MARK: - Called by the view when the buffer fires

    public func recordScan(_ barcode: String, isHardware: Bool) {
        let entry = ScannerTestEntry(barcode: barcode, isHardwareScan: isHardware)
        lastEntry = entry
        entries.insert(entry, at: 0)
        if entries.count > historyLimit { entries.removeLast() }
        isWaiting = false
        AppLog.hardware.info("ScannerTestViewModel: received '\(barcode, privacy: .public)' hardware=\(isHardware)")
    }

    // MARK: - Manual submit

    public func submitManual() {
        let trimmed = manualInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recordScan(trimmed, isHardware: false)
        manualInput = ""
    }

    // MARK: - Clear

    public func clear() {
        entries = []
        lastEntry = nil
        isWaiting = true
        manualInput = ""
    }
}

// MARK: - ScannerTestView

/// Full-screen scanner test screen for Settings → Hardware → Scanner.
///
/// ```swift
/// NavigationLink("Test Scanner") {
///     ScannerTestView()
/// }
/// ```
public struct ScannerTestView: View {

    // MARK: - Dependencies

    @State private var vm = ScannerTestViewModel()

    /// Buffer that the HID listener feeds into; the view owns it for this session.
    @State private var buffer: BarcodeScannerBuffer?
    @State private var bufferStream: AsyncStream<String>?
    @State private var streamTask: Task<Void, Never>?

    // MARK: - Body

    public init() {}

    public var body: some View {
        List {
            waitingSection
            if let entry = vm.lastEntry {
                lastScanSection(entry)
            }
            manualEntrySection
            if !vm.entries.isEmpty {
                historySection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Scanner Test")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear", action: vm.clear)
                    .disabled(vm.entries.isEmpty)
                    .accessibilityLabel("Clear scan history")
            }
        }
        .task { await startListening() }
        .onDisappear { streamTask?.cancel() }
    }

    // MARK: - Sections

    @ViewBuilder
    private var waitingSection: some View {
        Section {
            HStack(spacing: 16) {
                scannerStatusDot
                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.isWaiting ? "Waiting for scan\u{2026}" : "Scanner responding")
                        .font(.headline)
                    Text(vm.isWaiting
                         ? "Point your scanner at a barcode or type below."
                         : "Scanned \(vm.entries.count) barcode\(vm.entries.count == 1 ? "" : "s") this session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(vm.isWaiting
                ? "Waiting for scanner input."
                : "Scanner responding. \(vm.entries.count) barcodes scanned.")
        } header: {
            Text("Scanner Status")
        }
    }

    private var scannerStatusDot: some View {
        ZStack {
            Circle()
                .stroke(vm.isWaiting ? Color.orange.opacity(0.25) : Color.green.opacity(0.25),
                        lineWidth: 6)
                .frame(width: 36, height: 36)

            Circle()
                .fill(vm.isWaiting ? Color.orange : Color.green)
                .frame(width: 16, height: 16)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func lastScanSection(_ entry: ScannerTestEntry) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(entry.barcode)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Image(systemName: entry.isHardwareScan ? "barcode.viewfinder" : "keyboard")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }

                HStack(spacing: 12) {
                    Label("\(entry.barcode.count) chars", systemImage: "number")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(entry.symbologyHint, systemImage: "qrcode")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Last barcode: \(entry.barcode). \(entry.barcode.count) characters. \(entry.symbologyHint). Source: \(entry.isHardwareScan ? "hardware scanner" : "manual entry").")
        } header: {
            Text("Last Scan")
        }
    }

    private var manualEntrySection: some View {
        Section {
            HStack {
                TextField("Type or paste a barcode\u{2026}", text: $vm.manualInput)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit(vm.submitManual)
                    .accessibilityLabel("Manual barcode entry field")

                Button("Submit", action: vm.submitManual)
                    .disabled(vm.manualInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Submit manual barcode")
            }
        } header: {
            Text("Manual Entry (Fallback)")
        } footer: {
            Text("Use this if no hardware scanner is paired. Input is treated as a barcode string and added to the history above.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var historySection: some View {
        Section {
            ForEach(vm.entries) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.barcode)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        Text(entry.receivedAt.formatted(.dateTime.hour().minute().second()))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Image(systemName: entry.isHardwareScan ? "barcode.viewfinder" : "keyboard")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Barcode: \(entry.barcode), received at \(entry.receivedAt.formatted(.dateTime.hour().minute().second()))")
            }
        } header: {
            Text("History (last \(vm.entries.count))")
        }
    }

    // MARK: - Scanner buffer wiring

    private func startListening() async {
        let (stream, buf) = BarcodeScannerBuffer.makeStream()
        buffer = buf
        bufferStream = stream
        streamTask = Task { [stream] in
            for await barcode in stream {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    vm.recordScan(barcode, isHardware: true)
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("ScannerTestView") {
    NavigationStack {
        ScannerTestView()
    }
}
#endif
#endif
