#if canImport(UIKit)
import Foundation
import Core
import Networking

// MARK: - ZReportArchiveService (§39.2 auto-archive)

/// Archives the Z-report PDF to tenant storage when a cash session closes.
///
/// Call `archive(payload:)` immediately after `POST /cash-register/close`
/// succeeds. The service renders the report data to a local JSON archive
/// (PDF rendering deferred to §17.4 print pipeline) and uploads it via
/// `POST /api/v1/pos/z-reports/archive`.
///
/// If the server endpoint is not yet deployed (404/501), the payload is
/// persisted to the app's document directory under
/// `ZReports/<date>-<sessionId>.json` so the tenant can recover it later.
/// A local URL is returned in both cases.
///
/// Usage:
/// ```swift
/// let service = ZReportArchiveService(api: apiClient)
/// let result = try await service.archive(payload: closePayload)
/// ```
public actor ZReportArchiveService {

    // MARK: - Dependencies

    private let api: APIClient

    // MARK: - Init

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Archive

    /// Archives the Z-report for `payload`.
    ///
    /// - Returns: `.uploaded(url)` when the server accepted the archive,
    ///            `.savedLocally(url)` when the endpoint was absent or unreachable.
    /// - Throws: Unexpected network errors other than 404/501.
    public func archive(payload: ZReportArchivePayload) async throws -> ZReportArchiveResult {
        let localURL = try saveLocally(payload: payload)

        do {
            let serverURL = try await uploadToServer(payload: payload)
            AppLog.pos.info(
                "ZReportArchiveService: uploaded to \(serverURL.absoluteString, privacy: .public)"
            )
            return .uploaded(serverURL: serverURL, localURL: localURL)
        } catch let APITransportError.httpStatus(code, message: _) where code == 404 || code == 501 {
            AppLog.pos.warning(
                "ZReportArchiveService: server endpoint not available (HTTP \(code)); saved locally"
            )
            return .savedLocally(localURL: localURL)
        } catch {
            AppLog.pos.error(
                "ZReportArchiveService: upload error \(error.localizedDescription, privacy: .public); saved locally"
            )
            return .savedLocally(localURL: localURL)
        }
    }

    // MARK: - Local persistence

    private func saveLocally(payload: ZReportArchivePayload) throws -> URL {
        let dir = try localArchiveDirectory()
        let filename = archiveFilename(payload: payload)
        let fileURL = dir.appendingPathComponent(filename)
        let data = try JSONEncoder().encode(payload)
        try data.write(to: fileURL, options: .atomic)
        AppLog.pos.info(
            "ZReportArchiveService: saved locally to \(fileURL.lastPathComponent, privacy: .public)"
        )
        return fileURL
    }

    private func localArchiveDirectory() throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("ZReports", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func archiveFilename(payload: ZReportArchivePayload) -> String {
        let datePart = payload.closedAt.prefix(10)    // "YYYY-MM-DD"
        let idPart = payload.sessionId.map { "\($0)" } ?? "unknown"
        return "ZReport-\(datePart)-\(idPart).json"
    }

    // MARK: - Server upload

    private func uploadToServer(payload: ZReportArchivePayload) async throws -> URL {
        let response = try await api.archiveZReport(payload: payload)
        return response.archiveURL
    }
}

// MARK: - ZReportArchivePayload

/// Data sent to the server when archiving a Z-report.
/// Mirrors the close payload with additional rendering metadata.
public struct ZReportArchivePayload: Codable, Sendable {
    public let sessionId: Int64?
    public let openedAt: String
    public let closedAt: String
    public let openingFloatCents: Int
    public let closingCountCents: Int?
    public let expectedCashCents: Int?
    public let varianceCents: Int?
    public let totalSalesCents: Int
    public let totalRefundsCents: Int
    public let totalVoidsCents: Int
    public let cashierNotes: String?
    public let tendersBreakdown: [String: Int]

    public init(
        sessionId: Int64?,
        openedAt: Date,
        closedAt: Date,
        openingFloatCents: Int,
        closingCountCents: Int?,
        expectedCashCents: Int?,
        varianceCents: Int?,
        totalSalesCents: Int,
        totalRefundsCents: Int,
        totalVoidsCents: Int,
        cashierNotes: String?,
        tendersBreakdown: [String: Int] = [:]
    ) {
        let f = ISO8601DateFormatter()
        self.sessionId = sessionId
        self.openedAt = f.string(from: openedAt)
        self.closedAt = f.string(from: closedAt)
        self.openingFloatCents = openingFloatCents
        self.closingCountCents = closingCountCents
        self.expectedCashCents = expectedCashCents
        self.varianceCents = varianceCents
        self.totalSalesCents = totalSalesCents
        self.totalRefundsCents = totalRefundsCents
        self.totalVoidsCents = totalVoidsCents
        self.cashierNotes = cashierNotes
        self.tendersBreakdown = tendersBreakdown
    }

    enum CodingKeys: String, CodingKey {
        case sessionId           = "session_id"
        case openedAt            = "opened_at"
        case closedAt            = "closed_at"
        case openingFloatCents   = "opening_float_cents"
        case closingCountCents   = "closing_count_cents"
        case expectedCashCents   = "expected_cash_cents"
        case varianceCents       = "variance_cents"
        case totalSalesCents     = "total_sales_cents"
        case totalRefundsCents   = "total_refunds_cents"
        case totalVoidsCents     = "total_voids_cents"
        case cashierNotes        = "cashier_notes"
        case tendersBreakdown    = "tenders_breakdown"
    }
}

// MARK: - ZReportArchiveResult

public enum ZReportArchiveResult: Sendable {
    /// Report was uploaded to the server. `localURL` is the cached copy.
    case uploaded(serverURL: URL, localURL: URL)
    /// Server endpoint absent or unreachable; report saved to device only.
    case savedLocally(localURL: URL)

    /// The local file URL regardless of outcome.
    public var localURL: URL {
        switch self {
        case .uploaded(_, let url): return url
        case .savedLocally(let url): return url
        }
    }

    /// Whether the report was successfully uploaded to the server.
    public var wasUploaded: Bool {
        if case .uploaded = self { return true }
        return false
    }
}

// MARK: - Server response

private struct ZReportArchiveResponse: Decodable, Sendable {
    let success: Bool
    let archiveURL: URL

    enum CodingKeys: String, CodingKey {
        case success
        case archiveURL = "archive_url"
    }
}

// MARK: - APIClient extension

extension APIClient {
    /// `POST /api/v1/pos/z-reports/archive`
    ///
    /// Uploads the Z-report payload to tenant storage.
    /// Server route: planned in phase-6; may 404/501 until deployed.
    fileprivate func archiveZReport(payload: ZReportArchivePayload) async throws -> ZReportArchiveResponse {
        return try await post(
            "/pos/z-reports/archive",
            body: payload,
            as: ZReportArchiveResponse.self
        )
    }
}

// MARK: - ZReportArchiveButton (embeds in ZReportView action row)

import SwiftUI
import DesignSystem

/// "Archive to tenant storage" button for the Z-report action row.
/// Companion to `ZReportEmailButton` — same visual style, different action.
public struct ZReportArchiveButton: View {

    let payload: ZReportArchivePayload
    let api: APIClient?

    @State private var isArchiving: Bool = false
    @State private var result: ZReportArchiveResult?
    @State private var errorMessage: String?

    public init(payload: ZReportArchivePayload, api: APIClient?) {
        self.payload = payload
        self.api = api
    }

    public var body: some View {
        Button {
            guard let api else { errorMessage = "Server not connected."; return }
            Task { await archive(api: api) }
        } label: {
            Group {
                if isArchiving {
                    ProgressView().scaleEffect(0.85)
                } else if let result {
                    switch result {
                    case .uploaded:
                        Label("Archived", systemImage: "checkmark.icloud")
                            .foregroundStyle(.bizarreSuccess)
                    case .savedLocally:
                        Label("Saved locally", systemImage: "internaldrive")
                            .foregroundStyle(.bizarreWarning)
                    }
                } else {
                    Label("Archive report", systemImage: "tray.and.arrow.up")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isArchiving || result != nil)
        .alert("Archive failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .accessibilityIdentifier("pos.zReport.archive")
    }

    private func archive(api: APIClient) async {
        isArchiving = true
        defer { isArchiving = false }
        errorMessage = nil
        do {
            let service = ZReportArchiveService(api: api)
            let r = try await service.archive(payload: payload)
            result = r
            AppLog.pos.info(
                "Z-report archive: \(r.wasUploaded ? "uploaded" : "local only", privacy: .public)"
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
#endif
