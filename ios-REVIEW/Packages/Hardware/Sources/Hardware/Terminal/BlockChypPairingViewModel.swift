import Foundation
import Observation
import Core

// §17.3 BlockChyp terminal pairing ViewModel — Phase 5

// MARK: - PairingState

/// UI-observable state for the BlockChyp pairing wizard.
public enum PairingState: Sendable, Equatable {
    case idle
    case pairing
    case paired(TerminalInfo)
    case testing
    case failed(String) // errorMessage for banner
}

// MARK: - TerminalInfo

/// Persistent metadata shown on the "paired" tile.
public struct TerminalInfo: Sendable, Equatable, Codable {
    public let name: String
    public let lastUsedAt: Date?

    public init(name: String, lastUsedAt: Date?) {
        self.name = name
        self.lastUsedAt = lastUsedAt
    }
}

// MARK: - BlockChypPairingViewModel

/// @Observable state machine for the BlockChyp pairing admin screen.
///
/// States:
///   idle       → user enters activation code → pairing
///   pairing    → API call in flight → paired(info) | failed(msg)
///   paired     → can test ($1.00 test charge) or unpair
///   testing    → $1.00 test charge in flight → paired | failed
///   failed     → shows error banner, user can retry (→ idle)
@MainActor
@Observable
public final class BlockChypPairingViewModel {

    // MARK: - Public observable state

    public private(set) var state: PairingState = .idle

    /// Bound to the activation-code text field.
    public var activationCode: String = ""

    /// Bound to the terminal name text field (defaults to "Terminal 1").
    public var terminalName: String = "Terminal 1"

    /// Controls alert/confirmation for unpair destructive action.
    public var showUnpairConfirmation: Bool = false

    // MARK: - Dependencies

    private let terminal: any CardTerminal

    // MARK: - Init

    public init(terminal: any CardTerminal) {
        self.terminal = terminal
    }

    // MARK: - Boot

    /// Call on appear. If already paired, transition to `.paired`.
    public func onAppear() async {
        let paired = await terminal.isPaired
        if paired, let name = await terminal.pairedTerminalName {
            state = .paired(TerminalInfo(name: name, lastUsedAt: lastUsedDate()))
        } else {
            state = .idle
        }
    }

    // MARK: - Pair

    /// Validate inputs then begin pairing.
    public func beginPairing(credentials: BlockChypCredentials) async {
        let code = activationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = terminalName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !code.isEmpty else {
            state = .failed("Please enter the activation code shown on the terminal screen.")
            return
        }
        guard !name.isEmpty else {
            state = .failed("Please enter a name for this terminal.")
            return
        }

        state = .pairing

        do {
            try await terminal.pair(
                apiCredentials: credentials,
                activationCode: code,
                terminalName: name
            )
            markLastUsed()
            state = .paired(TerminalInfo(name: name, lastUsedAt: lastUsedDate()))
            activationCode = ""
        } catch let termErr as TerminalError {
            state = .failed(termErr.errorDescription ?? "Pairing failed.")
        } catch {
            state = .failed(AppError.from(error).errorDescription ?? "Pairing failed.")
        }
    }

    // MARK: - Test charge ($1.00)

    /// Sends a $1.00 test charge to verify the paired terminal is working.
    public func testCharge() async {
        guard case .paired(let info) = state else { return }
        state = .testing

        do {
            let txn = try await terminal.charge(
                amountCents: 100,
                tipCents: 0,
                metadata: ["description": "Test charge from BizarreCRM"]
            )
            markLastUsed()
            state = .paired(TerminalInfo(name: info.name, lastUsedAt: lastUsedDate()))
            AppLog.hardware.info("BlockChypPairingViewModel: test charge approved=\(txn.approved)")
        } catch let termErr as TerminalError {
            state = .failed(termErr.errorDescription ?? "Test charge failed.")
        } catch {
            state = .failed(AppError.from(error).errorDescription ?? "Test charge failed.")
        }
    }

    // MARK: - Unpair

    public func confirmUnpair() {
        showUnpairConfirmation = true
    }

    public func unpair() async {
        await terminal.unpair()
        activationCode = ""
        terminalName = "Terminal 1"
        state = .idle
        showUnpairConfirmation = false
    }

    // MARK: - Retry after failure

    /// Returns state to `.idle` so the user can try again.
    public func retryFromFailure() {
        state = .idle
    }

    // MARK: - Private: last-used timestamp

    private static let lastUsedKey = "com.bizarrecrm.blockchyp.lastUsed"

    private func markLastUsed() {
        UserDefaults.standard.set(Date(), forKey: Self.lastUsedKey)
    }

    private func lastUsedDate() -> Date? {
        UserDefaults.standard.object(forKey: Self.lastUsedKey) as? Date
    }
}
