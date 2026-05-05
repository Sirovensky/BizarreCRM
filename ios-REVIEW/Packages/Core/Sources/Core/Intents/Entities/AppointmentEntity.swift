import AppIntents
import Foundation
#if os(iOS)

/// AppEntity for an appointment, exposed to Shortcuts + Siri.
@available(iOS 16, *)
public struct AppointmentEntity: AppEntity, Sendable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Appointment")
    public static let defaultQuery = AppointmentEntityQuery()

    public let id: String
    /// Numeric database id, preserved separately for API calls.
    public let numericId: Int64
    public let customerName: String
    public let scheduledAt: Date
    public let serviceName: String?

    public var displayRepresentation: DisplayRepresentation {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .short
        let dateStr = formatter.string(from: scheduledAt)
        return DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: customerName),
            subtitle: LocalizedStringResource(
                stringLiteral: "\(dateStr)\(serviceName.map { " · \($0)" } ?? "")"
            )
        )
    }

    public init(
        id: Int64,
        customerName: String,
        scheduledAt: Date,
        serviceName: String? = nil
    ) {
        self.id = String(id)
        self.numericId = id
        self.customerName = customerName
        self.scheduledAt = scheduledAt
        self.serviceName = serviceName
    }
}
#endif // os(iOS)
