import Testing
import Foundation
@testable import KioskMode
import Core

// MARK: - KioskQueueBoard tests

@Suite("KioskQueueBoard §22")
@MainActor
struct KioskQueueBoardTests {

    // MARK: - Helpers

    private func makeEntry(
        id: Int64 = 1,
        displayId: String = "TK-0001",
        firstName: String = "Alice",
        device: String? = "iPhone 15",
        status: TicketStatus = .inProgress
    ) -> KioskQueueEntry {
        KioskQueueEntry(
            id: id,
            displayId: displayId,
            customerFirstName: firstName,
            deviceSummary: device,
            status: status,
            updatedAt: Date()
        )
    }

    private func makeTicket(
        id: Int64 = 1,
        customerName: String = "Alice Smith",
        status: TicketStatus = .inProgress
    ) -> Ticket {
        Ticket(
            id: id,
            displayId: "TK-000\(id)",
            customerId: 100,
            customerName: customerName,
            status: status,
            deviceSummary: "MacBook Pro",
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    // MARK: - KioskQueueEntry init

    @Test("KioskQueueEntry stores display ID correctly")
    func entryStoresDisplayId() {
        let entry = makeEntry(displayId: "TK-0042")
        #expect(entry.displayId == "TK-0042")
    }

    @Test("KioskQueueEntry stores customer first name correctly")
    func entryStoresFirstName() {
        let entry = makeEntry(firstName: "Bob")
        #expect(entry.customerFirstName == "Bob")
    }

    @Test("KioskQueueEntry stores status correctly")
    func entryStoresStatus() {
        let entry = makeEntry(status: .ready)
        #expect(entry.status == .ready)
    }

    @Test("KioskQueueEntry stores optional device summary")
    func entryStoresDeviceSummary() {
        let entry = makeEntry(device: "iPad Pro")
        #expect(entry.deviceSummary == "iPad Pro")
    }

    @Test("KioskQueueEntry allows nil device summary")
    func entryNilDeviceSummary() {
        let entry = makeEntry(device: nil)
        #expect(entry.deviceSummary == nil)
    }

    // MARK: - KioskQueueEntry from Ticket

    @Test("Init from Ticket strips surname to first name only")
    func ticketInitStripsLastName() {
        let ticket = makeTicket(customerName: "Alice Smith")
        let entry = KioskQueueEntry(ticket: ticket)
        #expect(entry.customerFirstName == "Alice")
    }

    @Test("Init from Ticket preserves single-word name unchanged")
    func ticketInitSingleName() {
        let ticket = makeTicket(customerName: "Madonna")
        let entry = KioskQueueEntry(ticket: ticket)
        #expect(entry.customerFirstName == "Madonna")
    }

    @Test("Init from Ticket copies displayId")
    func ticketInitCopiesDisplayId() {
        let ticket = makeTicket(id: 42)
        let entry = KioskQueueEntry(ticket: ticket)
        #expect(entry.displayId == ticket.displayId)
    }

    @Test("Init from Ticket copies status")
    func ticketInitCopiesStatus() {
        let ticket = makeTicket(status: .ready)
        let entry = KioskQueueEntry(ticket: ticket)
        #expect(entry.status == .ready)
    }

    @Test("Init from Ticket copies id")
    func ticketInitCopiesId() {
        let ticket = makeTicket(id: 99)
        let entry = KioskQueueEntry(ticket: ticket)
        #expect(entry.id == 99)
    }

    // MARK: - KioskQueueBoardConfig defaults

    @Test("Default config header title is 'Service Queue'")
    func defaultHeaderTitle() {
        let config = KioskQueueBoardConfig()
        #expect(config.headerTitle == "Service Queue")
    }

    @Test("Default config ready statuses include .ready")
    func defaultReadyStatusIncludesReady() {
        let config = KioskQueueBoardConfig()
        #expect(config.readyStatuses.contains(.ready))
    }

    @Test("Default config max visible entries is 12")
    func defaultMaxVisibleEntries() {
        let config = KioskQueueBoardConfig()
        #expect(config.maxVisibleEntries == 12)
    }

    @Test("Custom ready statuses stored correctly")
    func customReadyStatuses() {
        let config = KioskQueueBoardConfig(readyStatuses: [.ready, .completed])
        #expect(config.readyStatuses.contains(.completed))
        #expect(config.readyStatuses.contains(.ready))
    }

    @Test("Custom max visible entries stored correctly")
    func customMaxEntries() {
        let config = KioskQueueBoardConfig(maxVisibleEntries: 8)
        #expect(config.maxVisibleEntries == 8)
    }

    // MARK: - KioskQueueBoardConfig Equatable

    @Test("Identical configs are equal")
    func identicalConfigsEqual() {
        let a = KioskQueueBoardConfig(
            headerTitle: "Q", readyStatuses: [.ready], maxVisibleEntries: 10
        )
        let b = KioskQueueBoardConfig(
            headerTitle: "Q", readyStatuses: [.ready], maxVisibleEntries: 10
        )
        #expect(a == b)
    }

    @Test("Configs with different header titles are not equal")
    func differentHeadersNotEqual() {
        let a = KioskQueueBoardConfig(headerTitle: "A")
        let b = KioskQueueBoardConfig(headerTitle: "B")
        #expect(a != b)
    }

    @Test("Configs with different max entries are not equal")
    func differentMaxEntriesNotEqual() {
        let a = KioskQueueBoardConfig(maxVisibleEntries: 5)
        let b = KioskQueueBoardConfig(maxVisibleEntries: 10)
        #expect(a != b)
    }

    // MARK: - KioskQueueEntry Equatable / Identifiable

    @Test("Two entries with same id are equal")
    func entriesWithSameIdEqual() {
        let a = makeEntry(id: 7)
        let b = makeEntry(id: 7)
        #expect(a == b)
    }

    @Test("Two entries with different ids are not equal")
    func entriesWithDifferentIdsNotEqual() {
        let a = makeEntry(id: 1)
        let b = makeEntry(id: 2)
        #expect(a != b)
    }

    @Test("Entry id matches Identifiable id")
    func entryIdMatchesIdentifiableId() {
        let entry = makeEntry(id: 55)
        #expect(entry.id == 55)
    }
}
