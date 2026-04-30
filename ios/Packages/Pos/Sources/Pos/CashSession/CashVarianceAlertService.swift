import Foundation
import Core
import Networking

// MARK: - CashVarianceAlertService (§39.4 variance alerts)

/// Evaluates cash variance at session close and triggers a manager push alert
/// when the overage or shortage exceeds the tenant-configured threshold.
///
/// Push delivery: calls `POST /api/v1/notifications/send` with
/// `type = "cash_variance_alert"`. The server routes this to the manager's
/// device via APNs. If the endpoint is unavailable (404/501), the alert is
/// silently skipped — the variance is still visible in the Z-report.
///
/// Threshold: loaded from `GET /settings/pos` (`variance_alert_threshold_cents`).
/// Defaults to 500 cents ($5.00) when the field is absent.
///
/// Usage:
/// ```swift
/// let svc = CashVarianceAlertService(api: apiClient)
/// let fired = try await svc.evaluateAndAlert(
///     varianceCents: session.varianceCents,
///     sessionId: session.id
/// )
/// ```
public actor CashVarianceAlertService {

    // MARK: - Defaults

    /// Default threshold in cents when the tenant has not configured one.
    public static let defaultThresholdCents: Int = 500

    // MARK: - Dependencies

    private let api: APIClient

    // MARK: - Init

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Evaluate & alert

    /// Check variance against the configured threshold and send an alert if exceeded.
    ///
    /// - Parameters:
    ///   - varianceCents: Signed variance (positive = overage, negative = shortage).
    ///   - sessionId: The cash session ID — embedded in the push payload.
    ///   - thresholdCents: Override threshold; pass `nil` to load from server settings.
    /// - Returns: `true` when an alert was dispatched (or attempted), `false` otherwise.
    @discardableResult
    public func evaluateAndAlert(
        varianceCents: Int,
        sessionId: Int64?,
        thresholdCents: Int? = nil
    ) async throws -> Bool {
        let threshold: Int
        if let override = thresholdCents {
            threshold = override
        } else {
            threshold = (try? await loadThreshold()) ?? Self.defaultThresholdCents
        }
        let absVariance = abs(varianceCents)

        guard absVariance >= threshold else {
            AppLog.pos.info(
                "CashVarianceAlertService: variance \(absVariance)¢ below threshold \(threshold)¢ — no alert"
            )
            return false
        }

        let direction: String = varianceCents > 0 ? "overage" : "shortage"
        let formatted = String(format: "$%.2f", Double(absVariance) / 100.0)
        let message = "Cash variance \(direction): \(formatted). Session \(sessionId.map { "#\($0)" } ?? "(unknown)")."

        AppLog.pos.warning(
            "CashVarianceAlertService: threshold exceeded (\(absVariance)¢ ≥ \(threshold)¢) — sending push"
        )

        do {
            try await api.sendVarianceAlert(
                sessionId: sessionId,
                varianceCents: varianceCents,
                message: message
            )
            return true
        } catch let APITransportError.httpStatus(code, message: _) where code == 404 || code == 501 {
            AppLog.pos.warning(
                "CashVarianceAlertService: push endpoint not available (HTTP \(code)) — alert skipped"
            )
            return false
        }
    }

    // MARK: - Load threshold

    private func loadThreshold() async throws -> Int {
        let settings = try await api.getPosVarianceSettings()
        return settings.varianceAlertThresholdCents ?? Self.defaultThresholdCents
    }
}

// MARK: - POS settings model (variance threshold)

/// Subset of the tenant POS settings needed by the variance alert service.
public struct PosVarianceSettings: Decodable, Sendable {
    /// Cents threshold above which a manager push alert is triggered.
    /// Nil means the field is not set on the server.
    public let varianceAlertThresholdCents: Int?

    enum CodingKeys: String, CodingKey {
        case varianceAlertThresholdCents = "variance_alert_threshold_cents"
    }
}

// MARK: - APIClient extension (variance alert push)

extension APIClient {
    /// `POST /notifications/send` with `type = "cash_variance_alert"`.
    ///
    /// Server queues a push to the manager role. 404/501 → server not upgraded yet.
    fileprivate func sendVarianceAlert(
        sessionId: Int64?,
        varianceCents: Int,
        message: String
    ) async throws {
        _ = try await post(
            "/notifications/send",
            body: VarianceAlertBody(type: "cash_variance_alert", sessionId: sessionId,
                                    varianceCents: varianceCents, message: message),
            as: VarianceAlertResponse.self
        )
    }

    /// `GET /settings/pos` — loads variance threshold.
    fileprivate func getPosVarianceSettings() async throws -> PosVarianceSettings {
        let env = try await get("/settings/pos", as: PosVarianceEnvelope.self)
        return env.data ?? PosVarianceSettings(varianceAlertThresholdCents: nil)
    }
}

private struct VarianceAlertBody: Encodable, Sendable {
    let type: String
    let sessionId: Int64?
    let varianceCents: Int
    let message: String

    enum CodingKeys: String, CodingKey {
        case type
        case sessionId      = "session_id"
        case varianceCents  = "variance_cents"
        case message
    }
}

private struct VarianceAlertResponse: Decodable, Sendable { let success: Bool }

private struct PosVarianceEnvelope: Decodable, Sendable {
    let success: Bool
    let data: PosVarianceSettings?
}
