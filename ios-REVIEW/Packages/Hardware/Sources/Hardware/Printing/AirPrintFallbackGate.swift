#if canImport(UIKit)
import UIKit
import Foundation
import Core

// MARK: - AirPrintFallbackGate
//
// §17.4 — AirPrint fallback gating.
//
// Purpose:
//   Before invoking `AirPrintEngine.print(_:on:)`, callers must verify that:
//     (a) AirPrint printing is available on the current device/OS version.
//     (b) At least one AirPrint printer has been discovered / cached.
//     (c) A thermal MFi printer is NOT already paired — AirPrint is the fallback,
//         not the primary path when a dedicated thermal printer is configured.
//
// This file provides:
//   1. `AirPrintAvailability`     — enum describing why AirPrint can/cannot be used.
//   2. `AirPrintFallbackGate`     — evaluates the conditions above synchronously.
//   3. `AirPrintFallbackGateView` — SwiftUI banner shown in POS when AirPrint is
//      the active print path (no MFi printer paired).
//
// Integration:
//   `PrintService` calls `AirPrintFallbackGate.evaluate(profileStore:)` before
//   routing a job. If the result is `.notAvailable` the service falls back to the
//   PDF share sheet (`NoPrinterFallbackView`). If `.available` it hands the job
//   to `AirPrintEngine`.
//
// AirPrint availability rules:
//   - `UIPrintInteractionController.isPrintingAvailable` must return `true`.
//   - Returns `false` on Mac Catalyst (no driver) and in Simulator builds.

// MARK: - AirPrintAvailability

/// The result of the AirPrint fallback gate evaluation.
public enum AirPrintAvailability: Sendable, Equatable {
    /// AirPrint is available and may be used as the print path.
    case available

    /// AirPrint is available but no printer is cached; the interactive picker
    /// must be presented before a headless print can proceed.
    case availableNoCachedPrinter

    /// A higher-priority MFi/network thermal printer is already paired.
    /// Callers should use the thermal engine (StarPrinterBridge / ESC/POS) instead.
    case mfiPrinterPreferred(printerName: String)

    /// AirPrint is not available on this device/OS combination.
    case notAvailable(reason: String)

    // MARK: Derived

    /// Whether the caller may proceed with AirPrint (interactive or headless).
    public var isUsable: Bool {
        switch self {
        case .available, .availableNoCachedPrinter: return true
        case .mfiPrinterPreferred, .notAvailable:   return false
        }
    }

    /// Whether a picker must be shown before a headless print.
    public var requiresPicker: Bool {
        if case .availableNoCachedPrinter = self { return true }
        return false
    }

    public var localizedDescription: String {
        switch self {
        case .available:
            return "AirPrint is ready."
        case .availableNoCachedPrinter:
            return "AirPrint is available. Select a printer to continue."
        case .mfiPrinterPreferred(let name):
            return "Using paired thermal printer (\(name)); AirPrint is not needed."
        case .notAvailable(let reason):
            return "AirPrint is not available: \(reason)"
        }
    }
}

// MARK: - AirPrintFallbackGate

/// Evaluates whether the AirPrint path should be activated for a print job.
///
/// All members are static — the gate requires no injection.
public enum AirPrintFallbackGate {

    // MARK: - UserDefaults key (mirrors AirPrintEngine)

    private static let cachedPrinterKey = "com.bizarrecrm.hardware.airprint.defaultPrinterURL"

    // MARK: - Evaluate

    /// Determine whether AirPrint can serve as the print path given the current
    /// profile store and system state.
    ///
    /// - Parameter profileStore: The active station's `PrinterProfileStore`.
    ///   Used to check whether an MFi thermal printer is already paired.
    /// - Returns: `AirPrintAvailability` describing the outcome.
    @MainActor
    public static func evaluate(profileStore: PrinterProfileStore) -> AirPrintAvailability {
        // 1. System-level availability check.
        guard UIPrintInteractionController.isPrintingAvailable else {
            return .notAvailable(
                reason: "UIPrintInteractionController.isPrintingAvailable is false " +
                        "(Simulator or Mac without a printer driver installed)"
            )
        }

        // 2. If an MFi/BT/Network thermal printer is already paired, AirPrint is
        //    not the preferred path — callers should use the thermal engine instead.
        let profile = profileStore.currentProfile
        if let pairedId = profile.defaultReceiptPrinterId, !pairedId.isEmpty {
            // Trim long IDs for display.
            let displayName = pairedId.count > 30
                ? String(pairedId.prefix(20)) + "\u{2026}"
                : pairedId
            return .mfiPrinterPreferred(printerName: displayName)
        }

        // 3. No thermal printer paired — AirPrint is the fallback path.
        let hasCachedPrinter = UserDefaults.standard.string(forKey: cachedPrinterKey) != nil
        return hasCachedPrinter ? .available : .availableNoCachedPrinter
    }

    // MARK: - Clear cached printer

    /// Remove the cached AirPrint printer URL (e.g. when the printer is no longer
    /// reachable or the user explicitly clears it in Settings).
    public static func clearCachedPrinter() {
        UserDefaults.standard.removeObject(forKey: cachedPrinterKey)
        AppLog.hardware.info("AirPrintFallbackGate: cleared cached printer URL")
    }
}

// MARK: - AirPrintFallbackGateView

#if canImport(SwiftUI)
import SwiftUI

/// Informational banner shown in the POS / print flow when AirPrint is the active
/// print path.
///
/// Displayed when no MFi thermal printer is paired and
/// `UIPrintInteractionController.isPrintingAvailable` is `true`.
/// Prompts the operator to pair a dedicated thermal printer for a better experience.
public struct AirPrintFallbackGateView: View {

    public let availability: AirPrintAvailability
    public let onSelectPrinter: (() -> Void)?
    public let onGoToSettings: (() -> Void)?

    public init(
        availability: AirPrintAvailability,
        onSelectPrinter: (() -> Void)? = nil,
        onGoToSettings: (() -> Void)? = nil
    ) {
        self.availability = availability
        self.onSelectPrinter = onSelectPrinter
        self.onGoToSettings = onGoToSettings
    }

    public var body: some View {
        Group {
            switch availability {
            case .available:
                airPrintReadyBanner(needsPicker: false)
            case .availableNoCachedPrinter:
                airPrintReadyBanner(needsPicker: true)
            case .mfiPrinterPreferred:
                // Nothing to show — thermal printer is active.
                EmptyView()
            case .notAvailable(let reason):
                notAvailableBanner(reason: reason)
            }
        }
    }

    // MARK: - AirPrint ready banner

    @ViewBuilder
    private func airPrintReadyBanner(needsPicker: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wifi")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(needsPicker ? "Select an AirPrint Printer" : "AirPrint Active")
                    .font(.subheadline.weight(.semibold))

                Text(needsPicker
                     ? "No printer cached yet. Tap \u{201C}Select Printer\u{201D} to choose an AirPrint printer, or pair a thermal printer in Settings for offline-capable printing."
                     : "Printing will use AirPrint. Pair a thermal receipt printer in Settings for a faster, offline-capable experience.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    if needsPicker, let picker = onSelectPrinter {
                        Button("Select Printer", action: picker)
                            .font(.caption.weight(.medium))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityLabel("Select an AirPrint printer")
                    }
                    if let settings = onGoToSettings {
                        Button("Pair Thermal Printer", action: settings)
                            .font(.caption.weight(.medium))
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                            .controlSize(.small)
                            .accessibilityLabel("Go to Settings to pair a thermal printer")
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.blue.opacity(0.20), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(availability.localizedDescription)
    }

    // MARK: - Not available banner

    private func notAvailableBanner(reason: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "printer.fill")
                .font(.title3)
                .foregroundStyle(.red)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Printing Not Available")
                    .font(.subheadline.weight(.semibold))
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Receipts will be shared as a PDF via the share sheet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.red.opacity(0.20), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Printing not available. \(reason). Receipts will be shared as a PDF.")
    }
}

// MARK: - Preview

#if DEBUG
#Preview("AirPrintFallbackGateView") {
    ScrollView {
        VStack(spacing: 16) {
            AirPrintFallbackGateView(
                availability: .available,
                onGoToSettings: {}
            )
            AirPrintFallbackGateView(
                availability: .availableNoCachedPrinter,
                onSelectPrinter: {},
                onGoToSettings: {}
            )
            AirPrintFallbackGateView(
                availability: .notAvailable(
                    reason: "UIPrintInteractionController.isPrintingAvailable is false (Simulator)"
                ),
                onGoToSettings: {}
            )
        }
        .padding()
    }
}
#endif
#endif
#endif
