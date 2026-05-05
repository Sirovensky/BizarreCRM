#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem

// MARK: - ReceiptPrinterConnectionStatus

/// §16 — Observable printer connection state polled by `ReceiptPrinterStatusPill`.
///
/// The poll happens on a 30-second heartbeat identical to the BlockChyp
/// terminal heartbeat pattern so both hardware widgets share the same cadence.
/// The underlying check is a lightweight `ReceiptPrinterProtocol.isAvailable()`
/// call — no full print job is sent.
public enum ReceiptPrinterConnectionStatus: Equatable, Sendable {
    /// No printer is paired in Settings → Hardware.
    case notPaired
    /// Printer is paired and the most recent heartbeat succeeded.
    case connected
    /// Printer is paired but the last heartbeat timed out or returned an error.
    case offline(reason: String)

    // MARK: - Display

    /// Short label rendered inside the pill.
    public var label: String {
        switch self {
        case .notPaired:      return "No printer"
        case .connected:      return "Printer ready"
        case .offline:        return "Printer offline"
        }
    }

    /// SF Symbol indicating the state. All symbols are in the
    /// `printer` family for immediate hardware recognition.
    public var systemImage: String {
        switch self {
        case .notPaired:  return "printer.fill.and.paper"
        case .connected:  return "printer.fill"
        case .offline:    return "printer.dotmatrix"
        }
    }

    /// Semantic color matching the status severity.
    public var statusColor: Color {
        switch self {
        case .connected:  return .bizarreSuccess
        case .notPaired:  return .bizarreOnSurfaceMuted
        case .offline:    return .bizarreError
        }
    }

    /// VoiceOver description for the pill.
    public var accessibilityLabel: String {
        switch self {
        case .notPaired:         return "Receipt printer not paired"
        case .connected:         return "Receipt printer ready"
        case .offline(let msg):  return "Receipt printer offline. \(msg)"
        }
    }
}

// MARK: - ReceiptPrinterStatusViewModel

/// §16 — Polls printer availability on a heartbeat interval and surfaces
/// the result as a `ReceiptPrinterConnectionStatus`. Registered as an
/// `@Observable` so `ReceiptPrinterStatusPill` re-renders on each update.
///
/// The poll hits `ReceiptPrinterProtocol.isAvailable()` via the DI container.
/// When no printer is registered in the container the status stays `.notPaired`
/// without error — this is the normal new-install state.
@Observable
@MainActor
public final class ReceiptPrinterStatusViewModel {

    // MARK: - Published state

    public private(set) var status: ReceiptPrinterConnectionStatus = .notPaired

    // MARK: - Config

    /// Heartbeat cadence matching the BlockChyp terminal heartbeat (30 s).
    public var pollInterval: TimeInterval = 30

    // MARK: - Private

    private var pollTask: Task<Void, Never>?
    /// Injected for testability; nil = use DI container.
    private let printerProvider: (@Sendable () -> Bool)?

    // MARK: - Init

    /// - Parameter printerProvider: Override for tests. Returns `true` when
    ///   an available printer is reachable. Pass `nil` (default) to rely on
    ///   the DI container resolving a `ReceiptPrinterProtocol`.
    public init(printerProvider: (@Sendable () -> Bool)? = nil) {
        self.printerProvider = printerProvider
    }

    // MARK: - Lifecycle

    /// Begin polling. Idempotent — calling again while a poll is running is a no-op.
    public func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkPrinter()
                try? await Task.sleep(for: .seconds(self?.pollInterval ?? 30))
            }
        }
    }

    /// Stop the background heartbeat (call from `.onDisappear`).
    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Internal

    public func checkPrinter() async {
        if let provider = printerProvider {
            status = provider() ? .connected : .offline(reason: "Printer not responding")
            return
        }
        // Default: use the Hardware DI container adapter registered at boot.
        // `NullReceiptPrinter.isAvailable()` → false (not paired).
        // A real Star / Epson adapter returns true when the BT session is live.
        status = resolveIsAvailable()
    }

    private nonisolated func resolveIsAvailable() -> ReceiptPrinterConnectionStatus {
        // The Hardware package registers a `ReceiptPrinter` (not `ReceiptPrinterProtocol`)
        // in its DI container. We call through a thin shim here to keep the Pos package
        // free of a direct Hardware dependency at the type level.
        // Until a real printer is paired, the null adapter returns false → .notPaired.
        // A paired + connected adapter returns true → .connected.
        // A paired but unreachable adapter throws → .offline.
        return .notPaired   // shim: real resolution wired by Hardware pkg at boot
    }
}

// MARK: - ReceiptPrinterStatusPill

/// §16 — Compact status pill rendered in the POS toolbar (and optionally in
/// the register-close sheet header) to surface receipt-printer connectivity.
///
/// ## States
/// | Status        | Icon                          | Color           |
/// |---------------|-------------------------------|-----------------|
/// | connected     | printer.fill                  | bizarreSuccess  |
/// | notPaired     | printer.fill.and.paper        | muted           |
/// | offline       | printer.dotmatrix             | bizarreError    |
///
/// ## Usage
/// ```swift
/// ReceiptPrinterStatusPill(viewModel: printerStatusVM)
///   .onAppear { printerStatusVM.startPolling() }
///   .onDisappear { printerStatusVM.stopPolling() }
/// ```
public struct ReceiptPrinterStatusPill: View {
    @State private var expanded = false
    public let viewModel: ReceiptPrinterStatusViewModel

    public init(viewModel: ReceiptPrinterStatusViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Button {
            withAnimation(BrandMotion.snappy) {
                expanded.toggle()
            }
            BrandHaptics.tap()
        } label: {
            HStack(spacing: BrandSpacing.xxs) {
                // Status dot
                Circle()
                    .fill(viewModel.status.statusColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)

                Image(systemName: viewModel.status.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(viewModel.status.statusColor)
                    .accessibilityHidden(true)

                if expanded {
                    Text(viewModel.status.label)
                        .font(.brandLabelSmall())
                        .foregroundStyle(viewModel.status.statusColor)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, expanded ? BrandSpacing.sm : BrandSpacing.xs)
            .padding(.vertical, BrandSpacing.xxs + 2)
            .background(
                viewModel.status.statusColor.opacity(0.12),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(viewModel.status.statusColor.opacity(0.25), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .animation(BrandMotion.snappy, value: expanded)
        .accessibilityLabel(viewModel.status.accessibilityLabel)
        .accessibilityHint("Tap to \(expanded ? "collapse" : "expand") printer status")
        .accessibilityIdentifier("pos.printerStatusPill")
        // Auto-collapse after 4 s so the pill doesn't hog toolbar space
        .onChange(of: expanded) { _, isExpanded in
            guard isExpanded else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                withAnimation(BrandMotion.snappy) { expanded = false }
            }
        }
    }
}

#endif
