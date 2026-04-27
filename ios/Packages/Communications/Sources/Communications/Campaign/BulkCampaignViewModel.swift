import Foundation
import Observation
import Networking
import Core

// MARK: - BulkCampaignViewModel

/// §12.12 — Compose + send a bulk SMS campaign to a customer segment.
///
/// Flow:
///   1. Compose: choose segment, write body, set optional schedule.
///   2. Preview: fetch TCPA-safe recipient count from server.
///   3. Confirm + send.
@MainActor
@Observable
public final class BulkCampaignViewModel {

    // MARK: - State

    public enum Step: Equatable, Sendable {
        case compose
        case previewing
        case confirmSend(BulkCampaignPreview)
        case sending
        case done(BulkCampaignAck)
        case failed(String)
    }

    public private(set) var step: Step = .compose

    // MARK: - Compose fields

    public var selectedSegment: BulkCampaignSegment = .all
    public var customCustomerIds: [Int64] = []
    public var body: String = ""
    public var scheduledDate: Date? = nil
    public var isScheduled: Bool = false

    // MARK: - Derived

    public var charCount: Int { body.count }

    public var smsSegments: Int { max(1, Int(ceil(Double(charCount) / 160.0))) }

    public var isBodyValid: Bool { !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    public var segmentKey: String { selectedSegment.rawValue }

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient

    // MARK: - Init

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Public interface

    /// Fetch TCPA-safe preview from server.
    public func preview() async {
        guard isBodyValid else {
            step = .failed("Write a message before previewing.")
            return
        }
        step = .previewing
        do {
            let preview = try await api.previewBulkCampaign(
                segmentKey: segmentKey,
                body: body
            )
            step = .confirmSend(preview)
        } catch {
            AppLog.ui.error("BulkCampaign preview failed: \(error.localizedDescription, privacy: .public)")
            step = .failed(error.localizedDescription)
        }
    }

    /// Send after user confirms on the preview screen.
    public func send() async {
        step = .sending
        let isoAt: String? = {
            guard isScheduled, let d = scheduledDate else { return nil }
            return ISO8601DateFormatter().string(from: d)
        }()
        let request = BulkCampaignRequest(
            body: body,
            segmentKey: segmentKey,
            customerIds: selectedSegment == .custom ? customCustomerIds : nil,
            scheduledAt: isoAt
        )
        do {
            let ack = try await api.sendBulkCampaign(request)
            step = .done(ack)
        } catch {
            AppLog.ui.error("BulkCampaign send failed: \(error.localizedDescription, privacy: .public)")
            step = .failed(error.localizedDescription)
        }
    }

    public func restart() {
        step = .compose
        body = ""
        selectedSegment = .all
        customCustomerIds = []
        scheduledDate = nil
        isScheduled = false
    }
}
