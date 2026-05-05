import Foundation
import Observation
import Core
import Networking

// §7.8 Recurring Invoice Editor ViewModel — no UIKit dependency; fully testable.

@MainActor
@Observable
public final class RecurringInvoiceEditorViewModel {
    public var customerId: Int64?
    public var templateInvoiceId: Int64?
    /// §7.11 Display name of the picked template; kept in sync by RecurringInvoiceEditorSheet.
    public var selectedTemplateName: String?
    public var frequency: RecurringFrequency = .monthly
    public var dayOfMonth: Int = 1
    public var startDate: Date = .now
    public var endDate: Date?
    public var hasEndDate: Bool = false
    public var autoSend: Bool = false
    public var name: String = ""

    public var isSubmitting: Bool = false
    public var errorMessage: String?
    public var didSave: Bool = false

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored public let existingRuleId: Int64?

    public init(api: APIClient, rule: RecurringInvoiceRule? = nil) {
        self.api = api
        self.existingRuleId = rule?.id
        if let r = rule {
            customerId = r.customerId
            templateInvoiceId = r.templateInvoiceId
            frequency = r.frequency
            dayOfMonth = r.dayOfMonth
            startDate = r.startDate
            endDate = r.endDate
            hasEndDate = r.endDate != nil
            autoSend = r.autoSend
            name = r.name ?? ""
        }
    }

    public var isValid: Bool {
        customerId != nil && templateInvoiceId != nil && dayOfMonth >= 1 && dayOfMonth <= 28
    }

    public func save() async {
        guard isValid, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let ymd = DateFormatter.yyyyMMdd
        let req = CreateRecurringRuleRequest(
            customerId: customerId!,
            templateInvoiceId: templateInvoiceId!,
            frequency: frequency,
            dayOfMonth: dayOfMonth,
            startDate: ymd.string(from: startDate),
            endDate: hasEndDate ? endDate.map { ymd.string(from: $0) } : nil,
            autoSend: autoSend,
            name: name.isEmpty ? nil : name
        )

        do {
            if let existingId = existingRuleId {
                _ = try await api.updateRecurringRule(id: existingId, req)
            } else {
                _ = try await api.createRecurringRule(req)
            }
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
