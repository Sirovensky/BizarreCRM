import XCTest
@testable import KioskMode

// MARK: - TutorialChecklistTests
// §51.3 — Verifies topic catalog + completion store.

final class TutorialChecklistTests: XCTestCase {

    func test_catalogHasFourTopics() {
        XCTAssertEqual(TutorialTopic.catalog.count, 4)
    }

    func test_catalogTopicIDs_areUnique() {
        let ids = TutorialTopic.catalog.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func test_eachTopicHasAtLeastThreeSteps() {
        for topic in TutorialTopic.catalog {
            XCTAssertGreaterThanOrEqual(topic.steps.count, 3, "Topic \(topic.id) has too few steps")
        }
    }

    func test_completionStore_markAndCheck() {
        let defaults = UserDefaults(suiteName: "test.tutorialchecklist.\(UUID().uuidString)")!
        let store = TutorialCompletionStore(defaults: defaults)

        XCTAssertFalse(store.isComplete("pos-basics"))
        store.markComplete("pos-basics")
        XCTAssertTrue(store.isComplete("pos-basics"))
        XCTAssertFalse(store.isComplete("ticket-intake"))
    }

    func test_completionStore_reset() {
        let defaults = UserDefaults(suiteName: "test.tutorialchecklist.\(UUID().uuidString)")!
        let store = TutorialCompletionStore(defaults: defaults)

        store.markComplete("pos-basics")
        store.markComplete("invoicing")
        store.reset()
        XCTAssertTrue(store.completedTopicIDs.isEmpty)
    }
}
