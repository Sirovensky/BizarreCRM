import XCTest
@testable import KioskMode

// MARK: - TrainingChecklistViewModel tests

@MainActor
final class TrainingChecklistViewModelTests: XCTestCase {

    private func makeSUT(defaults: UserDefaults? = nil) -> TrainingChecklistViewModel {
        let d = defaults ?? {
            let name = "test_training_\(UUID().uuidString)"
            return UserDefaults(suiteName: name)!
        }()
        return TrainingChecklistViewModel(defaults: d)
    }

    // MARK: - Initial state

    func test_initial_noStepsCompleted() {
        let vm = makeSUT()
        for topic in vm.topics {
            XCTAssertEqual(vm.completedCount(for: topic), 0)
            XCTAssertFalse(vm.isTopicComplete(topic))
        }
    }

    func test_initial_progressIsZero() {
        let vm = makeSUT()
        XCTAssertEqual(vm.overallProgress, 0.0, accuracy: 0.001)
    }

    // MARK: - Toggle

    func test_toggleStep_marksAsComplete() throws {
        let vm = makeSUT()
        guard let topic = vm.topics.first, let step = topic.steps.first else {
            return XCTFail("No topics / steps")
        }
        XCTAssertFalse(vm.isCompleted(step))
        vm.toggleStep(step)
        XCTAssertTrue(vm.isCompleted(step))
    }

    func test_toggleStep_idempotentUnmark() {
        let vm = makeSUT()
        guard let topic = vm.topics.first, let step = topic.steps.first else {
            return XCTFail()
        }
        vm.toggleStep(step)
        vm.toggleStep(step)
        XCTAssertFalse(vm.isCompleted(step))
    }

    // MARK: - Topic completion

    func test_isTopicComplete_whenAllStepsDone() throws {
        let vm = makeSUT()
        guard let topic = vm.topics.first else { return XCTFail() }
        for step in topic.steps { vm.toggleStep(step) }
        XCTAssertTrue(vm.isTopicComplete(topic))
    }

    func test_completedCount_incrementsPerStep() {
        let vm = makeSUT()
        guard let topic = vm.topics.first else { return XCTFail() }
        var count = 0
        for step in topic.steps {
            vm.toggleStep(step)
            count += 1
            XCTAssertEqual(vm.completedCount(for: topic), count)
        }
    }

    // MARK: - Reset

    func test_resetAll_clearsAllSteps() {
        let vm = makeSUT()
        guard let topic = vm.topics.first, let step = topic.steps.first else {
            return XCTFail()
        }
        vm.toggleStep(step)
        XCTAssertTrue(vm.isCompleted(step))
        vm.resetAll()
        XCTAssertFalse(vm.isCompleted(step))
        XCTAssertEqual(vm.overallProgress, 0.0, accuracy: 0.001)
    }

    // MARK: - Overall progress

    func test_overallProgress_isOneWhenAllDone() {
        let vm = makeSUT()
        for topic in vm.topics {
            for step in topic.steps { vm.toggleStep(step) }
        }
        XCTAssertEqual(vm.overallProgress, 1.0, accuracy: 0.001)
    }

    // MARK: - Default topics coverage

    func test_defaultTopics_count() {
        XCTAssertEqual(TrainingTopic.all.count, 4)
    }

    func test_defaultTopics_eachHasAtLeastOneStep() {
        for topic in TrainingTopic.all {
            XCTAssertFalse(topic.steps.isEmpty, "\(topic.title) has no steps")
        }
    }

    func test_defaultTopics_uniqueIds() {
        let ids = TrainingTopic.all.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count, "Topic IDs must be unique")
    }

    func test_defaultTopics_uniqueStepIds() {
        let all = TrainingTopic.all.flatMap { $0.steps }.map { $0.id }
        XCTAssertEqual(Set(all).count, all.count, "Step IDs must be globally unique")
    }
}
