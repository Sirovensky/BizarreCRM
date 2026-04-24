import Foundation
import Networking
import Persistence

// MARK: - Server-side register state (confirmed routes)

/// Response data from `GET /pos/register`.
/// Server: packages/server/src/routes/pos.routes.ts:172
/// Envelope: { success, data: { cash_in, cash_out, cash_sales, net, entries } }
public struct RegisterStateDTO: Decodable, Sendable {
    public let cashIn: Int          // cents summed today
    public let cashOut: Int         // cents summed today
    public let cashSales: Int       // cents from cash tender payments today
    public let net: Int             // cashIn + cashSales - cashOut
    public let entries: [RegisterEntryDTO]
}

public struct RegisterEntryDTO: Decodable, Sendable, Identifiable {
    public let id: Int
    public let type: String         // "cash_in" | "cash_out" | "drawer_open"
    public let amount: Int          // cents
    public let reason: String?
    public let userName: String?
    public let createdAt: String?
}

/// Request body for `POST /pos/cash-in` and `POST /pos/cash-out`.
/// Server validates amount > 0 and <= 50_000 (cents=$50,000).
struct CashMoveRequest: Encodable, Sendable {
    let amount: Int        // cents — validated server-side
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case amount
        case reason
    }
}

/// Response from `POST /pos/cash-in` or `POST /pos/cash-out`.
/// Envelope data: `{ entry: { id, type, amount, reason, user_id, created_at } }`
public struct CashMoveResponseWrapper: Decodable, Sendable {
    public let entry: RegisterEntryDTO
}

// MARK: - Protocol

/// §39 — Cash session repository.
///
/// Wraps the confirmed POS register endpoints. Cash session open/close live
/// locally in `CashRegisterStore` (Persistence) because the server-side
/// `/pos/cash-sessions` endpoints do not yet exist (ticket POS-SESSIONS-001).
///
/// All amounts are in **cents** at this layer. Views convert to/from Decimal
/// via `CartMath`.
public protocol CashSessionRepository: Sendable {
    /// Fetch today's register state from the server.
    /// Route: `GET /pos/register`
    func fetchRegisterState() async throws -> RegisterStateDTO

    /// Record a cash-in event (e.g., manager deposits float into drawer).
    /// Route: `POST /pos/cash-in`
    /// - Parameters:
    ///   - amountCents: Must be 1…5_000_000 (server cap: $50,000).
    ///   - reason: Optional free-text note.
    func postCashIn(amountCents: Int, reason: String?) async throws -> RegisterEntryDTO

    /// Record a cash-out event (e.g., manager pulls money from drawer).
    /// Route: `POST /pos/cash-out`
    /// - Parameters:
    ///   - amountCents: Must be 1…5_000_000 (server cap: $50,000).
    ///   - reason: Optional free-text note.
    func postCashOut(amountCents: Int, reason: String?) async throws -> RegisterEntryDTO

    // MARK: — Local-only session management (no server endpoint yet)

    /// Open a local cash session. Delegates to `CashRegisterStore`.
    /// Falls back gracefully if a session is already open.
    func openSession(openingFloatCents: Int, userId: Int64) async throws -> CashSessionRecord

    /// Close the active local cash session. Delegates to `CashRegisterStore`.
    func closeSession(
        countedCash: Int,
        expectedCash: Int,
        notes: String?,
        closedBy: Int64
    ) async throws -> CashSessionRecord

    /// The currently-open session, or `nil` when the register is closed.
    func currentSession() async throws -> CashSessionRecord?

    /// Recent sessions, newest first (drives history list).
    func recentSessions(limit: Int) async throws -> [CashSessionRecord]
}
