import Foundation
import Networking

// §48.5 RecurringImportRepository — all APIClient calls for recurring import schedules
// and on-change webhooks live here per §20 containment rule.
//
// Server endpoints are stubs (not yet implemented):
//   GET    /imports/recurring
//   POST   /imports/recurring
//   PUT    /imports/recurring/:id
//   DELETE /imports/recurring/:id
//   POST   /imports/recurring/:id/run-now
//   GET    /imports/webhooks
//   POST   /imports/webhooks

public protocol RecurringImportRepository: Sendable {
    func listSchedules() async throws -> [RecurringImportSchedule]
    func createSchedule(_ s: RecurringImportSchedule) async throws -> RecurringImportSchedule
    func updateSchedule(_ s: RecurringImportSchedule) async throws -> RecurringImportSchedule
    func deleteSchedule(id: String) async throws
    func runNow(id: String) async throws -> String?  // returns triggered jobId if any
    func listWebhooks() async throws -> [ImportWebhook]
    func createWebhook(_ w: ImportWebhook) async throws -> ImportWebhook
}

public actor RecurringImportRepositoryImpl: RecurringImportRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func listSchedules() async throws -> [RecurringImportSchedule] {
        return try await api.get("/imports/recurring", as: [RecurringImportSchedule].self)
    }

    public func createSchedule(_ s: RecurringImportSchedule) async throws -> RecurringImportSchedule {
        return try await api.post("/imports/recurring", body: s, as: RecurringImportSchedule.self)
    }

    public func updateSchedule(_ s: RecurringImportSchedule) async throws -> RecurringImportSchedule {
        return try await api.put("/imports/recurring/\(s.id)", body: s, as: RecurringImportSchedule.self)
    }

    public func deleteSchedule(id: String) async throws {
        try await api.delete("/imports/recurring/\(id)")
    }

    public func runNow(id: String) async throws -> String? {
        struct Body: Encodable, Sendable {}
        struct Response: Decodable, Sendable {
            let jobId: String?
            enum CodingKeys: String, CodingKey { case jobId = "job_id" }
        }
        let resp = try await api.post("/imports/recurring/\(id)/run-now",
                                       body: Body(), as: Response.self)
        return resp.jobId
    }

    public func listWebhooks() async throws -> [ImportWebhook] {
        return try await api.get("/imports/webhooks", as: [ImportWebhook].self)
    }

    public func createWebhook(_ w: ImportWebhook) async throws -> ImportWebhook {
        return try await api.post("/imports/webhooks", body: w, as: ImportWebhook.self)
    }
}
