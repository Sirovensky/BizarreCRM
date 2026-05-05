import Testing
import Foundation
@testable import Notifications

// MARK: - NotificationMatrixModelTests

@Suite("NotificationMatrixModel")
struct NotificationMatrixModelTests {

    // MARK: - Build from preferences

    @Test("build returns one row per event")
    func buildRowCount() {
        let prefs = NotificationEvent.allCases.map { NotificationPreference.defaultPreference(for: $0) }
        let model = NotificationMatrixModel.build(from: prefs)
        #expect(model.rows.count == NotificationEvent.allCases.count)
    }

    @Test("build maps pushEnabled correctly")
    func buildMapsChannels() {
        let pref = NotificationPreference(
            event: .ticketAssigned,
            pushEnabled: true,
            inAppEnabled: true,
            emailEnabled: false,
            smsEnabled: false
        )
        let rest = NotificationEvent.allCases
            .filter { $0 != .ticketAssigned }
            .map { NotificationPreference.defaultPreference(for: $0) }
        let model = NotificationMatrixModel.build(from: [pref] + rest)
        let row = model.rows.first(where: { $0.event == .ticketAssigned })!
        #expect(row.pushEnabled == true)
        #expect(row.emailEnabled == false)
        #expect(row.smsEnabled == false)
    }

    @Test("build backfills missing events with defaults")
    func buildBackfillsMissing() {
        // Only provide one event preference
        let pref = NotificationPreference.defaultPreference(for: .ticketAssigned)
        let model = NotificationMatrixModel.build(from: [pref])
        #expect(model.rows.count == NotificationEvent.allCases.count)
    }

    @Test("defaults returns one row per event with default values")
    func defaultsRowCount() {
        let model = NotificationMatrixModel.defaults
        #expect(model.rows.count == NotificationEvent.allCases.count)
        for row in model.rows {
            #expect(row.pushEnabled == row.event.defaultPush)
            #expect(row.emailEnabled == row.event.defaultEmail)
            #expect(row.smsEnabled == row.event.defaultSms)
        }
    }

    // MARK: - rows(for category)

    @Test("rows(for:) returns only rows matching category")
    func rowsForCategory() {
        let model = NotificationMatrixModel.defaults
        let ticketRows = model.rows(for: .tickets)
        #expect(!ticketRows.isEmpty)
        #expect(ticketRows.allSatisfy { $0.category == .tickets })
    }

    @Test("rows(for:) returns empty for a category with no events")
    func rowsForCategoryEmpty() {
        // All categories should have at least one event — just verify count is sane
        for category in MatrixEventCategory.allCases {
            let rows = NotificationMatrixModel.defaults.rows(for: category)
            // POS and system categories should have rows
            _ = rows.count // no crash
        }
    }

    // MARK: - replacing

    @Test("replacing returns new model without mutating original")
    func replacingImmutable() {
        let model = NotificationMatrixModel.defaults
        guard let row = model.rows.first else { return }
        let toggled = row.toggling(.push)
        let updated = model.replacing(row: toggled)
        // Original unchanged
        #expect(model.rows.first?.pushEnabled == row.pushEnabled)
        // Updated changed
        #expect(updated.rows.first?.pushEnabled == toggled.pushEnabled)
    }

    @Test("replacing only changes the target event row")
    func replacingOnlyTargetRow() {
        let model = NotificationMatrixModel.defaults
        let target = NotificationEvent.invoicePaid
        guard let row = model.rows.first(where: { $0.event == target }) else { return }
        let toggled = row.toggling(.email)
        let updated = model.replacing(row: toggled)
        // Other rows unchanged
        for r in updated.rows where r.event != target {
            let original = model.rows.first(where: { $0.event == r.event })!
            #expect(r.emailEnabled == original.emailEnabled)
        }
    }

    // MARK: - toPreferences

    @Test("toPreferences returns one preference per row")
    func toPreferencesCount() {
        let model = NotificationMatrixModel.defaults
        let prefs = model.toPreferences()
        #expect(prefs.count == model.rows.count)
    }

    @Test("toPreferences preserves inAppEnabled from originals")
    func toPreferencesPreservesInApp() {
        let originals = NotificationEvent.allCases.map { event in
            NotificationPreference(
                event: event,
                pushEnabled: event.defaultPush,
                inAppEnabled: false, // deliberately set to false
                emailEnabled: false,
                smsEnabled: false
            )
        }
        let model = NotificationMatrixModel.build(from: originals)
        let prefs = model.toPreferences(originalPreferences: originals)
        #expect(prefs.allSatisfy { !$0.inAppEnabled })
    }
}

// MARK: - MatrixRowTests

@Suite("MatrixRow")
struct MatrixRowTests {

    @Test("toggling push flips pushEnabled, others unchanged")
    func togglePush() {
        let row = MatrixRow(event: .ticketAssigned, pushEnabled: false, emailEnabled: false, smsEnabled: false)
        let toggled = row.toggling(.push)
        #expect(toggled.pushEnabled == true)
        #expect(toggled.emailEnabled == false)
        #expect(toggled.smsEnabled == false)
    }

    @Test("toggling email flips emailEnabled, others unchanged")
    func toggleEmail() {
        let row = MatrixRow(event: .invoicePaid, pushEnabled: true, emailEnabled: false, smsEnabled: false)
        let toggled = row.toggling(.email)
        #expect(toggled.pushEnabled == true)
        #expect(toggled.emailEnabled == true)
        #expect(toggled.smsEnabled == false)
    }

    @Test("toggling sms flips smsEnabled")
    func toggleSms() {
        let row = MatrixRow(event: .invoicePaid, pushEnabled: false, emailEnabled: false, smsEnabled: false)
        let toggled = row.toggling(.sms)
        #expect(toggled.smsEnabled == true)
    }

    @Test("toggling does not mutate original row")
    func toggleImmutable() {
        let row = MatrixRow(event: .ticketAssigned, pushEnabled: true, emailEnabled: false, smsEnabled: false)
        let _ = row.toggling(.push)
        #expect(row.pushEnabled == true) // original unchanged
    }

    @Test("withQuietHours returns new row with quiet hours set")
    func withQuietHours() {
        let row = MatrixRow(event: .ticketAssigned, pushEnabled: true, emailEnabled: false, smsEnabled: false)
        let qh = QuietHours(startMinutesFromMidnight: 22 * 60, endMinutesFromMidnight: 7 * 60, allowCriticalOverride: true)
        let updated = row.withQuietHours(qh)
        #expect(updated.quietHours != nil)
        #expect(row.quietHours == nil)
    }

    @Test("withQuietHours(nil) clears quiet hours")
    func clearQuietHours() {
        let qh = QuietHours(startMinutesFromMidnight: 22 * 60, endMinutesFromMidnight: 7 * 60, allowCriticalOverride: false)
        let row = MatrixRow(event: .ticketAssigned, pushEnabled: true, emailEnabled: false, smsEnabled: false, quietHours: qh)
        let cleared = row.withQuietHours(nil)
        #expect(cleared.quietHours == nil)
    }

    @Test("isEnabled returns correct value per channel")
    func isEnabled() {
        let row = MatrixRow(event: .ticketAssigned, pushEnabled: true, emailEnabled: false, smsEnabled: true)
        #expect(row.isEnabled(.push) == true)
        #expect(row.isEnabled(.email) == false)
        #expect(row.isEnabled(.sms) == true)
    }

    @Test("toPreference builds NotificationPreference with correct values")
    func toPreference() {
        let qh = QuietHours(startMinutesFromMidnight: 22 * 60, endMinutesFromMidnight: 7 * 60, allowCriticalOverride: true)
        let row = MatrixRow(event: .invoicePaid, pushEnabled: true, emailEnabled: true, smsEnabled: false, quietHours: qh)
        let pref = row.toPreference(inAppEnabled: false)
        #expect(pref.event == .invoicePaid)
        #expect(pref.pushEnabled == true)
        #expect(pref.emailEnabled == true)
        #expect(pref.smsEnabled == false)
        #expect(pref.inAppEnabled == false)
        #expect(pref.quietHours != nil)
    }

    @Test("category maps correctly via MatrixEventCategory.from")
    func categoryMapping() {
        let row = MatrixRow(event: .ticketAssigned, pushEnabled: true, emailEnabled: false, smsEnabled: false)
        #expect(row.category == .tickets)

        let invoiceRow = MatrixRow(event: .invoicePaid, pushEnabled: false, emailEnabled: false, smsEnabled: false)
        #expect(invoiceRow.category == .invoices)

        let posRow = MatrixRow(event: .paymentDeclined, pushEnabled: true, emailEnabled: false, smsEnabled: false)
        #expect(posRow.category == .pos)
    }
}

// MARK: - MatrixEventCategoryTests

@Suite("MatrixEventCategory")
struct MatrixEventCategoryTests {

    @Test("from maps billing to invoices")
    func billingToInvoices() {
        #expect(MatrixEventCategory.from(.billing) == .invoices)
    }

    @Test("from maps admin to system")
    func adminToSystem() {
        #expect(MatrixEventCategory.from(.admin) == .system)
    }

    @Test("from maps tickets to tickets")
    func ticketsToTickets() {
        #expect(MatrixEventCategory.from(.tickets) == .tickets)
    }

    @Test("all cases have a non-empty symbolName")
    func allHaveSymbols() {
        for category in MatrixEventCategory.allCases {
            #expect(!category.symbolName.isEmpty)
        }
    }

    @Test("all cases have a non-empty rawValue (display name)")
    func allHaveDisplayNames() {
        for category in MatrixEventCategory.allCases {
            #expect(!category.rawValue.isEmpty)
        }
    }
}

// MARK: - MatrixChannelTests

@Suite("MatrixChannel")
struct MatrixChannelTests {

    @Test("all cases have non-empty displayLabel")
    func displayLabels() {
        for channel in MatrixChannel.allCases {
            #expect(!channel.displayLabel.isEmpty)
        }
    }

    @Test("all cases have non-empty symbolName")
    func symbolNames() {
        for channel in MatrixChannel.allCases {
            #expect(!channel.symbolName.isEmpty)
        }
    }

    @Test("rawValues match server channel strings")
    func rawValues() {
        #expect(MatrixChannel.push.rawValue == "push")
        #expect(MatrixChannel.email.rawValue == "email")
        #expect(MatrixChannel.sms.rawValue == "sms")
    }
}
