import Testing
import Foundation
@testable import Tickets
@testable import Networking

// MARK: - Inspector-specific stub APIClient

/// Minimal stub satisfying APIClient, covering only the three methods the
/// inspector VM calls. Any other call throws, surfacing unexpected usage.
private actor InspectorStubAPIClient: APIClient {

    // Configurable outcomes
    var statusListResult: Result<[TicketStatusRow], Error> = .success([])
    var changeStatusResult: Result<CreatedResource, Error> = .success(CreatedResource(id: 1))
    var updateTicketResult: Result<CreatedResource, Error> = .success(CreatedResource(id: 1))

    // Recorded calls (for assertion)
    private(set) var changeStatusCalls: [(ticketId: Int64, statusId: Int64)] = []
    private(set) var updateTicketCalls: [(id: Int64, assignedTo: Int64?)] = []

    // MARK: — Protocol requirements

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        // Serves listTicketStatuses (GET /api/v1/settings/statuses)
        if path == "/api/v1/settings/statuses" {
            switch statusListResult {
            case .success(let rows):
                guard let cast = rows as? T else { throw APITransportError.decoding("type mismatch") }
                return cast
            case .failure(let e):
                throw e
            }
        }
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        // Serves updateTicket (PUT /api/v1/tickets/:id)
        guard path.hasPrefix("/api/v1/tickets/") else { throw APITransportError.noBaseURL }
        if let req = body as? UpdateTicketRequest {
            let id = Int64(path.split(separator: "/").last ?? "0") ?? 0
            updateTicketCalls.append((id: id, assignedTo: req.assignedTo))
        }
        switch updateTicketResult {
        case .success(let r):
            guard let cast = r as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        case .failure(let e):
            throw e
        }
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        // Serves changeTicketStatus (PATCH /api/v1/tickets/:id/status)
        guard path.contains("/tickets/") && path.hasSuffix("/status") else {
            throw APITransportError.noBaseURL
        }
        // Parse ticket id from path: /api/v1/tickets/:id/status
        let parts = path.split(separator: "/")
        if let idxTickets = parts.firstIndex(where: { $0 == "tickets" }),
           parts.index(after: idxTickets) < parts.endIndex {
            let idPart = parts[parts.index(after: idxTickets)]
            let ticketId = Int64(idPart) ?? 0
            if let req = body as? ChangeTicketStatusRequest {
                changeStatusCalls.append((ticketId: ticketId, statusId: req.statusId))
            }
        }
        switch changeStatusResult {
        case .success(let r):
            guard let cast = r as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        case .failure(let e):
            throw e
        }
    }

    func delete(_ path: String) async throws {}

    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw APITransportError.noBaseURL
    }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}

    // MARK: — Test helpers

    func setStatusListResult(_ result: Result<[TicketStatusRow], Error>) {
        statusListResult = result
    }

    func setChangeStatusResult(_ result: Result<CreatedResource, Error>) {
        changeStatusResult = result
    }
}

// MARK: - TicketDetail factory

private func makeTicket(
    id: Int64 = 1,
    statusId: Int64? = 10,
    statusName: String = "Open",
    assignedTo: Int64? = nil
) -> TicketDetail {
    var json: [String: Any] = [
        "id": id,
        "order_id": "T-001",
        "customer_id": 5,
        "total": 99.0,
        "devices": [] as [Any],
        "notes": [] as [Any],
        "history": [] as [Any],
        "photos": [] as [Any]
    ]
    if let statusId {
        json["status_id"] = statusId
        json["status"] = ["id": statusId, "name": statusName] as [String: Any]
    }
    if let assignedTo {
        json["assigned_to"] = assignedTo
        json["assigned_user"] = ["id": assignedTo, "first_name": "Tech"] as [String: Any]
    }
    let data = try! JSONSerialization.data(withJSONObject: json)
    return try! JSONDecoder().decode(TicketDetail.self, from: data)
}

private func makeStatuses() -> [TicketStatusRow] {
    let json: [[String: Any]] = [
        ["id": 10, "name": "Open",        "sort_order": 1, "is_closed": 0, "is_cancelled": 0],
        ["id": 20, "name": "In Progress", "sort_order": 2, "is_closed": 0, "is_cancelled": 0],
        ["id": 30, "name": "Closed",      "sort_order": 3, "is_closed": 1, "is_cancelled": 0]
    ]
    let data = try! JSONSerialization.data(withJSONObject: json)
    return try! JSONDecoder().decode([TicketStatusRow].self, from: data)
}

// MARK: - Tests

@Suite("TicketInspectorViewModel")
@MainActor
struct TicketInspectorViewModelTests {

    // MARK: TC-1: fields initialised from ticket on init

    @Test("TC-1 fields initialised from ticket on init")
    func loadInitialisesFields() {
        let ticket = makeTicket(statusId: 10, assignedTo: 42)
        let stub = InspectorStubAPIClient()
        let vm = TicketInspectorViewModel(ticket: ticket, api: stub)

        #expect(vm.selectedStatusId == 10)
        #expect(vm.selectedStatusName == "Open")
        #expect(vm.assigneeId == 42)
        #expect(!vm.isSaving)
        #expect(!vm.isLoadingStatuses)
        #expect(vm.errorMessage == nil)
        #expect(!vm.didSave)
    }

    // MARK: TC-2: field mutations reflected before save

    @Test("TC-2 field mutations are reflected immediately")
    func mutateFields() {
        let ticket = makeTicket(statusId: 10)
        let stub = InspectorStubAPIClient()
        let vm = TicketInspectorViewModel(ticket: ticket, api: stub)

        vm.selectedStatusId = 20
        vm.selectedStatusName = "In Progress"
        vm.assigneeId = 7
        vm.assigneeName = "Jane"
        vm.priority = "high"
        vm.tagsText = "vip, urgent"

        #expect(vm.selectedStatusId == 20)
        #expect(vm.selectedStatusName == "In Progress")
        #expect(vm.assigneeId == 7)
        #expect(vm.priority == "high")
        #expect(vm.tagsText == "vip, urgent")
        #expect(!vm.didSave)
    }

    // MARK: TC-3: save-success — correct API methods called

    @Test("TC-3 save calls changeTicketStatus + updateTicket on changed fields")
    func saveSuccess() async {
        let ticket = makeTicket(statusId: 10, assignedTo: nil)
        let stub = InspectorStubAPIClient()
        var savedCalled = false
        let vm = TicketInspectorViewModel(ticket: ticket, api: stub) {
            savedCalled = true
        }

        vm.selectedStatusId = 20
        vm.assigneeId = 7

        await vm.save()

        #expect(vm.didSave)
        #expect(vm.errorMessage == nil)
        #expect(savedCalled)

        let statusCalls = await stub.changeStatusCalls
        #expect(statusCalls.count == 1)
        #expect(statusCalls[0].ticketId == 1)
        #expect(statusCalls[0].statusId == 20)

        let updateCalls = await stub.updateTicketCalls
        #expect(updateCalls.count == 1)
        #expect(updateCalls[0].assignedTo == 7)
    }

    // MARK: TC-4: save-error — errorMessage set, didSave remains false

    @Test("TC-4 save error: errorMessage set and didSave stays false")
    func saveError() async {
        let ticket = makeTicket(statusId: 10)
        let stub = InspectorStubAPIClient()
        await stub.setChangeStatusResult(.failure(APITransportError.noBaseURL))
        let vm = TicketInspectorViewModel(ticket: ticket, api: stub)

        vm.selectedStatusId = 20

        await vm.save()

        #expect(!vm.didSave)
        #expect(vm.errorMessage != nil)
        #expect(!vm.isSaving)
    }

    // MARK: TC-5: cancel — resets fields to original ticket values

    @Test("TC-5 cancel resets fields to original ticket state")
    func cancelResetsFields() {
        let ticket = makeTicket(statusId: 10, assignedTo: 3)
        let stub = InspectorStubAPIClient()
        let vm = TicketInspectorViewModel(ticket: ticket, api: stub)

        vm.selectedStatusId = 20
        vm.selectedStatusName = "In Progress"
        vm.assigneeId = 99
        vm.priority = "critical"
        vm.tagsText = "urgent"

        vm.cancel()

        #expect(vm.selectedStatusId == 10)
        #expect(vm.selectedStatusName == "Open")
        #expect(vm.assigneeId == 3)
        #expect(vm.priority == "")
        #expect(vm.tagsText == "")
        #expect(vm.errorMessage == nil)
        #expect(!vm.didSave)
    }

    // MARK: TC-6: loadStatuses — populates availableStatuses from API

    @Test("TC-6 loadStatuses populates availableStatuses")
    func loadStatuses() async {
        let statuses = makeStatuses()
        let stub = InspectorStubAPIClient()
        await stub.setStatusListResult(.success(statuses))
        let vm = TicketInspectorViewModel(ticket: makeTicket(), api: stub)

        await vm.loadStatuses()

        #expect(vm.availableStatuses.count == 3)
        #expect(vm.availableStatuses[0].name == "Open")
        #expect(vm.availableStatuses[1].name == "In Progress")
        #expect(!vm.isLoadingStatuses)
    }

    // MARK: TC-7: setTicket — switching ticket resets all state

    @Test("TC-7 setTicket resets state for the incoming ticket")
    func setTicketResetsState() {
        let ticketA = makeTicket(id: 1, statusId: 10, assignedTo: nil)
        let ticketB = makeTicket(id: 2, statusId: 30, statusName: "Closed", assignedTo: 8)
        let stub = InspectorStubAPIClient()
        let vm = TicketInspectorViewModel(ticket: ticketA, api: stub)

        vm.selectedStatusId = 20
        vm.priority = "high"

        vm.setTicket(ticketB)

        #expect(vm.ticket.id == 2)
        #expect(vm.selectedStatusId == 30)
        #expect(vm.selectedStatusName == "Closed")
        #expect(vm.assigneeId == 8)
        #expect(vm.priority == "")
        #expect(!vm.didSave)
    }
}
