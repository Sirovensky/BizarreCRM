#if canImport(SwiftUI)
import SwiftUI
import Core

// MARK: - PrinterStatusIndicator
//
// §17.4 — Printer connection status indicator.
//
// A compact chip/badge that reflects the live `PrinterStatus` of a configured
// receipt printer. Used in:
//   - Settings → Hardware → Printers row (badge on trailing edge)
//   - POS toolbar (mini dot variant)
//   - Day-open checklist (§17 startup ping)
//
// Design:
//   - `.ready`     → green dot + "Ready"
//   - `.printing`  → amber dot + "Printing…" with a `ProgressView` spinner
//   - `.error(msg)`→ red dot + "Error" with tap-to-expand detail
//   - `.offline`   → grey dot + "Offline"
//
// The view is self-contained; callers supply the `PrinterConnectionStatus` and an
// optional printer name. When `showLabel` is false only the coloured dot is shown
// (toolbar use).
//
// Accessibility: always announces status in VoiceOver regardless of `showLabel`.

// MARK: - PrinterConnectionStatus (richer model for UI)

/// Extends `PrinterStatus` with an `.offline` case for the status indicator.
/// `PrinterStatus.error("offline")` maps to `.offline` on construction.
public enum PrinterConnectionStatus: Sendable, Equatable {
    case ready
    case printing
    case offline
    case error(String)

    /// Build from the `Printer.status` stored in a `Printer` value.
    public init(printerStatus: PrinterStatus, isReachable: Bool) {
        if !isReachable {
            self = .offline
            return
        }
        switch printerStatus {
        case .idle:            self = .ready
        case .printing:        self = .printing
        case .error(let msg):
            // Convention: engine stores "offline" literal when reachability fails.
            self = (msg.lowercased() == "offline") ? .offline : .error(msg)
        }
    }

    // MARK: Presentation

    var label: String {
        switch self {
        case .ready:           return "Ready"
        case .printing:        return "Printing\u{2026}"
        case .offline:         return "Offline"
        case .error:           return "Error"
        }
    }

    var color: Color {
        switch self {
        case .ready:    return .green
        case .printing: return .orange
        case .offline:  return Color(UIColor.systemGray)
        case .error:    return .red
        }
    }

    var systemImage: String {
        switch self {
        case .ready:    return "printer.filled.and.paper"
        case .printing: return "printer.filled.and.paper"
        case .offline:  return "printer"
        case .error:    return "printer"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .ready:           return "Printer ready"
        case .printing:        return "Printer is printing"
        case .offline:         return "Printer offline"
        case .error(let msg):  return "Printer error: \(msg)"
        }
    }
}

// MARK: - PrinterStatusIndicator

/// Compact status chip for a receipt printer.
///
/// ```swift
/// // Settings row trailing:
/// PrinterStatusIndicator(
///     status: .init(printerStatus: printer.status, isReachable: true),
///     printerName: printer.name
/// )
///
/// // Dot-only toolbar variant:
/// PrinterStatusIndicator(status: .ready, showLabel: false)
/// ```
public struct PrinterStatusIndicator: View {

    public let status: PrinterConnectionStatus
    public let printerName: String?
    public let showLabel: Bool

    @State private var showErrorDetail: Bool = false

    public init(
        status: PrinterConnectionStatus,
        printerName: String? = nil,
        showLabel: Bool = true
    ) {
        self.status = status
        self.printerName = printerName
        self.showLabel = showLabel
    }

    public var body: some View {
        Group {
            if showLabel {
                chipBody
            } else {
                dotOnly
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .alert(errorTitle, isPresented: $showErrorDetail, presenting: errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
    }

    // MARK: - Chip (full)

    private var chipBody: some View {
        HStack(spacing: 5) {
            statusDot
            if case .printing = status {
                ProgressView()
                    .scaleEffect(0.55)
                    .accessibilityHidden(true)
            }
            Text(status.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(status.color.opacity(0.10), in: Capsule())
        .onTapGesture { handleTap() }
        .accessibilityAddTraits(canShowDetail ? .isButton : [])
        .accessibilityHint(canShowDetail ? "Tap to see error details" : "")
    }

    // MARK: - Dot-only (toolbar)

    private var dotOnly: some View {
        statusDot
            .onTapGesture { handleTap() }
    }

    // MARK: - Shared dot

    private var statusDot: some View {
        Circle()
            .fill(status.color)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }

    // MARK: - Helpers

    private var canShowDetail: Bool {
        if case .error = status { return true }
        return false
    }

    private func handleTap() {
        guard canShowDetail else { return }
        showErrorDetail = true
    }

    private var errorTitle: String { "Printer Error" }

    private var errorMessage: String? {
        guard case .error(let msg) = status else { return nil }
        return msg.isEmpty ? "An unknown printer error occurred." : msg
    }

    private var accessibilityText: String {
        var parts = [status.accessibilityDescription]
        if let name = printerName { parts.insert(name, at: 0) }
        return parts.joined(separator: " — ")
    }
}

// MARK: - PrinterStatusRow
//
// Convenience row for Settings list: icon + name + status indicator on trailing.

/// Full-width settings row combining printer name, connection type and status badge.
public struct PrinterStatusRow: View {

    public let printerName: String
    public let connectionDescription: String
    public let status: PrinterConnectionStatus

    public init(
        printerName: String,
        connectionDescription: String,
        status: PrinterConnectionStatus
    ) {
        self.printerName = printerName
        self.connectionDescription = connectionDescription
        self.status = status
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status.systemImage)
                .foregroundStyle(status.color)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(printerName)
                    .font(.body)
                Text(connectionDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            PrinterStatusIndicator(
                status: status,
                printerName: printerName,
                showLabel: true
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(printerName), \(connectionDescription), \(status.accessibilityDescription)")
    }
}

// MARK: - Preview

#if DEBUG
#Preview("PrinterStatusIndicator") {
    List {
        Section("Chip variants") {
            PrinterStatusIndicator(status: .ready, printerName: "Star TSP100IV")
            PrinterStatusIndicator(status: .printing, printerName: "Epson TM-m30")
            PrinterStatusIndicator(status: .offline, printerName: "Star mPOP")
            PrinterStatusIndicator(status: .error("Paper jam in feed mechanism"), printerName: "Dymo")
        }
        Section("Dot-only (toolbar)") {
            HStack {
                PrinterStatusIndicator(status: .ready, showLabel: false)
                PrinterStatusIndicator(status: .printing, showLabel: false)
                PrinterStatusIndicator(status: .offline, showLabel: false)
                PrinterStatusIndicator(status: .error("Low paper"), showLabel: false)
            }
        }
        Section("Full row") {
            PrinterStatusRow(
                printerName: "Star TSP100IV",
                connectionDescription: "Network — 192.168.1.42:9100",
                status: .ready
            )
            PrinterStatusRow(
                printerName: "Epson TM-m30II",
                connectionDescription: "AirPrint — epson.local",
                status: .error("Low paper — 10% remaining")
            )
            PrinterStatusRow(
                printerName: "Star mPOP",
                connectionDescription: "Bluetooth MFi",
                status: .offline
            )
        }
    }
    .listStyle(.insetGrouped)
}
#endif
#endif
