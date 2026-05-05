import AppIntents
import Foundation
#if os(iOS)

/// Reads the next appointment from the App Group shared store and speaks it via Siri.
@available(iOS 16, *)
public struct NextAppointmentIntent: AppIntent {
    public static let title: LocalizedStringResource = "Next Appointment"
    public static let description = IntentDescription("Tell me my next appointment.")

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<AppointmentEntity?> & ProvidesDialog {
        let appointment = try await AppointmentEntityQueryRegistry.repo.nextAppointment()
        guard let appt = appointment else {
            return .result(
                value: nil,
                dialog: IntentDialog("You have no upcoming appointments.")
            )
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let dateStr = formatter.string(from: appt.scheduledAt)
        let service = appt.serviceName.map { " for \($0)" } ?? ""
        return .result(
            value: appt,
            dialog: IntentDialog(
                "Your next appointment is with \(appt.customerName)\(service) at \(dateStr)."
            )
        )
    }
}
#endif // os(iOS)
