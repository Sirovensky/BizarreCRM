import Foundation

#if os(iOS)
@preconcurrency import ActivityKit

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

/// Attributes describing a ticket being actively worked on by a technician.
/// Started when tech taps "Start work"; ended when ticket marked Done.
public struct TicketInProgressAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        /// Elapsed minutes since "Start work" tapped.
        public let elapsedMinutes: Int

        public init(elapsedMinutes: Int) {
            self.elapsedMinutes = elapsedMinutes
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

        public init(cartTotalCents: Int, itemCount: Int) {
            self.cartTotalCents = cartTotalCents
            self.itemCount = itemCount
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
    public func startSaleActivity(
        cashierName: String,
        initialCartTotalCents: Int,
        itemCount: Int
    ) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard saleActivity == nil else { return }

        let attrs = POSSaleActivityAttributes(cashierName: cashierName)
        let initialState = POSSaleActivityAttributes.ContentState(
            cartTotalCents: initialCartTotalCents,
            itemCount: itemCount
        )
        let content = ActivityContent(state: initialState, staleDate: nil)
        saleActivity = try Activity<POSSaleActivityAttributes>.request(
            attributes: attrs,
            content: content,
            pushType: nil
        )
        isSaleActive = true
    }

    /// Update cart total and item count on the running sale Live Activity.
    public func updateSaleActivity(cartTotalCents: Int, itemCount: Int) async throws {
        guard let activity = saleActivity else { return }
        let newState = POSSaleActivityAttributes.ContentState(
            cartTotalCents: cartTotalCents,
            itemCount: itemCount
        )
        await Task { @MainActor in
            await activity.update(ActivityContent(state: newState, staleDate: nil))
        }.value
    }

    /// End the sale Live Activity (call on sale finalize or cancel).
    public func endSaleActivity() async {
        guard let activity = saleActivity else { return }
        let finalState = activity.content.state
        await Task { @MainActor in
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
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
        let initialState = TicketInProgressAttributes.ContentState(elapsedMinutes: 0)
        let content = ActivityContent(state: initialState, staleDate: nil)

        ticketActivity = try Activity<TicketInProgressAttributes>.request(
            attributes: attrs,
            content: content,
            pushType: nil
        )
        isTicketActive = true
    }

    /// Update elapsed minutes on the running ticket Live Activity.
    public func updateTicketActivity(elapsedMinutes: Int) async throws {
        guard let activity = ticketActivity else { return }
        let newState = TicketInProgressAttributes.ContentState(elapsedMinutes: elapsedMinutes)
        await Task { @MainActor in
            await activity.update(ActivityContent(state: newState, staleDate: nil))
        }.value
    }

    /// End the ticket Live Activity (call when ticket marked Done or cancelled).
    public func endTicketActivity() async {
        guard let activity = ticketActivity else { return }
        let finalState = activity.content.state
        await Task { @MainActor in
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .after(Date.now.addingTimeInterval(10))
            )
        }.value
        ticketActivity = nil
        isTicketActive = false
    }
}

#endif // os(iOS)
