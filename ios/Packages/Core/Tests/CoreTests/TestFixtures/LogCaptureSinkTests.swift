import XCTest
@testable import Core

// §31 Test-only logger seam — LogCaptureSink tests
//
// Verifies the LogSink protocol + LogCaptureSink in-memory implementation.
// These tests serve both as a correctness harness and as living documentation
// for how downstream tests should use the seam.

final class LogCaptureSinkTests: XCTestCase {

    private var sink: LogCaptureSink!

    override func setUp() {
        super.setUp()
        sink = LogCaptureSink()
    }

    override func tearDown() {
        sink.reset()
        sink = nil
        super.tearDown()
    }

    // MARK: — Basic capture

    func test_log_singleEntry_isCaptured() {
        sink.log(level: .info, message: "Hello", category: "app")
        XCTAssertEqual(sink.captured.count, 1)
        XCTAssertEqual(sink.captured[0].level, .info)
        XCTAssertEqual(sink.captured[0].message, "Hello")
        XCTAssertEqual(sink.captured[0].category, "app")
    }

    func test_log_multipleEntries_preservesOrder() {
        sink.log(level: .debug,  message: "first",  category: "networking")
        sink.log(level: .info,   message: "second", category: "networking")
        sink.log(level: .error,  message: "third",  category: "networking")
        XCTAssertEqual(sink.captured.count, 3)
        XCTAssertEqual(sink.captured[0].message, "first")
        XCTAssertEqual(sink.captured[1].message, "second")
        XCTAssertEqual(sink.captured[2].message, "third")
    }

    func test_log_emptyMessage_isCaptured() {
        sink.log(level: .notice, message: "", category: "app")
        XCTAssertEqual(sink.captured.count, 1)
        XCTAssertTrue(sink.captured[0].message.isEmpty)
    }

    // MARK: — reset

    func test_reset_clearsAllEntries() {
        sink.log(level: .fault, message: "boom", category: "sync")
        sink.reset()
        XCTAssertTrue(sink.captured.isEmpty, "reset() must clear all captured entries")
    }

    func test_reset_allowsSubsequentCapture() {
        sink.log(level: .debug, message: "before", category: "app")
        sink.reset()
        sink.log(level: .info, message: "after", category: "app")
        XCTAssertEqual(sink.captured.count, 1)
        XCTAssertEqual(sink.captured[0].message, "after")
    }

    // MARK: — entries(atOrAbove:)

    func test_entriesAtOrAbove_filtersCorrectly() {
        sink.log(level: .debug,  message: "d", category: "app")
        sink.log(level: .info,   message: "i", category: "app")
        sink.log(level: .notice, message: "n", category: "app")
        sink.log(level: .error,  message: "e", category: "app")
        sink.log(level: .fault,  message: "f", category: "app")

        let atInfo = sink.entries(atOrAbove: .info)
        XCTAssertEqual(atInfo.count, 4, "info and above must include info/notice/error/fault")

        let atError = sink.entries(atOrAbove: .error)
        XCTAssertEqual(atError.count, 2, "error and above must include error/fault")

        let atFault = sink.entries(atOrAbove: .fault)
        XCTAssertEqual(atFault.count, 1)
        XCTAssertEqual(atFault[0].message, "f")
    }

    func test_entriesAtOrAbove_debug_returnsAll() {
        sink.log(level: .debug, message: "a", category: "app")
        sink.log(level: .fault, message: "b", category: "app")
        XCTAssertEqual(sink.entries(atOrAbove: .debug).count, 2)
    }

    // MARK: — entries(category:)

    func test_entriesCategory_filtersToCategory() {
        sink.log(level: .info, message: "net1",  category: "networking")
        sink.log(level: .info, message: "auth1", category: "auth")
        sink.log(level: .info, message: "net2",  category: "networking")

        let net = sink.entries(category: "networking")
        XCTAssertEqual(net.count, 2)
        XCTAssertTrue(net.allSatisfy { $0.category == "networking" })
    }

    func test_entriesCategory_unknownCategory_returnsEmpty() {
        sink.log(level: .info, message: "x", category: "app")
        XCTAssertTrue(sink.entries(category: "nonexistent").isEmpty)
    }

    // MARK: — contains(substring:)

    func test_contains_substring_findsMatch() {
        sink.log(level: .error, message: "database error: SQLITE_FULL", category: "db")
        XCTAssertTrue(sink.contains(substring: "SQLITE_FULL"))
        XCTAssertTrue(sink.contains(substring: "database error"))
    }

    func test_contains_substring_noMatch_returnsFalse() {
        sink.log(level: .info, message: "all good", category: "sync")
        XCTAssertFalse(sink.contains(substring: "failure"))
    }

    // MARK: — contains(level:substring:)

    func test_contains_levelAndSubstring_matchesExact() {
        sink.log(level: .error,  message: "sync failed", category: "sync")
        sink.log(level: .notice, message: "sync failed", category: "sync")

        // .error entry matches; .fault entry does not exist — so false
        XCTAssertTrue(sink.contains(level: .error,  substring: "sync failed"))
        XCTAssertFalse(sink.contains(level: .fault, substring: "sync failed"))
    }

    // MARK: — LogLevel ordering

    func test_logLevel_ordering() {
        XCTAssertLessThan(LogLevel.debug,  LogLevel.info)
        XCTAssertLessThan(LogLevel.info,   LogLevel.notice)
        XCTAssertLessThan(LogLevel.notice, LogLevel.error)
        XCTAssertLessThan(LogLevel.error,  LogLevel.fault)
    }

    func test_logLevel_descriptions_areNonEmpty() {
        let levels: [LogLevel] = [.debug, .info, .notice, .error, .fault]
        for level in levels {
            XCTAssertFalse(level.description.isEmpty, "\(level).description must not be empty")
        }
    }

    // MARK: — LogEntry.description

    func test_logEntry_description_includesAllParts() {
        let entry = LogEntry(level: .error, message: "oops", category: "sync")
        let desc = entry.description
        XCTAssertTrue(desc.contains("ERROR"),  "description must include level")
        XCTAssertTrue(desc.contains("sync"),   "description must include category")
        XCTAssertTrue(desc.contains("oops"),   "description must include message")
    }

    // MARK: — NullLogSink

    func test_nullLogSink_doesNotCrash() {
        let null = NullLogSink()
        null.log(level: .fault, message: "anything", category: "any")
        // No assertion needed — just verifying it doesn't crash
    }

    // MARK: — Protocol conformance (compile-time)

    func test_logCaptureSink_conformsToLogSink() {
        let _: LogSink = LogCaptureSink()
    }

    func test_nullLogSink_conformsToLogSink() {
        let _: LogSink = NullLogSink()
    }

    // MARK: — Thread safety smoke test

    func test_concurrentWrites_doNotCrash() {
        let expectation = expectation(description: "concurrent writes")
        expectation.expectedFulfillmentCount = 100
        let sink = LogCaptureSink()
        for i in 0..<100 {
            DispatchQueue.global().async {
                sink.log(level: .debug, message: "msg \(i)", category: "test")
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 5)
        XCTAssertEqual(sink.captured.count, 100, "All 100 concurrent writes must be captured")
    }
}
