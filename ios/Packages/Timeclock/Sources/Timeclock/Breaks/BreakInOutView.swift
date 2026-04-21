import SwiftUI
import DesignSystem
import Networking

// MARK: - BreakInOutViewModel

@MainActor
@Observable
public final class BreakInOutViewModel {

    public enum State: Sendable, Equatable {
        case idle
        case loading
        case onBreak(BreakEntry)
        case failed(String)
    }

    public private(set) var state: State = .idle
    public let tracker: BreakDurationTracker

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored public var userIdProvider: @Sendable () async -> Int64
    @ObservationIgnored public var shiftIdProvider: @Sendable () async -> Int64

    public init(
        api: APIClient,
        userIdProvider: @escaping @Sendable () async -> Int64 = { 0 },
        shiftIdProvider: @escaping @Sendable () async -> Int64 = { 0 },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.api = api
        self.userIdProvider = userIdProvider
        self.shiftIdProvider = shiftIdProvider
        self.tracker = BreakDurationTracker(now: now)
    }

    public func startBreak(kind: BreakKind) async {
        state = .loading
        let employeeId = await userIdProvider()
        let shiftId = await shiftIdProvider()
        do {
            let entry = try await api.startBreak(employeeId: employeeId, shiftId: shiftId, kind: kind)
            state = .onBreak(entry)
            tracker.breakDidStart(entry)
        } catch {
            state = .failed(error.localizedDescription)
            tracker.setFailed(error.localizedDescription)
        }
    }

    public func endBreak() async {
        guard case let .onBreak(entry) = state else { return }
        state = .loading
        do {
            _ = try await api.endBreak(breakId: entry.id)
            state = .idle
            tracker.breakDidEnd()
        } catch {
            state = .failed(error.localizedDescription)
            tracker.setFailed(error.localizedDescription)
        }
    }

    public func tick() {
        tracker.tick()
    }
}

// MARK: - BreakInOutView

/// Modal sheet shown from `ClockInOutTile` to start or end a break.
///
/// Liquid Glass on the sheet header per CLAUDE.md mandate.
/// Supports Reduce Motion via `@Environment(\.accessibilityReduceMotion)`.
public struct BreakInOutView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Bindable var vm: BreakInOutViewModel

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    public init(vm: BreakInOutViewModel) {
        self.vm = vm
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: DesignTokens.Spacing.xl) {
                headerSection
                if case .onBreak = vm.state {
                    onBreakSection
                } else {
                    startBreakSection
                }
                Spacer()
            }
            .padding(DesignTokens.Spacing.lg)
            .navigationTitle("Break")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Dismiss break sheet")
                }
            }
        }
        .onReceive(timer) { _ in vm.tick() }
    }

    // MARK: - Sections

    @ViewBuilder
    private var headerSection: some View {
        if case let .onBreak(entry) = vm.state {
            VStack(spacing: DesignTokens.Spacing.sm) {
                Text("On Break")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(BreakDurationTracker.formatElapsed(vm.tracker.elapsedSeconds))
                    .font(.system(.largeTitle, design: .rounded).monospacedDigit())
                    .contentTransition(reduceMotion ? .identity : .numericText())
                Text("Kind: \(entry.kind.rawValue.capitalized)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Start a Break")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private var startBreakSection: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ForEach(BreakKind.allCases, id: \.self) { kind in
                Button {
                    Task { await vm.startBreak(kind: kind) }
                } label: {
                    Label(kind.rawValue.capitalized, systemImage: iconName(for: kind))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                }
                .accessibilityLabel("Start \(kind.rawValue) break")
                .disabled(vm.state == .loading)
            }
        }

        if case let .failed(msg) = vm.state {
            Text(msg)
                .foregroundStyle(.red)
                .font(.caption)
                .accessibilityLabel("Error: \(msg)")
        }
    }

    @ViewBuilder
    private var onBreakSection: some View {
        Button(role: .destructive) {
            Task { await vm.endBreak() }
        } label: {
            Label("End Break", systemImage: "stop.circle.fill")
                .frame(maxWidth: .infinity)
                .padding()
                .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        }
        .accessibilityLabel("End current break")
        .disabled(vm.state == .loading)

        if case let .failed(msg) = vm.state {
            Text(msg)
                .foregroundStyle(.red)
                .font(.caption)
                .accessibilityLabel("Error: \(msg)")
        }
    }

    // MARK: - Helpers

    private func iconName(for kind: BreakKind) -> String {
        switch kind {
        case .meal:  return "fork.knife"
        case .rest:  return "cup.and.saucer"
        case .other: return "ellipsis.circle"
        }
    }
}
