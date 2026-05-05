#if canImport(SwiftUI)
import SwiftUI
import Core

// MARK: - PrinterPaperLowWarning
//
// §17.4 — Printer paper-low warning.
//
// ESC/POS printers (Star TSP100IV, Epson TM-m30II, Epson TM-T88VII) emit a
// paper-near-end status byte in the real-time status response (DLE EOT 1).
// The Star mPOP uses the StarIO SDK status bit `starPaperNearEnd`.
//
// This file provides:
//   1. `PrinterPaperLevel`      — enum representing full / low / empty paper states.
//   2. `PrinterPaperMonitor`    — @Observable that holds the paper level per printer
//      and exposes `setPaperLevel(_:for:)` for engine adapters to call when they
//      read a status byte.
//   3. `PrinterPaperLowBanner`  — glass warning banner shown in the POS toolbar or
//      Settings when paper is low or out.
//   4. `PrinterPaperLowAlert`   — alert modifier that fires an alert when a
//      printer transitions to `.low` or `.empty`.
//
// Integration: the `EscPosNetworkEngine` and `StarPrinterBridge` call
// `PrinterPaperMonitor.shared.setPaperLevel(_:for:)` when they receive a
// real-time status update from the printer.

// MARK: - PrinterPaperLevel

/// Thermal printer paper-roll level.
public enum PrinterPaperLevel: String, Sendable, CaseIterable, Codable {
    /// Paper roll is at normal operating level.
    case ok      = "ok"
    /// Paper is running low — replace soon to avoid mid-receipt cutoff.
    case low     = "low"
    /// Paper is exhausted — printing will fail until roll is replaced.
    case empty   = "empty"
    /// Level is unknown (printer hasn't reported status yet).
    case unknown = "unknown"

    // MARK: Presentation

    public var label: String {
        switch self {
        case .ok:      return "Paper OK"
        case .low:     return "Paper Low"
        case .empty:   return "No Paper"
        case .unknown: return "Paper Status Unknown"
        }
    }

    public var systemImage: String {
        switch self {
        case .ok:      return "printer.filled.and.paper"
        case .low:     return "exclamationmark.triangle.fill"
        case .empty:   return "xmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    public var color: Color {
        switch self {
        case .ok:      return .green
        case .low:     return .orange
        case .empty:   return .red
        case .unknown: return Color(UIColor.systemGray)
        }
    }

    public var isWarning: Bool {
        self == .low || self == .empty
    }

    public var accessibilityDescription: String {
        switch self {
        case .ok:      return "Paper level OK"
        case .low:     return "Paper running low — replace soon"
        case .empty:   return "No paper — printing unavailable"
        case .unknown: return "Paper level unknown"
        }
    }
}

// MARK: - PrinterPaperMonitor

/// Tracks paper level across all configured printers.
///
/// Engine adapters call `setPaperLevel(_:for:)` when they read a real-time
/// status byte. UI components observe `levels` to show warnings.
///
/// ```swift
/// // From EscPosNetworkEngine after reading DLE EOT:
/// PrinterPaperMonitor.shared.setPaperLevel(.low, for: printer.id)
/// ```
@Observable
@MainActor
public final class PrinterPaperMonitor {

    // MARK: - Singleton

    public static let shared = PrinterPaperMonitor()

    // MARK: - State

    /// Paper level per printer identifier.
    public private(set) var levels: [String: PrinterPaperLevel] = [:]

    /// True if any configured printer is `.low` or `.empty`.
    public var hasWarning: Bool {
        levels.values.contains { $0.isWarning }
    }

    /// Returns the most-severe paper level across all printers, or `.unknown` if none.
    public var worstLevel: PrinterPaperLevel {
        if levels.values.contains(.empty)  { return .empty }
        if levels.values.contains(.low)    { return .low }
        if levels.values.contains(.ok)     { return .ok }
        return .unknown
    }

    // MARK: - Init (private — use .shared)

    public init() {}

    // MARK: - Public API

    /// Update the paper level for `printerId`. Engine adapters call this.
    public func setPaperLevel(_ level: PrinterPaperLevel, for printerId: String) {
        let previous = levels[printerId]
        guard previous != level else { return }
        levels[printerId] = level
        AppLog.hardware.info("PrinterPaperMonitor: printer '\(printerId, privacy: .public)' paper level → \(level.rawValue, privacy: .public)")
        if level.isWarning {
            AppLog.hardware.warning("PrinterPaperMonitor: paper warning for '\(printerId, privacy: .public)' — \(level.label, privacy: .public)")
        }
    }

    /// Remove a printer from tracking (e.g. when unpaired).
    public func removePrinter(_ printerId: String) {
        levels.removeValue(forKey: printerId)
    }
}

// MARK: - PrinterPaperLowBanner

/// Compact glass banner shown in POS toolbar / Settings when paper is low or out.
///
/// ```swift
/// if monitor.hasWarning {
///     PrinterPaperLowBanner(level: monitor.worstLevel)
/// }
/// ```
public struct PrinterPaperLowBanner: View {

    public let level: PrinterPaperLevel
    /// Optional printer name to include in the message.
    public let printerName: String?

    public init(level: PrinterPaperLevel, printerName: String? = nil) {
        self.level = level
        self.printerName = printerName
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: level.systemImage)
                .foregroundStyle(level.color)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(level.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(level.color)
                if let name = printerName {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(bannerDetail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
                .font(.caption2)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(level.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(level.color.opacity(0.25), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(level.accessibilityDescription)
        .accessibilityAddTraits(.isButton)
    }

    private var bannerDetail: String {
        switch level {
        case .low:   return "Replace paper roll before next busy period."
        case .empty: return "Printing unavailable — insert paper roll now."
        default:     return ""
        }
    }
}

// MARK: - PrinterPaperLowAlert (ViewModifier)

/// Fires an alert when the observed `monitor` reports a paper-low or paper-empty
/// condition on any printer.
///
/// ```swift
/// view
///     .printerPaperLowAlert(monitor: PrinterPaperMonitor.shared)
/// ```
struct PrinterPaperLowAlertModifier: ViewModifier {
    @State private var isPresented: Bool = false
    @State private var lastWarningLevel: PrinterPaperLevel = .unknown

    let monitor: PrinterPaperMonitor

    func body(content: Content) -> some View {
        content
            .onChange(of: monitor.worstLevel) { _, newLevel in
                if newLevel.isWarning && newLevel != lastWarningLevel {
                    lastWarningLevel = newLevel
                    isPresented = true
                }
            }
            .alert(alertTitle, isPresented: $isPresented) {
                Button("Replace Paper") {}
                Button("Dismiss", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
    }

    private var alertTitle: String {
        monitor.worstLevel == .empty ? "No Paper" : "Paper Running Low"
    }

    private var alertMessage: String {
        monitor.worstLevel == .empty
            ? "The receipt printer is out of paper. Replace the paper roll to resume printing."
            : "The receipt printer's paper roll is running low. Replace it before the next busy period to avoid mid-print interruptions."
    }
}

public extension View {
    /// Monitors the given `PrinterPaperMonitor` and shows an alert when paper is low or empty.
    func printerPaperLowAlert(monitor: PrinterPaperMonitor = .shared) -> some View {
        modifier(PrinterPaperLowAlertModifier(monitor: monitor))
    }
}

// MARK: - Preview

#if DEBUG
#Preview("PrinterPaperLowBanner") {
    List {
        Section("Banners") {
            PrinterPaperLowBanner(level: .low, printerName: "Star TSP100IV")
            PrinterPaperLowBanner(level: .empty, printerName: "Epson TM-m30II")
            PrinterPaperLowBanner(level: .ok)
        }
    }
    .listStyle(.insetGrouped)
}
#endif
#endif
