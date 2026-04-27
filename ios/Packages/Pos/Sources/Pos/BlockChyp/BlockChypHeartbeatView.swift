#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

/// §16.5 — BlockChyp terminal heartbeat indicator shown in the POS chrome.
///
/// SCAFFOLD ONLY — no payment math. This view polls the server heartbeat
/// endpoint every 10 seconds while the POS screen is active and surfaces a
/// colour-coded badge: online / offline / unknown.
///
/// The actual heartbeat RPC (`GET /blockchyp/terminal-status`) is stubbed in
/// `APIClient+Pos.swift` until Agent 2 wires the Hardware SDK. This view
/// gracefully degrades to `.unknown` when the endpoint returns 501.
@MainActor
public struct BlockChypHeartbeatView: View {

    // MARK: - Terminal state (§16.5)

    public enum TerminalHeartbeatState: Equatable {
        case unknown
        case online(terminalName: String?)
        case offline
        case checking
    }

    // MARK: - State

    @State private var heartbeatState: TerminalHeartbeatState = .unknown
    @State private var pollingTask: Task<Void, Never>?

    private let api: APIClient?

    // MARK: - Init

    public init(api: APIClient?) {
        self.api = api
    }

    // MARK: - Body

    public var body: some View {
        button
            .task { await startPolling() }
            .onDisappear { pollingTask?.cancel() }
    }

    private var button: some View {
        Button {
            // Tap → manual refresh
            Task { await ping() }
        } label: {
            HStack(spacing: BrandSpacing.xs) {
                heartbeatDot
                Text(heartbeatLabel)
                    .font(.brandLabelSmall())
                    .foregroundStyle(heartbeatColor)
            }
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xs)
            .brandGlass(.subtle, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Terminal: \(heartbeatLabel). Tap to refresh.")
        .accessibilityIdentifier("blockchyp.heartbeat")
    }

    @ViewBuilder
    private var heartbeatDot: some View {
        if case .checking = heartbeatState {
            ProgressView()
                .scaleEffect(0.7)
                .tint(heartbeatColor)
        } else {
            Circle()
                .fill(heartbeatColor)
                .frame(width: 8, height: 8)
        }
    }

    // MARK: - Derived

    private var heartbeatLabel: String {
        switch heartbeatState {
        case .unknown:
            return "No terminal"
        case .online(let name):
            return name.map { "Terminal · \($0)" } ?? "Terminal online"
        case .offline:
            return "Terminal offline"
        case .checking:
            return "Checking…"
        }
    }

    private var heartbeatColor: Color {
        switch heartbeatState {
        case .unknown:   return .bizarreOnSurfaceMuted
        case .online:    return .bizarreSuccess
        case .offline:   return .bizarreError
        case .checking:  return .bizarreOrange
        }
    }

    // MARK: - Polling

    private func startPolling() async {
        pollingTask?.cancel()
        await ping()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.ping()
            }
        }
    }

    private func ping() async {
        guard let api else {
            heartbeatState = .unknown
            return
        }
        heartbeatState = .checking

        // Check if a pairing is stored first.
        guard PairingKeychainStore.load(key: "com.bizarrecrm.pos.terminal") != nil else {
            heartbeatState = .unknown
            return
        }

        do {
            let status = try await api.getTerminalHeartbeat()
            heartbeatState = .online(terminalName: status.terminalName)
        } catch let APITransportError.httpStatus(code, _) where code == 501 {
            // Endpoint not yet live — treat as unknown (not error).
            heartbeatState = .unknown
        } catch {
            heartbeatState = .offline
        }
    }
}

// MARK: - Terminal reader state view (§16.5)

/// Displays the current card-reader state during a BlockChyp charge attempt.
/// Shown inside `PosChargePlaceholderSheet` until the real SDK flow lands.
///
/// States: waitForCard / chipInserted / pinEntered / awaitingSignature /
///         approved / declined / timeout (all defined in §16.5).
public struct BlockChypReaderStateView: View {

    public enum ReaderState: Equatable {
        case waitForCard
        case chipInserted
        case pinEntered
        case awaitingSignature
        case approved
        case declined(reason: String)
        case timeout

        var displayTitle: String {
            switch self {
            case .waitForCard:         return "Waiting for card"
            case .chipInserted:        return "Card inserted"
            case .pinEntered:          return "PIN entered"
            case .awaitingSignature:   return "Awaiting signature"
            case .approved:            return "Approved"
            case .declined:            return "Declined"
            case .timeout:             return "Timeout"
            }
        }

        var displaySubtitle: String {
            switch self {
            case .waitForCard:         return "Present card, phone or watch to the reader."
            case .chipInserted:        return "Processing — do not remove card."
            case .pinEntered:          return "Verifying PIN…"
            case .awaitingSignature:   return "Please sign on the terminal."
            case .approved:            return "Payment approved."
            case .declined(let reason): return reason.isEmpty ? "Payment declined." : reason
            case .timeout:             return "No response from card. Try again or use another tender."
            }
        }

        var icon: String {
            switch self {
            case .waitForCard:         return "creditcard.and.123"
            case .chipInserted:        return "creditcard.fill"
            case .pinEntered:          return "lock.fill"
            case .awaitingSignature:   return "signature"
            case .approved:            return "checkmark.seal.fill"
            case .declined:            return "xmark.seal.fill"
            case .timeout:             return "clock.badge.exclamationmark"
            }
        }

        var color: Color {
            switch self {
            case .approved:  return .bizarreSuccess
            case .declined:  return .bizarreError
            case .timeout:   return .bizarreWarning
            default:         return .bizarreOrange
            }
        }

        var isTerminal: Bool {
            switch self {
            case .approved, .declined, .timeout: return true
            default: return false
            }
        }
    }

    public let state: ReaderState

    public init(state: ReaderState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: BrandSpacing.lg) {
            // Icon
            ZStack {
                Circle()
                    .fill(state.color.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: state.icon)
                    .font(.system(size: 40))
                    .foregroundStyle(state.color)
            }
            .accessibilityHidden(true)

            // Title + subtitle
            VStack(spacing: BrandSpacing.xs) {
                Text(state.displayTitle)
                    .font(.brandTitleLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .multilineTextAlignment(.center)

                Text(state.displaySubtitle)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.xl)
            }

            // Progress indicator for in-flight states
            if !state.isTerminal {
                ProgressView()
                    .tint(.bizarreOrange)
                    .scaleEffect(1.2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BrandSpacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(state.displayTitle). \(state.displaySubtitle)")
    }
}

// MARK: - Preview

#Preview("Heartbeat — Online") {
    BlockChypHeartbeatView(api: nil)
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Reader states") {
    ScrollView {
        VStack(spacing: BrandSpacing.xl) {
            BlockChypReaderStateView(state: .waitForCard)
            BlockChypReaderStateView(state: .chipInserted)
            BlockChypReaderStateView(state: .awaitingSignature)
            BlockChypReaderStateView(state: .approved)
            BlockChypReaderStateView(state: .declined(reason: "Insufficient funds"))
            BlockChypReaderStateView(state: .timeout)
        }
        .padding()
    }
    .background(Color.bizarreSurfaceBase.ignoresSafeArea())
    .preferredColorScheme(.dark)
}
#endif
