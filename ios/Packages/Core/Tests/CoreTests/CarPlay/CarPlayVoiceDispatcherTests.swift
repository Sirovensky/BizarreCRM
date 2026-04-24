#if canImport(CarPlay)
import XCTest
@testable import Core

// MARK: - Mock

/// Minimal in-process implementation of ``CarPlayVoiceDispatcher`` for testing.
///
/// Returns configurable outcomes so tests can verify that callers correctly
/// handle every ``CarPlayVoiceDispatcherResult`` case.
private final class MockVoiceDispatcher: CarPlayVoiceDispatcher {

    let tenantSlug: String

    /// Fixed result to return for any command, configurable per test.
    var stubbedResult: CarPlayVoiceDispatcherResult

    /// Records every command passed to `handle(_:)`.
    private(set) var receivedCommands: [CarPlayVoiceCommand] = []

    init(
        tenantSlug: String = "acme",
        stubbedResult: CarPlayVoiceDispatcherResult = .notHandled(feedback: "")
    ) {
        self.tenantSlug = tenantSlug
        self.stubbedResult = stubbedResult
    }

    func handle(_ command: CarPlayVoiceCommand) async -> CarPlayVoiceDispatcherResult {
        receivedCommands.append(command)
        return stubbedResult
    }
}

// MARK: - CarPlayVoiceCommandTests

/// Tests the ``CarPlayVoiceCommand`` enum's value equality and exhaustiveness.
final class CarPlayVoiceCommandTests: XCTestCase {

    func test_callContact_equality() {
        XCTAssertEqual(
            CarPlayVoiceCommand.callContact(name: "Alice"),
            CarPlayVoiceCommand.callContact(name: "Alice")
        )
    }

    func test_callContact_differentName_notEqual() {
        XCTAssertNotEqual(
            CarPlayVoiceCommand.callContact(name: "Alice"),
            CarPlayVoiceCommand.callContact(name: "Bob")
        )
    }

    func test_openTicket_equality() {
        XCTAssertEqual(
            CarPlayVoiceCommand.openTicket(id: "T-1"),
            CarPlayVoiceCommand.openTicket(id: "T-1")
        )
    }

    func test_openTicket_differentId_notEqual() {
        XCTAssertNotEqual(
            CarPlayVoiceCommand.openTicket(id: "T-1"),
            CarPlayVoiceCommand.openTicket(id: "T-2")
        )
    }

    func test_showVoicemail_equality() {
        XCTAssertEqual(CarPlayVoiceCommand.showVoicemail, .showVoicemail)
    }

    func test_showCallLog_equality() {
        XCTAssertEqual(CarPlayVoiceCommand.showCallLog, .showCallLog)
    }

    func test_unrecognised_equality() {
        XCTAssertEqual(
            CarPlayVoiceCommand.unrecognised(transcript: "huh?"),
            CarPlayVoiceCommand.unrecognised(transcript: "huh?")
        )
    }

    func test_unrecognised_differentTranscript_notEqual() {
        XCTAssertNotEqual(
            CarPlayVoiceCommand.unrecognised(transcript: "foo"),
            CarPlayVoiceCommand.unrecognised(transcript: "bar")
        )
    }
}

// MARK: - CarPlayVoiceDispatcherResultTests

/// Tests the ``CarPlayVoiceDispatcherResult`` enum's value equality.
final class CarPlayVoiceDispatcherResultTests: XCTestCase {

    private let dest = DeepLinkDestination.dashboard(tenantSlug: "acme")

    func test_navigated_equality() {
        XCTAssertEqual(
            CarPlayVoiceDispatcherResult.navigated(to: dest),
            CarPlayVoiceDispatcherResult.navigated(to: dest)
        )
    }

    func test_navigated_differentDestination_notEqual() {
        let other = DeepLinkDestination.ticket(tenantSlug: "acme", id: "T-1")
        XCTAssertNotEqual(
            CarPlayVoiceDispatcherResult.navigated(to: dest),
            CarPlayVoiceDispatcherResult.navigated(to: other)
        )
    }

    func test_needsDisambiguation_equality() {
        XCTAssertEqual(
            CarPlayVoiceDispatcherResult.needsDisambiguation(hint: "Which John?"),
            CarPlayVoiceDispatcherResult.needsDisambiguation(hint: "Which John?")
        )
    }

    func test_notHandled_equality() {
        XCTAssertEqual(
            CarPlayVoiceDispatcherResult.notHandled(feedback: "Sorry"),
            CarPlayVoiceDispatcherResult.notHandled(feedback: "Sorry")
        )
    }
}

// MARK: - MockVoiceDispatcherTests

/// Integration-style tests using ``MockVoiceDispatcher`` to validate the
/// protocol contract.
final class MockVoiceDispatcherTests: XCTestCase {

    private var dispatcher: MockVoiceDispatcher!

    override func setUp() {
        super.setUp()
        dispatcher = MockVoiceDispatcher()
    }

    // MARK: tenantSlug

    func test_tenantSlug_returnsConfiguredSlug() {
        let d = MockVoiceDispatcher(tenantSlug: "demo")
        XCTAssertEqual(d.tenantSlug, "demo")
    }

    // MARK: handle — records commands

    func test_handle_recordsCallContactCommand() async {
        _ = await dispatcher.handle(.callContact(name: "Alice"))
        XCTAssertEqual(dispatcher.receivedCommands, [.callContact(name: "Alice")])
    }

    func test_handle_recordsMultipleCommandsInOrder() async {
        _ = await dispatcher.handle(.showVoicemail)
        _ = await dispatcher.handle(.showCallLog)
        XCTAssertEqual(dispatcher.receivedCommands, [.showVoicemail, .showCallLog])
    }

    // MARK: handle — returns stubbed result

    func test_handle_returnsNavigatedResult() async {
        let dest = DeepLinkDestination.dashboard(tenantSlug: "acme")
        dispatcher.stubbedResult = .navigated(to: dest)
        let result = await dispatcher.handle(.showVoicemail)
        XCTAssertEqual(result, .navigated(to: dest))
    }

    func test_handle_returnsNeedsDisambiguationResult() async {
        dispatcher.stubbedResult = .needsDisambiguation(hint: "Which John?")
        let result = await dispatcher.handle(.callContact(name: "John"))
        XCTAssertEqual(result, .needsDisambiguation(hint: "Which John?"))
    }

    func test_handle_returnsNotHandledResult() async {
        dispatcher.stubbedResult = .notHandled(feedback: "Unrecognised")
        let result = await dispatcher.handle(.unrecognised(transcript: "blah"))
        XCTAssertEqual(result, .notHandled(feedback: "Unrecognised"))
    }

    func test_handle_openTicket_recordedCorrectly() async {
        _ = await dispatcher.handle(.openTicket(id: "T-99"))
        XCTAssertEqual(dispatcher.receivedCommands.first, .openTicket(id: "T-99"))
    }
}

#endif // canImport(CarPlay)
