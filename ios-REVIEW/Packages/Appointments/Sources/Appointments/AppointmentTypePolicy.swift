import Foundation
import Networking

// MARK: - §10 Appointment types — per-type default duration + resource requirement

/// Defines the business policy for each appointment type:
/// default duration, required resource category, and buffer time.
public struct AppointmentTypePolicy: Sendable, Identifiable, Hashable {
    public let id: String  // matches AppointmentServiceType.rawValue / server "appointment_type"
    public let displayName: String
    public let systemImage: String
    /// Default duration in seconds for this type.
    public let defaultDurationSeconds: TimeInterval
    /// Resource categories required for this appointment type.
    public let requiredResources: [String]
    /// Buffer time after appointment (in seconds) before next can start.
    public let bufferSeconds: TimeInterval

    public init(
        id: String,
        displayName: String,
        systemImage: String,
        defaultDurationSeconds: TimeInterval,
        requiredResources: [String] = [],
        bufferSeconds: TimeInterval = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.systemImage = systemImage
        self.defaultDurationSeconds = defaultDurationSeconds
        self.requiredResources = requiredResources
        self.bufferSeconds = bufferSeconds
    }

    public var defaultDurationMinutes: Int {
        Int(defaultDurationSeconds / 60)
    }

    public var resourceSummary: String {
        requiredResources.isEmpty ? "No specific resource" : requiredResources.joined(separator: ", ")
    }
}

// MARK: - Default policies

public extension AppointmentTypePolicy {

    /// Canonical default type policies — override from tenant settings when available.
    static let defaults: [AppointmentTypePolicy] = [
        AppointmentTypePolicy(
            id: "Drop-off",
            displayName: "Drop-off",
            systemImage: "shippingbox",
            defaultDurationSeconds: 15 * 60,    // 15 min intake
            requiredResources: [],
            bufferSeconds: 5 * 60
        ),
        AppointmentTypePolicy(
            id: "Pickup",
            displayName: "Pickup",
            systemImage: "hand.raised.fill",
            defaultDurationSeconds: 15 * 60,
            requiredResources: [],
            bufferSeconds: 5 * 60
        ),
        AppointmentTypePolicy(
            id: "Consultation",
            displayName: "Consultation",
            systemImage: "person.2.wave.2",
            defaultDurationSeconds: 30 * 60,    // 30 min
            requiredResources: ["tech"],
            bufferSeconds: 10 * 60
        ),
        AppointmentTypePolicy(
            id: "On-site",
            displayName: "On-site Visit",
            systemImage: "mappin.and.ellipse",
            defaultDurationSeconds: 90 * 60,    // 90 min travel + work
            requiredResources: ["tech"],
            bufferSeconds: 30 * 60
        ),
        AppointmentTypePolicy(
            id: "Delivery",
            displayName: "Delivery",
            systemImage: "truck.box",
            defaultDurationSeconds: 30 * 60,
            requiredResources: ["driver"],
            bufferSeconds: 15 * 60
        )
    ]

    /// Look up policy by appointment type string (case-insensitive).
    static func policy(for type: String) -> AppointmentTypePolicy {
        defaults.first { $0.id.lowercased() == type.lowercased() }
            ?? AppointmentTypePolicy(
                id: type,
                displayName: type.capitalized,
                systemImage: "calendar",
                defaultDurationSeconds: 60 * 60,
                requiredResources: [],
                bufferSeconds: 0
            )
    }
}

// MARK: - §10 No-show tracking per customer

/// Tracks no-show occurrences per customer.
/// When count reaches `tenant.noShowDepositThreshold`, deposit is required for next booking.
public struct CustomerNoShowRecord: Sendable, Codable {
    /// Customer identifier.
    public let customerId: Int64
    /// Total confirmed no-shows.
    public let noShowCount: Int
    /// Date of most recent no-show.
    public let lastNoShowAt: Date?
    /// Whether deposit is currently required per tenant policy.
    public let depositRequired: Bool

    public init(
        customerId: Int64,
        noShowCount: Int,
        lastNoShowAt: Date?,
        depositRequired: Bool
    ) {
        self.customerId = customerId
        self.noShowCount = noShowCount
        self.lastNoShowAt = lastNoShowAt
        self.depositRequired = depositRequired
    }

    enum CodingKeys: String, CodingKey {
        case customerId      = "customer_id"
        case noShowCount     = "no_show_count"
        case lastNoShowAt    = "last_no_show_at"
        case depositRequired = "deposit_required"
    }
}

// MARK: - No-show policy

/// Tenant-configurable no-show deposit policy.
/// After `thresholdCount` no-shows, `depositCents` is required on next booking.
public struct NoShowDepositPolicy: Sendable, Codable, Hashable {
    public let thresholdCount: Int
    public let depositCents: Int
    public let resetAfterDays: Int?

    public init(thresholdCount: Int = 2, depositCents: Int = 5000, resetAfterDays: Int? = 365) {
        self.thresholdCount = thresholdCount
        self.depositCents = depositCents
        self.resetAfterDays = resetAfterDays
    }

    public var depositFormatted: String {
        let amount = Double(depositCents) / 100.0
        return String(format: "$%.2f", amount)
    }

    enum CodingKeys: String, CodingKey {
        case thresholdCount  = "threshold_count"
        case depositCents    = "deposit_cents"
        case resetAfterDays  = "reset_after_days"
    }
}

// MARK: - APIClient extension

public extension APIClient {
    /// GET /api/v1/appointments/no-show-record?customer_id=:id
    func customerNoShowRecord(customerId: Int64) async throws -> CustomerNoShowRecord {
        let q = [URLQueryItem(name: "customer_id", value: String(customerId))]
        return try await get("/api/v1/appointments/no-show-record", query: q, as: CustomerNoShowRecord.self)
    }

    /// GET /api/v1/settings/no-show-policy
    func noShowDepositPolicy() async throws -> NoShowDepositPolicy {
        try await get("/api/v1/settings/no-show-policy", as: NoShowDepositPolicy.self)
    }

    /// PATCH /api/v1/settings/no-show-policy
    @discardableResult
    func updateNoShowPolicy(_ policy: NoShowDepositPolicy) async throws -> NoShowDepositPolicy {
        try await patch("/api/v1/settings/no-show-policy", body: policy, as: NoShowDepositPolicy.self)
    }
}
