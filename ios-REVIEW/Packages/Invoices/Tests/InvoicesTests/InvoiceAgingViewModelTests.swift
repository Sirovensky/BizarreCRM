#if canImport(UIKit)
import XCTest
@testable import Invoices
@testable import Networking

// §7.6 InvoiceAgingViewModel — load + sendReminder

// MARK: - Aging-specific stub

private actor AgingStubAPIClient: APIClient {
    enum Mode {
        case agingSuccess(InvoiceAgingReport)
        case agingFailure(Error)
        case reminderSuccess
        case reminderFailure(Error)
    }

    private var agingMode: Mode
    private var reminderMode: Mode

    init(aging: Mode, reminder: Mode = .reminderSuccess) {
        self.agingMode = aging
        self.reminderMode = reminder
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if path.hasSuffix("/reports/aging") {
            switch agingMode {
            case .agingSuccess(let report):
                guard let cast = report as? T else { throw APITransportError.decoding("type mismatch") }
                return cast
            case .agingFailure(let err):
                throw err
            default:
                throw APITransportError.noBaseURL
            }
        }
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        // bulk-action endpoint
        if path.hasSuffix("/invoices/bulk") || path.hasSuffix("/bulk") || path.contains("bulk") {
            switch reminderMode {
            case .reminderSuccess:
                // Return empty-ish BulkActionResponse
                let data = """
                {"processed":1,"failed":0,"errors":[]}
                """.data(using: .utf8)!
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                return try decoder.decode(T.self, from: data)
            case .reminderFailure(let err):
                throw err
            default:
                throw APITransportError.noBaseURL
            }
        }
        throw APITransportError.noBaseURL
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw APITransportError.noBaseURL
    }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

// MARK: - Helpers

private func makeSummary(id: Int64, daysOverdue: Int) -> AgingInvoiceSummary {
    // AgingInvoiceSummary is Decodable-only; build via JSON round-trip
    let json = """
    {
        "id": \(id),
        "order_id": "INV-\(id)",
        "customer_name": "Customer \(id)",
        "total_cents": 10000,
        "days_overdue": \(daysOverdue),
        "due_on": null
    }
    """.data(using: .utf8)!
    return try! JSONDecoder().decode(AgingInvoiceSummary.self, from: json)
}

private func encodeBuckets(
    bucket0: [AgingInvoiceSummary],
    bucket31: [AgingInvoiceSummary],
    bucket61: [AgingInvoiceSummary],
    bucket91: [AgingInvoiceSummary]
) -> Data {
    func bucketJSON(_ id: String, _ label: String, _ invoices: [AgingInvoiceSummary]) -> String {
        let invJSON = invoices.map { inv in
            """
            {"id":\(inv.id),"order_id":"\(inv.displayId)","customer_name":"\(inv.customerName ?? "")","total_cents":\(inv.totalCents),"days_overdue":\(inv.daysOverdue),"due_on":null}
            """
        }.joined(separator: ",")
        let total = invoices.reduce(0) { $0 + $1.totalCents }
        return """
        {"id":"\(id)","label":"\(label)","total_cents":\(total),"invoice_count":\(invoices.count),"invoices":[\(invJSON)]}
        """
    }
    let all = bucket0 + bucket31 + bucket61 + bucket91
    let totalCents = all.reduce(0) { $0 + $1.totalCents }
    let bucketsJSON = [
        bucketJSON("0-30",  "0\u{2013}30 days",  bucket0),
        bucketJSON("31-60", "31\u{2013}60 days", bucket31),
        bucketJSON("61-90", "61\u{2013}90 days", bucket61),
        bucketJSON("90+",   "90+ days",           bucket91)
    ].joined(separator: ",")
    let json = """
    {"buckets":[\(bucketsJSON)],"total_overdue_cents":\(totalCents)}
    """
    return json.data(using: .utf8)!
}

private func makeReport(
    bucket0: [AgingInvoiceSummary] = [],
    bucket31: [AgingInvoiceSummary] = [],
    bucket61: [AgingInvoiceSummary] = [],
    bucket91: [AgingInvoiceSummary] = []
) -> InvoiceAgingReport {
    let data = encodeBuckets(bucket0: bucket0, bucket31: bucket31, bucket61: bucket61, bucket91: bucket91)
    return try! JSONDecoder().decode(InvoiceAgingReport.self, from: data)
}

// MARK: - Tests

@MainActor
final class InvoiceAgingViewModelTests: XCTestCase {

    // MARK: load()

    func testLoad_success_setsLoadedState() async {
        let report = makeReport(bucket0: [makeSummary(id: 1, daysOverdue: 15)])
        let api = AgingStubAPIClient(aging: .agingSuccess(report))
        let vm = InvoiceAgingViewModel(api: api)

        await vm.load()

        if case .loaded(let r) = vm.loadState {
            XCTAssertEqual(r.buckets.count, 4)
            XCTAssertEqual(r.buckets[0].invoices.count, 1)
            XCTAssertEqual(r.buckets[0].invoices[0].id, 1)
        } else {
            XCTFail("Expected .loaded, got \(vm.loadState)")
        }
    }

    func testLoad_failure_setsFailedState() async {
        let api = AgingStubAPIClient(aging: .agingFailure(APITransportError.noBaseURL))
        let vm = InvoiceAgingViewModel(api: api)

        await vm.load()

        if case .failed(let msg) = vm.loadState {
            XCTAssertFalse(msg.isEmpty)
        } else {
            XCTFail("Expected .failed, got \(vm.loadState)")
        }
    }

    func testLoad_initialState_isIdle() {
        let api = AgingStubAPIClient(aging: .agingSuccess(makeReport()))
        let vm = InvoiceAgingViewModel(api: api)
        if case .idle = vm.loadState { } else {
            XCTFail("Initial state must be .idle")
        }
    }

    func testLoad_duringLoad_isLoadingThenLoaded() async {
        let report = makeReport()
        let api = AgingStubAPIClient(aging: .agingSuccess(report))
        let vm = InvoiceAgingViewModel(api: api)

        // After await, state must be .loaded (not .loading)
        await vm.load()
        if case .loaded = vm.loadState { } else {
            XCTFail("Expected .loaded after await")
        }
    }

    // MARK: totalOverdueCents

    func testLoad_totalOverdueCents_sumAcrossBuckets() async {
        let report = makeReport(
            bucket0:  [makeSummary(id: 1, daysOverdue: 10)],  // 10_000
            bucket31: [makeSummary(id: 2, daysOverdue: 45)],  // 10_000
            bucket91: [makeSummary(id: 3, daysOverdue: 95)]   // 10_000
        )
        let api = AgingStubAPIClient(aging: .agingSuccess(report))
        let vm = InvoiceAgingViewModel(api: api)
        await vm.load()

        if case .loaded(let r) = vm.loadState {
            XCTAssertEqual(r.totalOverdueCents, 30_000)
        } else {
            XCTFail("Expected .loaded")
        }
    }

    // MARK: emptyReport

    func testLoad_emptyBuckets_allInvoicesEmpty() async {
        let report = makeReport() // all buckets empty
        let api = AgingStubAPIClient(aging: .agingSuccess(report))
        let vm = InvoiceAgingViewModel(api: api)
        await vm.load()

        if case .loaded(let r) = vm.loadState {
            XCTAssertTrue(r.buckets.allSatisfy { $0.invoices.isEmpty })
        } else {
            XCTFail("Expected .loaded")
        }
    }

    // MARK: sendReminder()

    func testSendReminder_success_setsReminderMessage() async {
        let report = makeReport(bucket0: [makeSummary(id: 7, daysOverdue: 20)])
        let api = AgingStubAPIClient(aging: .agingSuccess(report), reminder: .reminderSuccess)
        let vm = InvoiceAgingViewModel(api: api)
        await vm.load()

        await vm.sendReminder(invoiceId: 7)

        XCTAssertEqual(vm.reminderMessage, "Reminder sent")
        XCTAssertFalse(vm.isSendingReminder, "isSendingReminder must be false after completion (defer)")
    }

    func testSendReminder_failure_setsFailedMessage() async {
        let err = APITransportError.noBaseURL
        let api = AgingStubAPIClient(aging: .agingSuccess(makeReport()), reminder: .reminderFailure(err))
        let vm = InvoiceAgingViewModel(api: api)

        await vm.sendReminder(invoiceId: 99)

        XCTAssertTrue(vm.reminderMessage?.hasPrefix("Failed:") == true,
                      "Expected 'Failed: …', got: \(vm.reminderMessage ?? "nil")")
        XCTAssertFalse(vm.isSendingReminder)
    }

    func testSendReminder_deferResetsisSendingReminder() async {
        // Even on success, isSendingReminder = false after await
        let api = AgingStubAPIClient(aging: .agingSuccess(makeReport()), reminder: .reminderSuccess)
        let vm = InvoiceAgingViewModel(api: api)

        await vm.sendReminder(invoiceId: 1)
        XCTAssertFalse(vm.isSendingReminder)
    }

    // MARK: Bucket model

    func testBucket_labels() {
        let report = makeReport()
        // En-dash (U+2013) used in range labels
        XCTAssertEqual(report.buckets[0].label, "0\u{2013}30 days")
        XCTAssertEqual(report.buckets[1].label, "31\u{2013}60 days")
        XCTAssertEqual(report.buckets[2].label, "61\u{2013}90 days")
        XCTAssertEqual(report.buckets[3].label, "90+ days")
    }

    func testBucket_ids_unique() {
        let report = makeReport()
        let ids = report.buckets.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Bucket IDs must be unique")
    }

    // MARK: AgingInvoiceSummary model

    func testAgingInvoiceSummary_displayId_format() {
        let inv = makeSummary(id: 42, daysOverdue: 5)
        XCTAssertEqual(inv.displayId, "INV-42")
    }

    func testAgingInvoiceSummary_daysOverdue_preserved() {
        let inv = makeSummary(id: 1, daysOverdue: 95)
        XCTAssertEqual(inv.daysOverdue, 95)
    }
}
#endif
