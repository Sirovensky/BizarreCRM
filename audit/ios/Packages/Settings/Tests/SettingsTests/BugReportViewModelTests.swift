import Testing
import Foundation
@testable import Settings
import Core
import Networking

// MARK: - MockAPIClient

final class MockAPIClient: APIClient, @unchecked Sendable {

    // MARK: - Configuration

    var postHandler: ((String) throws -> any (Decodable & Sendable))?
    var getHandler: ((String) throws -> any (Decodable & Sendable))?

    // MARK: - APIClient

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if let handler = getHandler {
            return try handler(path) as! T
        }
        throw URLError(.notConnectedToInternet)
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if let handler = postHandler {
            return try handler(path) as! T
        }
        throw URLError(.notConnectedToInternet)
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw URLError(.notConnectedToInternet)
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw URLError(.notConnectedToInternet)
    }

    func delete(_ path: String) async throws {}

    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw URLError(.notConnectedToInternet)
    }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

// MARK: - BugReportViewModelTests

@Suite("BugReportViewModel")
@MainActor
struct BugReportViewModelTests {

    // MARK: - Validation

    @Test("isValid is false when description is empty")
    func isValidFalseWhenEmpty() {
        let vm = BugReportViewModel(api: nil)
        #expect(!vm.isValid)
    }

    @Test("isValid is false when description is whitespace only")
    func isValidFalseWhitespace() {
        let vm = BugReportViewModel(api: nil)
        vm.description = "   "
        #expect(!vm.isValid)
    }

    @Test("isValid is true when description has content")
    func isValidTrueWithContent() {
        let vm = BugReportViewModel(api: nil)
        vm.description = "App crashed on startup"
        #expect(vm.isValid)
    }

    // MARK: - Submit

    @Test("Submit sets validationError when description is empty")
    func submitWithEmptyDescription() async {
        let vm = BugReportViewModel(api: nil)
        await vm.submit()
        #expect(vm.validationError != nil)
        #expect(vm.submissionResult == nil)
    }

    @Test("Submit with no API sets failure result")
    func submitWithNoAPI() async {
        let vm = BugReportViewModel(api: nil)
        vm.description = "Test bug"
        await vm.submit()
        if case .failure = vm.submissionResult { } else {
            Issue.record("Expected failure result but got: \(String(describing: vm.submissionResult))")
        }
    }

    @Test("Submit calls POST and captures path")
    func submitCallsCorrectEndpoint() async {
        let mockAPI = MockAPIClient()
        var capturedPath: String?
        // BugReportResponse is internal — we simulate a network error after path capture
        // to confirm the endpoint was hit, then verify the failure path.
        mockAPI.postHandler = { path in
            capturedPath = path
            throw URLError(.notConnectedToInternet)
        }

        let vm = BugReportViewModel(api: mockAPI)
        vm.description = "Crash on launch"
        await vm.submit()

        #expect(capturedPath == "/support/bug-reports")
    }

    @Test("Submit network error sets failure result")
    func submitNetworkErrorSetsFailure() async {
        let mockAPI = MockAPIClient()
        mockAPI.postHandler = { _ in throw URLError(.notConnectedToInternet) }

        let vm = BugReportViewModel(api: mockAPI)
        vm.description = "Some bug"
        await vm.submit()

        if case .failure = vm.submissionResult { } else {
            Issue.record("Expected failure, got: \(String(describing: vm.submissionResult))")
        }
    }

    // MARK: - Reset

    @Test("Reset clears description and result")
    func resetClears() {
        let vm = BugReportViewModel(api: nil)
        vm.description = "Something"
        vm.reset()
        #expect(vm.description.isEmpty)
        #expect(vm.submissionResult == nil)
        #expect(vm.validationError == nil)
    }

    @Test("Default category is uiBug")
    func defaultCategory() {
        let vm = BugReportViewModel(api: nil)
        #expect(vm.category == .uiBug)
    }

    @Test("Default severity is medium")
    func defaultSeverity() {
        let vm = BugReportViewModel(api: nil)
        #expect(vm.severity == .medium)
    }

    // MARK: - isSubmitting flag

    @Test("isSubmitting is false when idle")
    func isSubmittingFalseIdle() {
        let vm = BugReportViewModel(api: nil)
        #expect(!vm.isSubmitting)
    }
}
