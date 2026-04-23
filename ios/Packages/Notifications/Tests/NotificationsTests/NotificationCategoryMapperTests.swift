import Testing
import Foundation
@testable import Notifications

@Suite("NotificationCategoryMapper")
struct NotificationCategoryMapperTests {

    // MARK: - typeFilter

    @Test("ticket type maps to .ticket filter")
    func ticketMapsToTicket() {
        #expect(NotificationCategoryMapper.typeFilter(for: "ticket.updated") == .ticket)
    }

    @Test("sms type maps to .sms filter")
    func smsMapsToSMS() {
        #expect(NotificationCategoryMapper.typeFilter(for: "sms.inbound") == .sms)
    }

    @Test("invoice type maps to .invoice filter")
    func invoiceMapsToInvoice() {
        #expect(NotificationCategoryMapper.typeFilter(for: "invoice.paid") == .invoice)
    }

    @Test("estimate type maps to .invoice filter bucket")
    func estimateMapsToInvoice() {
        #expect(NotificationCategoryMapper.typeFilter(for: "estimate.sent") == .invoice)
    }

    @Test("payment type maps to .payment filter")
    func paymentMapsToPayment() {
        #expect(NotificationCategoryMapper.typeFilter(for: "payment.received") == .payment)
    }

    @Test("refund type maps to .payment filter")
    func refundMapsToPayment() {
        #expect(NotificationCategoryMapper.typeFilter(for: "payment.refund") == .payment)
    }

    @Test("appointment type maps to .appointment filter")
    func appointmentMapsToAppointment() {
        #expect(NotificationCategoryMapper.typeFilter(for: "appointment.reminder.24h") == .appointment)
    }

    @Test("mention type maps to .mention filter")
    func mentionMapsToMention() {
        #expect(NotificationCategoryMapper.typeFilter(for: "mention.note") == .mention)
    }

    @Test("unknown type maps to .system filter")
    func unknownMapsToSystem() {
        #expect(NotificationCategoryMapper.typeFilter(for: "backup.complete") == .system)
    }

    @Test("nil type maps to .system filter")
    func nilMapsToSystem() {
        #expect(NotificationCategoryMapper.typeFilter(for: nil) == .system)
    }

    // MARK: - sectionLabel

    @Test("sectionLabel returns non-empty string for known type")
    func sectionLabelNonEmpty() {
        #expect(!NotificationCategoryMapper.sectionLabel(for: "ticket.updated").isEmpty)
    }

    @Test("sectionLabel for nil returns 'System'")
    func sectionLabelNilIsSystem() {
        #expect(NotificationCategoryMapper.sectionLabel(for: nil) == "System")
    }

    // MARK: - icon

    @Test("icon for ticket type returns wrench symbol")
    func ticketIcon() {
        #expect(NotificationCategoryMapper.icon(for: "ticket.updated") == "wrench.and.screwdriver")
    }

    @Test("icon for sms type returns message symbol")
    func smsIcon() {
        #expect(NotificationCategoryMapper.icon(for: "sms.inbound") == "message")
    }

    @Test("icon for nil returns bell symbol")
    func nilIcon() {
        #expect(NotificationCategoryMapper.icon(for: nil) == "bell")
    }

    @Test("icon for security returns lock.shield")
    func securityIcon() {
        #expect(NotificationCategoryMapper.icon(for: "security.alert") == "lock.shield")
    }

    // MARK: - isCritical

    @Test("security type is critical")
    func securityIsCritical() {
        #expect(NotificationCategoryMapper.isCritical(serverType: "security.event"))
    }

    @Test("ticket type is not critical")
    func ticketNotCritical() {
        #expect(!NotificationCategoryMapper.isCritical(serverType: "ticket.updated"))
    }

    @Test("nil type is not critical")
    func nilNotCritical() {
        #expect(!NotificationCategoryMapper.isCritical(serverType: nil))
    }
}
