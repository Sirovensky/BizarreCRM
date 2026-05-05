#if canImport(SwiftUI)
import SwiftUI

// MARK: - TestActionState

/// Result of a hardware test action.
public enum TestActionState: Equatable, Sendable {
    case idle
    case running
    case success(String)
    case failure(String)
}

// MARK: - DeviceTestActionsViewModel

/// Observable view-model driving the inline test-fire buttons in the detail column.
///
/// Each device type exposes the set of test actions relevant to it.
/// Real hardware calls are mocked at this layer; integration is the responsibility
/// of the concrete hardware subsystem (PrintEngine, CashDrawer, WeightScale, etc.).
@Observable
@MainActor
public final class DeviceTestActionsViewModel {

    // MARK: State

    public var printerTestState: TestActionState = .idle
    public var drawerTestState:  TestActionState = .idle
    public var scaleTestState:   TestActionState = .idle
    public var scannerTestState: TestActionState = .idle
    public var terminalTestState: TestActionState = .idle

    // Injectable closures — replace in tests or when wiring real hardware.
    public var onPrintTestPage:    (() async throws -> Void)?
    public var onOpenDrawer:       (() async throws -> Void)?
    public var onReadScale:        (() async throws -> String)?
    public var onTestScanner:      (() async throws -> Void)?
    public var onPingTerminal:     (() async throws -> String)?

    public init() {}

    // MARK: - Printer: print test page

    public func printTestPage() async {
        guard printerTestState != .running else { return }
        printerTestState = .running
        do {
            try await (onPrintTestPage ?? { try await Task.sleep(nanoseconds: 500_000_000) })()
            printerTestState = .success("Test page sent")
        } catch {
            printerTestState = .failure(error.localizedDescription)
        }
    }

    // MARK: - Drawer: open test

    public func openDrawer() async {
        guard drawerTestState != .running else { return }
        drawerTestState = .running
        do {
            try await (onOpenDrawer ?? { try await Task.sleep(nanoseconds: 300_000_000) })()
            drawerTestState = .success("Drawer opened")
        } catch {
            drawerTestState = .failure(error.localizedDescription)
        }
    }

    // MARK: - Scale: live read

    public func readScale() async {
        guard scaleTestState != .running else { return }
        scaleTestState = .running
        do {
            let reading = try await (onReadScale ?? {
                try await Task.sleep(nanoseconds: 400_000_000)
                return "0 g (no scale paired)"
            })()
            scaleTestState = .success(reading)
        } catch {
            scaleTestState = .failure(error.localizedDescription)
        }
    }

    // MARK: - Scanner: test beep / trigger

    public func testScanner() async {
        guard scannerTestState != .running else { return }
        scannerTestState = .running
        do {
            try await (onTestScanner ?? { try await Task.sleep(nanoseconds: 300_000_000) })()
            scannerTestState = .success("Scanner triggered")
        } catch {
            scannerTestState = .failure(error.localizedDescription)
        }
    }

    // MARK: - Terminal: ping

    public func pingTerminal() async {
        guard terminalTestState != .running else { return }
        terminalTestState = .running
        do {
            let result = try await (onPingTerminal ?? {
                try await Task.sleep(nanoseconds: 500_000_000)
                return "No terminal paired"
            })()
            terminalTestState = .success(result)
        } catch {
            terminalTestState = .failure(error.localizedDescription)
        }
    }

    // MARK: - Reset helpers

    public func resetAll() {
        printerTestState  = .idle
        drawerTestState   = .idle
        scaleTestState    = .idle
        scannerTestState  = .idle
        terminalTestState = .idle
    }

    public func reset(for type: HardwareDeviceType) {
        switch type {
        case .printer:  printerTestState  = .idle
        case .drawer:   drawerTestState   = .idle
        case .scale:    scaleTestState    = .idle
        case .scanner:  scannerTestState  = .idle
        case .terminal: terminalTestState = .idle
        }
    }
}

// MARK: - DeviceTestActions (View)

/// Inline test-fire button panel for a given device type.
///
/// Placement: top section of the detail column in `HardwareThreeColumnView`.
/// Shows one or more test buttons with live state feedback (spinner → success/error badge).
/// Liquid Glass applied to the action card chrome only.
public struct DeviceTestActions: View {

    let deviceType: HardwareDeviceType
    @Bindable var vm: DeviceTestActionsViewModel

    public init(deviceType: HardwareDeviceType, vm: DeviceTestActionsViewModel) {
        self.deviceType = deviceType
        self.vm = vm
    }

    public var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                testButtons
            }
        } label: {
            Label("Test Actions", systemImage: "bolt.fill")
                .font(.headline)
                .foregroundStyle(deviceType.accentColor)
        }
        .padding(.horizontal)
    }

    // MARK: - Per-device buttons

    @ViewBuilder
    private var testButtons: some View {
        switch deviceType {
        case .printer:
            TestActionButton(
                title: "Print Test Page",
                systemImage: "doc.text.fill",
                state: vm.printerTestState,
                accentColor: deviceType.accentColor
            ) {
                Task { await vm.printTestPage() }
            }
            .accessibilityLabel("Print test page")
            .accessibilityHint("Sends a test receipt to the default printer")

        case .drawer:
            TestActionButton(
                title: "Open Drawer",
                systemImage: "tray.full.fill",
                state: vm.drawerTestState,
                accentColor: deviceType.accentColor
            ) {
                Task { await vm.openDrawer() }
            }
            .accessibilityLabel("Open cash drawer")
            .accessibilityHint("Sends an ESC/POS kick command to open the drawer")

        case .scale:
            TestActionButton(
                title: "Read Weight",
                systemImage: "scalemass.fill",
                state: vm.scaleTestState,
                accentColor: deviceType.accentColor
            ) {
                Task { await vm.readScale() }
            }
            .accessibilityLabel("Read weight from scale")
            .accessibilityHint("Takes a single stable reading from the paired scale")

        case .scanner:
            TestActionButton(
                title: "Test Scanner",
                systemImage: "barcode.viewfinder",
                state: vm.scannerTestState,
                accentColor: deviceType.accentColor
            ) {
                Task { await vm.testScanner() }
            }
            .accessibilityLabel("Test barcode scanner")
            .accessibilityHint("Triggers the scanner and waits for a scan result")

        case .terminal:
            TestActionButton(
                title: "Ping Terminal",
                systemImage: "network",
                state: vm.terminalTestState,
                accentColor: deviceType.accentColor
            ) {
                Task { await vm.pingTerminal() }
            }
            .accessibilityLabel("Ping payment terminal")
            .accessibilityHint("Checks network connectivity to the paired terminal")
        }
    }
}

// MARK: - TestActionButton

/// Reusable button that reflects running / success / failure state inline.
private struct TestActionButton: View {
    let title: String
    let systemImage: String
    let state: TestActionState
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .font(.body.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)
            .disabled(state == .running)

            stateIndicator
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch state {
        case .idle:
            EmptyView()
        case .running:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Test in progress")
        case .success(let msg):
            Label(msg, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .transition(.opacity)
                .accessibilityLabel("Success: \(msg)")
        case .failure(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
                .transition(.opacity)
                .accessibilityLabel("Failed: \(msg)")
        }
    }
}

#endif
