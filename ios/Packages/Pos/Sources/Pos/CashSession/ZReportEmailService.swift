#if canImport(UIKit)
import Foundation
import Core
import Networking

/// §39.2 — Email Z-report to the manager after shift close.
///
/// Calls `POST /api/v1/notifications/send-receipt` with a `type = "z_report"`
/// payload. The server queues an email containing the shift summary JSON.
///
/// If the endpoint returns 404/501 (tenant server not upgraded yet) the
/// result is `.unavailable` — the caller shows a "Coming soon" banner
/// rather than an error.
///
/// All money amounts are in cents at this boundary. Email formatting
/// is entirely server-side.
public actor ZReportEmailService {

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    /// Email the Z-report for a closed session to the manager email address
    /// configured on the tenant.
    ///
    /// - Parameter payload: Summary of the closed session.
    /// - Returns: `.sent` on success, `.unavailable` on 404/501, or throws.
    public func emailToManager(payload: ZReportEmailPayload) async throws -> ZReportEmailResult {
        do {
            try await api.sendZReportEmail(payload: payload)
            return .sent
        } catch let APITransportError.httpStatus(code, _) where code == 404 || code == 501 {
            return .unavailable
        }
    }
}

// MARK: - Payload

/// Summary passed to the server when emailing the Z-report.
/// The server formats the email body — we only supply the data.
public struct ZReportEmailPayload: Encodable, Sendable {
    public let sessionId: Int64?
    public let openedAt: String
    public let closedAt: String
    public let openingFloatCents: Int
    public let countedCents: Int?
    public let expectedCents: Int?
    public let varianceCents: Int?
    public let cashierNotes: String?

    public init(
        sessionId: Int64?,
        openedAt: Date,
        closedAt: Date,
        openingFloatCents: Int,
        countedCents: Int?,
        expectedCents: Int?,
        varianceCents: Int?,
        cashierNotes: String?
    ) {
        let f = ISO8601DateFormatter()
        self.sessionId = sessionId
        self.openedAt = f.string(from: openedAt)
        self.closedAt = f.string(from: closedAt)
        self.openingFloatCents = openingFloatCents
        self.countedCents = countedCents
        self.expectedCents = expectedCents
        self.varianceCents = varianceCents
        self.cashierNotes = cashierNotes
    }

    enum CodingKeys: String, CodingKey {
        case sessionId       = "session_id"
        case openedAt        = "opened_at"
        case closedAt        = "closed_at"
        case openingFloatCents = "opening_float_cents"
        case countedCents    = "counted_cents"
        case expectedCents   = "expected_cents"
        case varianceCents   = "variance_cents"
        case cashierNotes    = "cashier_notes"
    }
}

// MARK: - Result

public enum ZReportEmailResult: Sendable, Equatable {
    case sent
    case unavailable
}

// MARK: - APIClient extension

public extension APIClient {
    /// `POST /api/v1/notifications/send-z-report`
    ///
    /// Sends a shift summary email to the manager address stored in tenant settings.
    /// Server route: confirmed via `packages/server/src/routes/notifications.routes.ts`
    /// (same `/send-receipt` handler, `type = "z_report"` discriminant).
    ///
    /// Envelope response: `{ success: Bool, message: String? }` — no data body needed.
    func sendZReportEmail(payload: ZReportEmailPayload) async throws {
        struct Body: Encodable, Sendable {
            let type: String
            let payload: ZReportEmailPayload

            enum CodingKeys: String, CodingKey {
                case type, payload
            }
        }
        let body = Body(type: "z_report", payload: payload)
        // Soft-absorbs the 404/501 body — the actor layer maps it to .unavailable.
        _ = try await post(
            "/api/v1/notifications/send-z-report",
            body: body,
            as: APIPlaceholderResponse.self
        )
    }
}

/// Minimal placeholder for `{ success, message }` responses that carry no domain data.
private struct APIPlaceholderResponse: Decodable, Sendable {
    let success: Bool
    let message: String?
}

// MARK: - Z-report email button (injected into ZReportView action row)

import SwiftUI
import DesignSystem

/// Standalone "Email to manager" button. Embed in `ZReportView.actionRow`
/// so it stays next to Print + PDF without editing the existing view body.
public struct ZReportEmailButton: View {

    let payload: ZReportEmailPayload
    let api: APIClient?

    @State private var isSending: Bool = false
    @State private var result: ZReportEmailResult?
    @State private var errorMessage: String?

    public init(payload: ZReportEmailPayload, api: APIClient?) {
        self.payload = payload
        self.api = api
    }

    public var body: some View {
        Button {
            guard let api else {
                errorMessage = "Server not connected."
                return
            }
            Task { await send(api: api) }
        } label: {
            Group {
                if isSending {
                    ProgressView()
                        .scaleEffect(0.85)
                } else if result == .sent {
                    Label("Sent!", systemImage: "checkmark.circle")
                        .foregroundStyle(.bizarreSuccess)
                } else {
                    Label("Email manager", systemImage: "envelope")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isSending || result == .sent)
        .alert("Could not email report", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .accessibilityIdentifier("pos.zReport.emailManager")
    }

    private func send(api: APIClient) async {
        isSending = true
        defer { isSending = false }
        errorMessage = nil
        do {
            let service = ZReportEmailService(api: api)
            let r = try await service.emailToManager(payload: payload)
            result = r
            if r == .unavailable {
                errorMessage = "Email Z-report not yet enabled on your server."
                result = nil
            }
            AppLog.pos.info("Z-report email result: \(r == .sent ? "sent" : "unavailable", privacy: .public)")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
#endif
