import Testing
import Foundation
@testable import Notifications

@Suite("NotificationFilterChip")
struct NotificationFilterChipTests {

    // MARK: - Identity

    @Test("Each chip has a unique non-empty id")
    func allChipsUniqueIds() {
        let all: [NotificationFilterChip] = [.all, .unread] + NotificationFilterChip.typeChips
        let ids = all.map { $0.id }
        let unique = Set(ids)
        #expect(unique.count == all.count, "Expected all chip IDs to be unique")
        for id in ids {
            #expect(!id.isEmpty, "chip id must not be empty")
        }
    }

    @Test("Each chip has a non-empty label")
    func allChipsHaveLabels() {
        let all: [NotificationFilterChip] = [.all, .unread] + NotificationFilterChip.typeChips
        for chip in all {
            #expect(!chip.label.isEmpty, "chip.label must not be empty for \(chip.id)")
        }
    }

    // MARK: - Equality

    @Test(".all chips are equal")
    func allChipsEquality() {
        #expect(NotificationFilterChip.all == NotificationFilterChip.all)
    }

    @Test(".unread chips are equal")
    func unreadChipsEquality() {
        #expect(NotificationFilterChip.unread == NotificationFilterChip.unread)
    }

    @Test("byType chips equal when same type")
    func byTypeChipsEquality() {
        #expect(NotificationFilterChip.byType(.ticket) == NotificationFilterChip.byType(.ticket))
    }

    @Test("byType chips not equal when different types")
    func byTypeChipsInequality() {
        #expect(NotificationFilterChip.byType(.ticket) != NotificationFilterChip.byType(.sms))
    }
}

@Suite("NotificationTypeFilter")
struct NotificationTypeFilterTests {

    @Test("ticket filter matches 'ticket.updated'")
    func ticketMatches() {
        #expect(NotificationTypeFilter.ticket.matches("ticket.updated"))
    }

    @Test("sms filter matches 'sms.inbound'")
    func smsMatches() {
        #expect(NotificationTypeFilter.sms.matches("sms.inbound"))
    }

    @Test("invoice filter matches 'invoice.paid'")
    func invoiceMatches() {
        #expect(NotificationTypeFilter.invoice.matches("invoice.paid"))
    }

    @Test("invoice filter matches 'estimate.sent'")
    func estimateMatchesInvoice() {
        #expect(NotificationTypeFilter.invoice.matches("estimate.sent"))
    }

    @Test("payment filter matches 'payment.received'")
    func paymentMatches() {
        #expect(NotificationTypeFilter.payment.matches("payment.received"))
    }

    @Test("payment filter matches 'payment.refund'")
    func refundMatchesPayment() {
        #expect(NotificationTypeFilter.payment.matches("payment.refund"))
    }

    @Test("appointment filter matches 'appointment.reminder.24h'")
    func appointmentMatches() {
        #expect(NotificationTypeFilter.appointment.matches("appointment.reminder.24h"))
    }

    @Test("mention filter matches 'mention.note'")
    func mentionMatches() {
        #expect(NotificationTypeFilter.mention.matches("mention.note"))
    }

    @Test("system filter matches unknown type")
    func systemMatchesUnknown() {
        #expect(NotificationTypeFilter.system.matches("backup.completed"))
    }

    @Test("ticket filter does not match 'sms.inbound'")
    func ticketDoesNotMatchSMS() {
        #expect(!NotificationTypeFilter.ticket.matches("sms.inbound"))
    }

    @Test("nil type matches system filter")
    func nilTypeMatchesSystem() {
        #expect(NotificationTypeFilter.system.matches(nil))
    }

    @Test("nil type does not match ticket filter")
    func nilTypeDoesNotMatchTicket() {
        #expect(!NotificationTypeFilter.ticket.matches(nil))
    }

    @Test("All filter cases have non-empty displayName")
    func allCasesHaveDisplayName() {
        for filter in NotificationTypeFilter.allCases {
            #expect(!filter.displayName.isEmpty)
        }
    }
}
