#if canImport(SwiftUI)
import SwiftUI
import Core

// MARK: - PrintOptionsSheet
//
// §17 Reprint options sheet:
//   - Printer choice (if multiple configured)
//   - Paper size (80mm / Letter / A4 / Legal / etc.)
//   - Number of copies (1–10)
//   - Reason picker (for reprints older than 7 days — tenant-configurable)
//
// Designed for presentation from the Reprint flow (Agent 1 / Pos package) or
// any other print-confirm context. Agent 1 embeds this sheet; Hardware owns it.
//
// Usage:
// ```swift
// PrintOptionsSheet(
//     availablePrinters: printers,
//     requireReasonForOldJobs: true,
//     isOldJob: true
// ) { options in
//     printService.submit(job, options: options)
// }
// ```

// MARK: - PrintOptions (result type)

public struct PrintOptions: Sendable {
    public let selectedPrinter: Printer?
    public let paperSize: PrintMedium
    public let copies: Int
    public let reason: ReprintReason?

    public init(
        selectedPrinter: Printer?,
        paperSize: PrintMedium,
        copies: Int,
        reason: ReprintReason? = nil
    ) {
        self.selectedPrinter = selectedPrinter
        self.paperSize = paperSize
        self.copies = max(1, copies)
        self.reason = reason
    }
}

// MARK: - ReprintReason

public enum ReprintReason: String, CaseIterable, Sendable, Identifiable {
    case customerLostIt   = "Customer lost it"
    case accountantRequest = "Accountant request"
    case printerError     = "Printer error / illegible"
    case auditRequest     = "Audit request"
    case other            = "Other"

    public var id: String { rawValue }
}

// MARK: - PrintOptionsSheet

public struct PrintOptionsSheet: View {

    // MARK: - Configuration

    public let availablePrinters: [Printer]
    public let requireReasonForOldJobs: Bool
    public let isOldJob: Bool
    public let onConfirm: (PrintOptions) -> Void
    public let onCancel: () -> Void

    // MARK: - State

    @State private var selectedPrinterIndex: Int = 0
    @State private var paperSize: PrintMedium = .thermal80mm
    @State private var copies: Int = 1
    @State private var reason: ReprintReason = .customerLostIt

    // MARK: - Init

    public init(
        availablePrinters: [Printer] = [],
        requireReasonForOldJobs: Bool = false,
        isOldJob: Bool = false,
        onConfirm: @escaping (PrintOptions) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        self.availablePrinters = availablePrinters
        self.requireReasonForOldJobs = requireReasonForOldJobs
        self.isOldJob = isOldJob
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            Form {
                printerSection
                paperSizeSection
                copiesSection
                if requireReasonForOldJobs && isOldJob {
                    reasonSection
                }
            }
            .navigationTitle("Print Options")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .accessibilityLabel("Cancel and close print options")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Print") { confirm() }
                        .fontWeight(.semibold)
                        .accessibilityLabel("Confirm and print with selected options")
                }
            }
        }
        .onAppear { paperSize = PrintMedium.tenantDefault }
    }

    // MARK: - Sections

    @ViewBuilder
    private var printerSection: some View {
        Section("Printer") {
            if availablePrinters.isEmpty {
                Label("No printers configured", systemImage: "printer.slash")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("No printers are configured. Add a printer in Settings.")
            } else {
                Picker("Printer", selection: $selectedPrinterIndex) {
                    ForEach(availablePrinters.indices, id: \.self) { idx in
                        Text(availablePrinters[idx].name)
                            .tag(idx)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Select printer. Currently: \(availablePrinters[safe: selectedPrinterIndex]?.name ?? "None")")
            }
        }
    }

    private var paperSizeSection: some View {
        Section("Paper Size") {
            Picker("Paper Size", selection: $paperSize) {
                ForEach(PrintMedium.allCases, id: \.self) { medium in
                    Text(medium.displayName).tag(medium)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Select paper size. Currently: \(paperSize.displayName)")
        }
    }

    private var copiesSection: some View {
        Section("Copies") {
            Stepper(
                value: $copies,
                in: 1...10,
                step: 1
            ) {
                HStack {
                    Text("Copies")
                    Spacer()
                    Text("\(copies)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .accessibilityLabel("Number of copies: \(copies)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: copies = min(10, copies + 1)
                case .decrement: copies = max(1, copies - 1)
                @unknown default: break
                }
            }
        }
    }

    private var reasonSection: some View {
        Section {
            Picker("Reason", selection: $reason) {
                ForEach(ReprintReason.allCases) { r in
                    Text(r.rawValue).tag(r)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Reason for reprinting: \(reason.rawValue)")
        } header: {
            Text("Reason for Reprint")
        } footer: {
            Text("Required for receipts older than 7 days.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Confirm

    private func confirm() {
        let printer = availablePrinters.isEmpty
            ? nil
            : availablePrinters[safe: selectedPrinterIndex]
        onConfirm(PrintOptions(
            selectedPrinter: printer,
            paperSize: paperSize,
            copies: copies,
            reason: (requireReasonForOldJobs && isOldJob) ? reason : nil
        ))
    }
}

// MARK: - Safe subscript helper

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

#endif
