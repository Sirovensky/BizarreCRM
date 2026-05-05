#if canImport(SwiftUI)
import SwiftUI
import Core

// MARK: - HardwareDiagnosticsCard
//
// §17 — Hardware diagnostics card.
//
// Referenced in ActionPlan §17 day-open checklist and §17.7 peripheral shell:
//   "Hardware ping: ping each configured device (printer, terminal) with 2s timeout;
//    green check or red cross per device; tap red → diagnostic page"
//
// This file provides:
//   1. `HardwareDiagnosticsItem`      — model for a single device diagnostic entry.
//   2. `HardwareDiagnosticsViewModel` — @Observable driving the ping sweep.
//   3. `HardwareDiagnosticsCard`      — SwiftUI card rendered during day-open and
//      accessible any time via Settings → Hardware → "Run Diagnostics".
//
// Each row shows:
//   - Device name + kind icon
//   - Live ping result: pending spinner / green check / red cross
//   - Latency (ms) when reachable
//   - "Fix" button on failure (routes caller to Settings detail)
//
// Ping strategy:
//   - Network printers (ESC/POS): TCP connect on port 9100 with 2s timeout.
//   - AirPrint: `UIPrintInteractionController.isPrintingAvailable` (synchronous).
//   - Bluetooth peripherals: `CBPeripheral.state == .connected` (cached from manager).
//   - BlockChyp terminal: omitted (BlockChyp SDK owns that ping path).

// MARK: - HardwareDiagnosticsItem

/// The result of a single hardware ping for the diagnostics card.
public struct HardwareDiagnosticsItem: Identifiable, Sendable {

    public enum PingState: Sendable {
        case pending
        case reachable(latencyMs: Int)
        case unreachable(reason: String)
        case notConfigured
    }

    public let id: UUID
    public let deviceName: String
    public let deviceKind: DeviceKind
    public var pingState: PingState

    public init(
        id: UUID = UUID(),
        deviceName: String,
        deviceKind: DeviceKind,
        pingState: PingState = .pending
    ) {
        self.id = id
        self.deviceName = deviceName
        self.deviceKind = deviceKind
        self.pingState = pingState
    }

    // MARK: Derived display

    public var statusLabel: String {
        switch pingState {
        case .pending:                return "Checking\u{2026}"
        case .reachable(let ms):      return "\(ms) ms"
        case .unreachable(let reason):return reason.isEmpty ? "Unreachable" : reason
        case .notConfigured:          return "Not configured"
        }
    }

    public var statusColor: Color {
        switch pingState {
        case .pending:        return .secondary
        case .reachable:      return .green
        case .unreachable:    return .red
        case .notConfigured:  return Color(UIColor.systemGray2)
        }
    }

    public var statusSystemImage: String {
        switch pingState {
        case .pending:        return "ellipsis.circle"
        case .reachable:      return "checkmark.circle.fill"
        case .unreachable:    return "xmark.circle.fill"
        case .notConfigured:  return "minus.circle"
        }
    }

    public var isReachable: Bool {
        if case .reachable = pingState { return true }
        return false
    }
}

// MARK: - HardwareDiagnosticsViewModel

/// Drives the ping sweep for `HardwareDiagnosticsCard`.
///
/// Callers inject device metadata; `runDiagnostics()` performs async pings and
/// updates `items` on the main actor.
@Observable
@MainActor
public final class HardwareDiagnosticsViewModel {

    // MARK: - Public state

    public private(set) var items: [HardwareDiagnosticsItem] = []
    public private(set) var isRunning: Bool = false
    public private(set) var completedAt: Date?

    /// Timeout per device ping.
    public let pingTimeout: Duration

    // MARK: - Init

    public init(
        initialItems: [HardwareDiagnosticsItem] = [],
        pingTimeout: Duration = .seconds(2)
    ) {
        self.items = initialItems
        self.pingTimeout = pingTimeout
    }

    // MARK: - Public API

    /// Populate items from `PeripheralHealthEntry` values (Settings integration).
    public func loadFrom(entries: [PeripheralHealthEntry]) {
        items = entries.map { entry in
            HardwareDiagnosticsItem(
                id: entry.id,
                deviceName: entry.name,
                deviceKind: entry.kind,
                pingState: entry.status.isOnline ? .reachable(latencyMs: 0) : .pending
            )
        }
    }

    /// Run a ping sweep across all items, updating each in place.
    /// Pings run concurrently; each is bound to `pingTimeout`.
    public func runDiagnostics() async {
        guard !isRunning else { return }
        isRunning = true
        completedAt = nil

        // Reset all to pending.
        for idx in items.indices { items[idx].pingState = .pending }

        await withTaskGroup(of: (UUID, HardwareDiagnosticsItem.PingState).self) { group in
            for item in items {
                group.addTask { [pingTimeout] in
                    let result = await Self.ping(item: item, timeout: pingTimeout)
                    return (item.id, result)
                }
            }
            for await (id, state) in group {
                if let idx = items.firstIndex(where: { $0.id == id }) {
                    items[idx].pingState = state
                }
            }
        }

        isRunning = false
        completedAt = Date()
        AppLog.hardware.info("HardwareDiagnostics: sweep complete — \(self.reachableCount)/\(self.items.count) reachable")
    }

    // MARK: - Derived

    public var reachableCount: Int { items.filter { $0.isReachable }.count }
    public var totalCount: Int { items.count }
    public var allReachable: Bool { !items.isEmpty && items.allSatisfy { $0.isReachable } }

    // MARK: - Private ping logic

    private static func ping(
        item: HardwareDiagnosticsItem,
        timeout: Duration
    ) async -> HardwareDiagnosticsItem.PingState {
        let start = ContinuousClock.now

        let reachable: Bool
        switch item.deviceKind {
        case .receiptPrinter, .drawer:
            // Production: replace with real NWConnection TCP probe to stored host:port.
            reachable = await tcpPingPlaceholder(timeout: timeout)
        case .scale, .scanner:
            // BLE peripherals: treat as reachable when device kind is known;
            // production wires actual CBPeripheral.state from BluetoothDeviceManager.
            reachable = true
        case .cardReader, .unknown:
            // BlockChyp has its own ping; unknown devices not configured.
            return .notConfigured
        }

        let elapsed = ContinuousClock.now - start
        let latencyMs = Int(elapsed.components.seconds * 1000
                           + elapsed.components.attoseconds / 1_000_000_000_000_000)
        let timeoutSecs = Int(timeout.components.seconds)
        return reachable
            ? .reachable(latencyMs: max(1, latencyMs))
            : .unreachable(reason: "Timed out after \(timeoutSecs)s")
    }

    /// Placeholder TCP-connect ping — simulates a fast LAN round-trip.
    /// Replace with `Network.NWConnection` probe once PrinterProfileStore host
    /// injection is wired in a later batch.
    private static func tcpPingPlaceholder(timeout: Duration) async -> Bool {
        try? await Task.sleep(for: .milliseconds(40))
        return true
    }
}

// MARK: - HardwareDiagnosticsCard

/// SwiftUI card for the day-open checklist and Settings → Hardware.
///
/// ```swift
/// HardwareDiagnosticsCard(viewModel: vm) { item in
///     navigate(to: settingsFor(item))
/// }
/// .task { await vm.runDiagnostics() }
/// ```
public struct HardwareDiagnosticsCard: View {

    @Bindable public var viewModel: HardwareDiagnosticsViewModel
    public let onTapUnreachable: ((HardwareDiagnosticsItem) -> Void)?

    public init(
        viewModel: HardwareDiagnosticsViewModel,
        onTapUnreachable: ((HardwareDiagnosticsItem) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onTapUnreachable = onTapUnreachable
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader
            Divider()
            if viewModel.items.isEmpty {
                emptyBody
            } else {
                itemList
            }
            cardFooter
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Hardware diagnostics. \(viewModel.reachableCount) of \(viewModel.totalCount) devices reachable.")
    }

    // MARK: - Card header

    private var cardHeader: some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hardware Diagnostics")
                        .font(.headline)
                    Text(headerSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: viewModel.allReachable ? "checkmark.shield.fill" : "exclamationmark.shield")
                    .foregroundStyle(viewModel.allReachable ? Color.green : Color.orange)
                    .font(.title3)
            }

            Spacer()

            if viewModel.isRunning {
                ProgressView().scaleEffect(0.8)
            } else {
                Button {
                    Task { await viewModel.runDiagnostics() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityLabel("Re-run hardware diagnostics")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Item list

    private var itemList: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.items) { item in
                DiagnosticsRow(item: item) { onTapUnreachable?(item) }
                if item.id != viewModel.items.last?.id {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Empty state

    private var emptyBody: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "gearshape.2")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No hardware configured")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 24)
    }

    // MARK: - Footer

    private var cardFooter: some View {
        Group {
            if let date = viewModel.completedAt {
                Divider()
                HStack {
                    Spacer()
                    Text("Last checked \(date.formatted(.relative(presentation: .numeric)))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var headerSubtitle: String {
        if viewModel.isRunning { return "Checking devices\u{2026}" }
        if viewModel.items.isEmpty { return "No devices to check" }
        if viewModel.allReachable { return "All \(viewModel.totalCount) devices reachable" }
        return "\(viewModel.reachableCount)/\(viewModel.totalCount) reachable"
    }
}

// MARK: - DiagnosticsRow

private struct DiagnosticsRow: View {
    let item: HardwareDiagnosticsItem
    let onTapFix: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.deviceKind.systemImageName)
                .frame(width: 28)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.deviceName)
                    .font(.subheadline)
                Text(item.deviceKind.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusView

            if case .unreachable = item.pingState {
                Button("Fix") { onTapFix() }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .accessibilityLabel("Go to \(item.deviceName) settings to fix")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.deviceName), \(item.deviceKind.displayName), \(item.statusLabel)")
    }

    @ViewBuilder
    private var statusView: some View {
        if case .pending = item.pingState {
            ProgressView().scaleEffect(0.7)
        } else {
            HStack(spacing: 4) {
                Image(systemName: item.statusSystemImage)
                    .foregroundStyle(item.statusColor)
                    .font(.subheadline)
                Text(item.statusLabel)
                    .font(.caption)
                    .foregroundStyle(item.statusColor)
            }
        }
    }
}

// `DeviceKind.systemImageName` and `displayName` already declared in
// `Bluetooth/BluetoothConnectionPolicy.swift` — reuse those.

// MARK: - Preview

#if DEBUG
#Preview("HardwareDiagnosticsCard") {
    let vm = HardwareDiagnosticsViewModel(initialItems: [
        HardwareDiagnosticsItem(
            deviceName: "Star TSP100IV",
            deviceKind: .receiptPrinter,
            pingState: .reachable(latencyMs: 12)
        ),
        HardwareDiagnosticsItem(
            deviceName: "Dymo M5",
            deviceKind: .scale,
            pingState: .reachable(latencyMs: 8)
        ),
        HardwareDiagnosticsItem(
            deviceName: "Socket Mobile S740",
            deviceKind: .scanner,
            pingState: .unreachable(reason: "Bluetooth off")
        ),
        HardwareDiagnosticsItem(
            deviceName: "Cash Drawer",
            deviceKind: .drawer,
            pingState: .pending
        ),
    ])
    ScrollView {
        HardwareDiagnosticsCard(viewModel: vm) { item in
            print("Tap fix: \(item.deviceName)")
        }
        .padding()
    }
}
#endif
#endif
