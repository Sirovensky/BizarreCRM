#if canImport(UIKit)
import Foundation
import Core
import SwiftUI

// §17.3 Batch management — force-close daily at configurable time.
//
// BatchManager persists the user-configured close hour in UserDefaults
// and exposes a trigger for the "Close batch now" Settings button.
// Scheduled auto-close (at the configured hour) requires a background task
// or server-side cron; the iOS side provides the trigger that the POS
// wraps in a background URLSession task.

// MARK: - BatchManager

/// Manages daily batch-close scheduling and manual triggers for BlockChyp.
@Observable
@MainActor
public final class BatchManager {

    // MARK: - Constants

    private static let closeHourKey = "com.bizarrecrm.hardware.batchCloseHour"
    private static let lastClosedKey = "com.bizarrecrm.hardware.batchLastClosed"

    // MARK: - Published state

    /// Hour (0–23) at which the batch auto-closes. Default: 23 (11 PM).
    public var scheduledCloseHour: Int {
        get { UserDefaults.standard.integer(forKey: Self.closeHourKey) == 0
              ? 23
              : UserDefaults.standard.integer(forKey: Self.closeHourKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.closeHourKey) }
    }

    public private(set) var isClosing: Bool = false
    public private(set) var lastCloseResult: BatchCloseResult?
    public private(set) var lastClosedAt: Date? = {
        let t = UserDefaults.standard.double(forKey: lastClosedKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }()
    public private(set) var errorMessage: String?

    // MARK: - Dependencies

    private let terminal: BlockChypTerminal

    // MARK: - Init

    public init(terminal: BlockChypTerminal) {
        self.terminal = terminal
    }

    // MARK: - Manual close

    /// Immediately force-close the current batch. Maps to Settings "Close batch now".
    public func closeBatchNow() async {
        guard !isClosing else { return }
        isClosing = true
        errorMessage = nil
        defer { isClosing = false }

        AppLog.hardware.info("BatchManager: manual batch close requested")
        do {
            let result = try await terminal.closeBatch()
            lastCloseResult = result
            lastClosedAt = result.closedAt
            UserDefaults.standard.set(result.closedAt.timeIntervalSince1970, forKey: Self.lastClosedKey)
            AppLog.hardware.info("BatchManager: batch closed — \(result.transactionCount) txns, batchId=\(result.batchId ?? "n/a", privacy: .public)")
        } catch {
            errorMessage = error.localizedDescription
            AppLog.hardware.error("BatchManager: batch close failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Scheduled close check

    /// Returns `true` if the configured close time has passed today and no batch was
    /// closed yet today. Callers (e.g. background fetch handler) call `closeBatchNow()`
    /// when this returns `true`.
    public var shouldAutoCloseNow: Bool {
        let cal = Calendar.current
        let now = Date()
        let hour = cal.component(.hour, from: now)

        // Has the scheduled hour passed today?
        guard hour >= scheduledCloseHour else { return false }

        // Has a close already happened today?
        if let last = lastClosedAt, cal.isDateInToday(last) { return false }

        return true
    }
}

// MARK: - BatchSettingsSection (Settings UI component)

/// Settings section embedded in `HardwareSettingsView` / BlockChyp pairing screen.
public struct BatchSettingsSection: View {

    @State private var vm: BatchManager

    public init(manager: BatchManager) {
        self._vm = State(initialValue: manager)
    }

    public var body: some View {
        Section {
            Stepper(
                "Auto-close at \(vm.scheduledCloseHour):00",
                value: Binding(
                    get: { vm.scheduledCloseHour },
                    set: { vm.scheduledCloseHour = $0 }
                ),
                in: 0...23
            )
            .accessibilityLabel("Batch auto-close hour")
            .accessibilityValue("\(vm.scheduledCloseHour):00")
            .accessibilityHint("Adjusts the daily automatic batch close time in 1-hour steps.")

            if let last = vm.lastClosedAt {
                LabeledContent("Last closed", value: last.formatted(.dateTime.month().day().hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await vm.closeBatchNow() }
            } label: {
                if vm.isClosing {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Closing batch…")
                    }
                } else {
                    Label("Close Batch Now", systemImage: "checkmark.seal")
                }
            }
            .disabled(vm.isClosing)
            .accessibilityLabel("Close batch now")
            .accessibilityHint("Force-closes the current payment batch immediately.")

            if let err = vm.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .accessibilityLabel("Batch close error: \(err)")
            }

            if let result = vm.lastCloseResult {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("Batch closed — \(result.transactionCount) transactions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Batch successfully closed with \(result.transactionCount) transactions.")
            }
        } header: {
            Text("Batch Management")
        } footer: {
            Text("Batch auto-closes daily at the configured hour. Bar/restaurant tenants can adjust tips before close via the transaction detail view.")
                .font(.caption2)
        }
    }
}

// MARK: - Terminal offline banner (§17.3 offline behavior)

/// Inline chip shown in the POS charge sheet to indicate the terminal relay mode.
/// Cashier knows what "offline" means for their setup.
public struct TerminalRelayModeBadge: View {

    public let mode: BlockChypRelayMode

    public init(mode: BlockChypRelayMode) {
        self.mode = mode
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: mode == .cloudRelay ? "cloud.fill" : "wifi")
                .font(.caption2)
                .accessibilityHidden(true)
            Text(mode.rawValue)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundStyle(badgeColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(badgeColor.opacity(0.12), in: Capsule())
        .accessibilityLabel("Terminal mode: \(mode.rawValue). \(mode.offlineImplication)")
    }

    private var badgeColor: Color {
        mode == .cloudRelay ? .orange : .green
    }
}
#endif
