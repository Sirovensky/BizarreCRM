import Foundation

#if os(iOS)
@preconcurrency import ActivityKit

public protocol LiveActivityPushTokenRegistering: Sendable {
    func registerLiveActivityPushToken(_ request: LiveActivityPushTokenRequest) async throws
}

// MARK: - Shift activity

/// Attributes describing a clock-in / clock-out shift Live Activity.
///
/// To start a Live Activity the main app's `Info.plist` must contain:
/// ```xml
/// <key>NSSupportsLiveActivities</key>
/// <true/>
/// ```
/// See `scripts/write-info-plist.sh` — add the key there; do NOT edit
/// `Info.plist` by hand (it is a generated build artifact).
public struct ShiftActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        /// Elapsed minutes since clocked in.
        public let elapsedMinutes: Int

        public init(elapsedMinutes: Int) {
            self.elapsedMinutes = elapsedMinutes
        }
    }

    public let employeeName: String
    public let clockedInAt: Date

    public init(employeeName: String, clockedInAt: Date) {
        self.employeeName = employeeName
        self.clockedInAt = clockedInAt
    }
}

// MARK: - Ticket in-progress activity (§24.3)

/// Workflow phase shown in the ticket Live Activity lock-screen layout.
public enum TicketPhase: String, Codable, Hashable, Sendable {
    case diagnosing   = "Diagnosing"
    case repairing    = "Repairing"
    case testing      = "Testing"
    case waitingParts = "Waiting for parts"
    case done         = "Done"
}

/// Attributes describing a ticket being actively worked on by a technician.
/// Started when tech taps "Start work"; ended when ticket marked Done.
public struct TicketInProgressAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        /// Elapsed minutes since "Start work" tapped.
        public let elapsedMinutes: Int
        /// Current repair phase shown in the lock-screen layout subtitle.
        public let phase: TicketPhase

        public init(elapsedMinutes: Int, phase: TicketPhase = .repairing) {
            self.elapsedMinutes = elapsedMinutes
            self.phase = phase
        }
    }

    public let ticketId: Int64
    /// Short alphanumeric order ID shown in the UI (e.g. "T-1042").
    public let orderId: String
    /// Customer display name; nil when ticket has no linked customer.
    public let customerName: String?
    /// First service description from the ticket's services list.
    public let service: String?

    public init(ticketId: Int64, orderId: String, customerName: String?, service: String?) {
        self.ticketId     = ticketId
        self.orderId      = orderId
        self.customerName = customerName
        self.service      = service
    }
}

// MARK: - POS sale activity

/// Attributes describing an in-progress POS sale Live Activity.
public struct POSSaleActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        /// Running cart total in cents.
        public let cartTotalCents: Int
        /// Number of line items in the cart.
        public let itemCount: Int
        /// Sale completion progress 0.0–1.0 (0 = cart building, 1 = payment complete).
        /// Used to drive a visual progress indicator in the lock-screen layout.
        public let progressPercent: Double

        public init(cartTotalCents: Int, itemCount: Int, progressPercent: Double = 0) {
            self.cartTotalCents = cartTotalCents
            self.itemCount = itemCount
            self.progressPercent = max(0, min(1, progressPercent))
        }
    }

    public let cashierName: String

    public init(cashierName: String) {
        self.cashierName = cashierName
    }
}

// MARK: - Coordinator

/// Manages Live Activity lifecycle for shift clock-in/out and POS sales.
///
/// - Requires `NSSupportsLiveActivities = true` in main app `Info.plist`
///   (add to `scripts/write-info-plist.sh`).
/// - App Group entitlement `group.com.bizarrecrm` must be present.
///
/// Usage (from `BizarreCRMApp` or a feature ViewModel):
/// ```swift
/// let coordinator = LiveActivityCoordinator()
/// try await coordinator.startShiftActivity(employeeName: "Alice", clockedInAt: .now)
/// // Later, on each minute tick:
/// try await coordinator.updateShiftActivity(durationMinutes: 65)
/// // On clock-out:
/// await coordinator.endShiftActivity()
/// ```
@MainActor
@Observable
public final class LiveActivityCoordinator {

    // MARK: - State

    @ObservationIgnored
    private var shiftActivity: Activity<ShiftActivityAttributes>?

    @ObservationIgnored
    private var saleActivity: Activity<POSSaleActivityAttributes>?

    @ObservationIgnored
    private var ticketActivity: Activity<TicketInProgressAttributes>?

    /// Whether a shift Live Activity is currently running.
    public private(set) var isShiftActive: Bool = false

    /// Whether a POS sale Live Activity is currently running.
    public private(set) var isSaleActive: Bool = false

    /// Whether a ticket-in-progress Live Activity is currently running.
    public private(set) var isTicketActive: Bool = false

    // MARK: - Init

    public init() {}

    // MARK: - Shift activity

    /// Start a clock-in Live Activity. No-ops if one is already running.
    /// - Parameters:
    ///   - employeeName: Employee display name shown on lock screen / Dynamic Island.
    ///   - clockedInAt: Exact time the shift started.
    public func startShiftActivity(employeeName: String, clockedInAt: Date) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard shiftActivity == nil else { return }

        let attrs = ShiftActivityAttributes(employeeName: employeeName, clockedInAt: clockedInAt)
        let initialState = ShiftActivityAttributes.ContentState(elapsedMinutes: 0)
        let content = ActivityContent(state: initialState, staleDate: nil)

        shiftActivity = try Activity<ShiftActivityAttributes>.request(
            attributes: attrs,
            content: content,
            pushType: nil
        )
        isShiftActive = true
    }

    /// Update elapsed minutes on the running shift activity.
    public func updateShiftActivity(durationMinutes: Int) async throws {
        guard let activity = shiftActivity else { return }
        let newState = ShiftActivityAttributes.ContentState(elapsedMinutes: durationMinutes)
        await Task { @MainActor in
            await activity.update(ActivityContent(state: newState, staleDate: nil))
        }.value
    }

    /// End the shift Live Activity.
    public func endShiftActivity() async {
        guard let activity = shiftActivity else { return }
        let finalState = ShiftActivityAttributes.ContentState(
            elapsedMinutes: activity.content.state.elapsedMinutes
        )
        await Task { @MainActor in
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .after(Date.now.addingTimeInterval(5))
            )
        }.value
        shiftActivity = nil
        isShiftActive = false
    }

    // MARK: - POS sale activity

    /// Start a POS sale Live Activity.
    /// - Parameters:
    ///   - cashierName: Name shown in the Dynamic Island.
    ///   - initialCartTotalCents: Starting cart total.
    ///   - itemCount: Number of items already in cart.
    ///   - progressPercent: Workflow progress 0.0–1.0 (default 0 = cart building).
    public func startSaleActivity(
        cashierName: String,
        initialCartTotalCents: Int,
        itemCount: Int,
        progressPercent: Double = 0
    ) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard saleActivity == nil else { return }

        let attrs = POSSaleActivityAttributes(cashierName: cashierName)
        let initialState = POSSaleActivityAttributes.ContentState(
            cartTotalCents: initialCartTotalCents,
            itemCount: itemCount,
            progressPercent: progressPercent
        )
        let content = ActivityContent(state: initialState, staleDate: nil)
        saleActivity = try Activity<POSSaleActivityAttributes>.request(
            attributes: attrs,
            content: content,
            pushType: nil
        )
        isSaleActive = true
    }

    /// Update cart total, item count, and sale-progress percent on the running sale Live Activity.
    /// - Parameter progressPercent: 0.0 (cart building) → 0.5 (payment pending) → 1.0 (complete).
    public func updateSaleActivity(
        cartTotalCents: Int,
        itemCount: Int,
        progressPercent: Double = 0
    ) async throws {
        guard let activity = saleActivity else { return }
        let newState = POSSaleActivityAttributes.ContentState(
            cartTotalCents: cartTotalCents,
            itemCount: itemCount,
            progressPercent: progressPercent
        )
        await Task { @MainActor in
            await activity.update(ActivityContent(state: newState, staleDate: nil))
        }.value
    }

    /// End the sale Live Activity.
    /// - Parameter completed: Pass `true` for a completed sale (shows "Sale complete" dismissal),
    ///   `false` for a cancelled transaction (shows "Sale cancelled" dismissal).
    public func endSaleActivity(completed: Bool = true) async {
        guard let activity = saleActivity else { return }
        // Drive progress to 1 on completion so the final lock-screen frame looks right.
        let finalState = POSSaleActivityAttributes.ContentState(
            cartTotalCents: activity.content.state.cartTotalCents,
            itemCount: activity.content.state.itemCount,
            progressPercent: completed ? 1.0 : activity.content.state.progressPercent
        )
        let dismissalPolicy: ActivityUIDismissalPolicy = completed
            ? .after(Date.now.addingTimeInterval(8))   // linger 8 s so cashier sees "Complete"
            : .immediate
        await Task { @MainActor in
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: dismissalPolicy
            )
        }.value
        saleActivity = nil
        isSaleActive = false
    }

    // MARK: - Ticket in-progress activity (§24.3)

    /// Start a "Ticket in progress" Live Activity. No-ops if one is already running.
    /// - Parameters:
    ///   - ticketId: Server-assigned ticket ID (for deep-link).
    ///   - orderId: Short order string shown in Dynamic Island compact view.
    ///   - customerName: Customer display name (may be nil).
    ///   - service: First service description (may be nil).
    public func startTicketActivity(
        ticketId: Int64,
        orderId: String,
        customerName: String?,
        service: String?
    ) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard ticketActivity == nil else { return }

        let attrs = TicketInProgressAttributes(
            ticketId: ticketId,
            orderId: orderId,
            customerName: customerName,
            service: service
        )
        let initialState = TicketInProgressAttributes.ContentState(
            elapsedMinutes: 0,
            phase: .diagnosing
        )
        let content = ActivityContent(state: initialState, staleDate: nil)

        ticketActivity = try Activity<TicketInProgressAttributes>.request(
            attributes: attrs,
            content: content,
            pushType: nil
        )
        isTicketActive = true
    }

    /// Update elapsed minutes and repair phase on the running ticket Live Activity.
    /// - Parameters:
    ///   - elapsedMinutes: Total minutes since "Start work".
    ///   - phase: Current workflow phase shown in the lock-screen subtitle.
    public func updateTicketActivity(elapsedMinutes: Int, phase: TicketPhase = .repairing) async throws {
        guard let activity = ticketActivity else { return }
        let newState = TicketInProgressAttributes.ContentState(
            elapsedMinutes: elapsedMinutes,
            phase: phase
        )
        await Task { @MainActor in
            await activity.update(ActivityContent(state: newState, staleDate: nil))
        }.value
    }

    /// End the ticket Live Activity (call when ticket marked Done or cancelled).
    /// - Parameter resolved: Pass `true` when the ticket was completed successfully.
    ///   The activity lingers 12 s showing "Ticket done" dismissal copy before auto-dismissing.
    public func endTicketActivity(resolved: Bool = true) async {
        guard let activity = ticketActivity else { return }
        let finalState = TicketInProgressAttributes.ContentState(
            elapsedMinutes: activity.content.state.elapsedMinutes,
            phase: resolved ? .done : activity.content.state.phase
        )
        let linger: TimeInterval = resolved ? 12 : 5
        await Task { @MainActor in
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .after(Date.now.addingTimeInterval(linger))
            )
        }.value
        ticketActivity = nil
        isTicketActive = false
    }
}

// MARK: - Push-to-update token registration (§24.3)

/// Service that requests a Live Activity with `pushType: .token` so the server can send
/// ActivityKit push updates directly (iOS 17.2+, avoids the 15-update/hour app-side rate limit).
///
/// Wire after `startTicketActivity` or `startSaleActivity`:
/// ```swift
/// let pushService = LiveActivityPushTokenService()
/// let token = try await pushService.requestTicketActivityToken(
///     coordinator: coordinator,
///     ticketId: ticket.id,
///     orderId: ticket.orderId,
///     customerName: ticket.customerName,
///     service: ticket.service,
///     api: apiClient
/// )
/// // token is sent to the server; server uses it to push ActivityKit updates.
/// ```
@available(iOS 17.2, *)
@MainActor
public final class LiveActivityPushTokenService {

    public init() {}

    // MARK: - Ticket push token

    /// Start a ticket Live Activity with `pushType: .token` and upload the push token to the server.
    ///
    /// - Returns: The hex push-token string (also uploaded to `POST /api/v1/live-activities/register`).
    @discardableResult
    public func startTicketActivityWithPushToken(
        ticketId: Int64,
        orderId: String,
        customerName: String?,
        service: String?,
        api: LiveActivityPushTokenRegistering
    ) async throws -> String {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw LiveActivityPushTokenError.activitiesDisabled
        }

        let attrs = TicketInProgressAttributes(
            ticketId: ticketId,
            orderId: orderId,
            customerName: customerName,
            service: service
        )
        let initialState = TicketInProgressAttributes.ContentState(
            elapsedMinutes: 0,
            phase: .diagnosing
        )
        let content = ActivityContent(state: initialState, staleDate: nil)

        let activity = try Activity<TicketInProgressAttributes>.request(
            attributes: attrs,
            content: content,
            pushType: .token
        )

        // Wait for the system to vend the first push token.
        var tokenHex: String?
        for await token in activity.pushTokenUpdates {
            tokenHex = token.map { String(format: "%02x", $0) }.joined()
            break
        }
        guard let hex = tokenHex else {
            throw LiveActivityPushTokenError.noTokenReceived
        }

        // Upload token to server so it can push ActivityKit content updates.
        try await registerPushToken(LiveActivityPushTokenRequest(
            activityId: activity.id,
            pushToken: hex,
            activityType: "ticket",
            referenceId: String(ticketId)
        ))

        return hex
    }

    // MARK: - Sale push token

    /// Start a POS sale Live Activity with `pushType: .token` and upload the push token.
    @discardableResult
    public func startSaleActivityWithPushToken(
        cashierName: String,
        initialCartTotalCents: Int,
        itemCount: Int,
        api: LiveActivityPushTokenRegistering
    ) async throws -> String {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw LiveActivityPushTokenError.activitiesDisabled
        }

        let attrs = POSSaleActivityAttributes(cashierName: cashierName)
        let initialState = POSSaleActivityAttributes.ContentState(
            cartTotalCents: initialCartTotalCents,
            itemCount: itemCount,
            progressPercent: 0
        )
        let content = ActivityContent(state: initialState, staleDate: nil)

        let activity = try Activity<POSSaleActivityAttributes>.request(
            attributes: attrs,
            content: content,
            pushType: .token
        )

        var tokenHex: String?
        for await token in activity.pushTokenUpdates {
            tokenHex = token.map { String(format: "%02x", $0) }.joined()
            break
        }
        guard let hex = tokenHex else {
            throw LiveActivityPushTokenError.noTokenReceived
        }

        try await registerPushToken(LiveActivityPushTokenRequest(
            activityId: activity.id,
            pushToken: hex,
            activityType: "sale",
            referenceId: nil
        ))

        return hex
    }
}

// MARK: - Error

public enum LiveActivityPushTokenError: Error, LocalizedError {
    case activitiesDisabled
    case noTokenReceived

    public var errorDescription: String? {
        switch self {
        case .activitiesDisabled:
            return "Live Activities are disabled on this device or by the user."
        case .noTokenReceived:
            return "The system did not vend an ActivityKit push token."
        }
    }
}

// MARK: - DTO

/// Request body for `POST /api/v1/live-activities/register`.
public struct LiveActivityPushTokenRequest: Encodable, Sendable {
    /// Unique identifier assigned by ActivityKit to this live activity instance.
    public let activityId: String
    /// Hex-encoded APNs push token for ActivityKit updates.
    public let pushToken: String
    /// Type discriminator: "ticket" or "sale".
    public let activityType: String
    /// Server-side entity ID the activity is bound to (ticket ID, etc.).
    public let referenceId: String?

    enum CodingKeys: String, CodingKey {
        case activityId   = "activity_id"
        case pushToken    = "push_token"
        case activityType = "activity_type"
        case referenceId  = "reference_id"
    }
}

#endif // os(iOS)
