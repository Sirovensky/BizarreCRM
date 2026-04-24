import XCTest
@testable import Camera

// MARK: - Mock Recorder

/// Test double for ``VoiceMemoViewModel.RecorderProtocol``.
///
/// Configurable behaviour:
/// - `authorizeShouldThrow`: when `true`, `authorize()` throws `VoiceMemoError.notAuthorized`.
/// - `startShouldThrow`: when `true`, `startRecording(maxDuration:)` throws.
/// - `stubbedURL`: the URL returned by `startRecording` and `stopRecording`.
/// Counters record call counts for assertion.
final class MockVoiceMemoRecorder: VoiceMemoViewModel.RecorderProtocol, @unchecked Sendable {

    var authorizeShouldThrow: Bool = false
    var startShouldThrow: Bool = false
    var stubbedURL: URL = FileManager.default.temporaryDirectory.appendingPathComponent("test-memo.m4a")

    private(set) var authorizeCallCount: Int = 0
    private(set) var startCallCount: Int = 0
    private(set) var stopCallCount: Int = 0

    func authorize() async throws -> Bool {
        authorizeCallCount += 1
        if authorizeShouldThrow { throw VoiceMemoError.notAuthorized }
        return true
    }

    func startRecording(maxDuration: TimeInterval) async throws -> URL {
        startCallCount += 1
        if startShouldThrow { throw VoiceMemoError.setupFailed("mock failure") }
        return stubbedURL
    }

    func stopRecording() async throws -> URL {
        stopCallCount += 1
        return stubbedURL
    }
}

// MARK: - VoiceMemoViewModelTests

@MainActor
final class VoiceMemoViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeVM(
        recorder: MockVoiceMemoRecorder = MockVoiceMemoRecorder(),
        maxDuration: TimeInterval = 120
    ) -> VoiceMemoViewModel {
        VoiceMemoViewModel(recorder: recorder, maxDuration: maxDuration)
    }

    // MARK: - Initial state

    func test_initial_state_isIdle() {
        let vm = makeVM()
        XCTAssertEqual(vm.recordingState, .idle)
    }

    func test_initial_elapsedSeconds_isZero() {
        let vm = makeVM()
        XCTAssertEqual(vm.elapsedSeconds, 0)
    }

    func test_initial_maxDuration_isStored() {
        let vm = makeVM(maxDuration: 60)
        XCTAssertEqual(vm.maxDuration, 60)
    }

    // MARK: - startRecording — happy path

    func test_startRecording_transitionsToRecording() async {
        let recorder = MockVoiceMemoRecorder()
        let vm = makeVM(recorder: recorder)
        await vm.startRecording()
        if case .recording = vm.recordingState {
            // expected
        } else {
            XCTFail("Expected .recording, got \(vm.recordingState)")
        }
    }

    func test_startRecording_callsAuthorizeOnce() async {
        let recorder = MockVoiceMemoRecorder()
        let vm = makeVM(recorder: recorder)
        await vm.startRecording()
        XCTAssertEqual(recorder.authorizeCallCount, 1)
    }

    func test_startRecording_callsStartOnce() async {
        let recorder = MockVoiceMemoRecorder()
        let vm = makeVM(recorder: recorder)
        await vm.startRecording()
        XCTAssertEqual(recorder.startCallCount, 1)
    }

    func test_startRecording_resetsElapsedSeconds() async {
        let recorder = MockVoiceMemoRecorder()
        let vm = makeVM(recorder: recorder)
        await vm.startRecording()
        XCTAssertEqual(vm.elapsedSeconds, 0)
    }

    // MARK: - startRecording — authorization failure

    func test_startRecording_authFailure_setsFailedState() async {
        let recorder = MockVoiceMemoRecorder()
        recorder.authorizeShouldThrow = true
        let vm = makeVM(recorder: recorder)
        await vm.startRecording()
        if case .failed(let msg) = vm.recordingState {
            XCTAssertFalse(msg.isEmpty)
        } else {
            XCTFail("Expected .failed, got \(vm.recordingState)")
        }
    }

    func test_startRecording_authFailure_doesNotCallStart() async {
        let recorder = MockVoiceMemoRecorder()
        recorder.authorizeShouldThrow = true
        let vm = makeVM(recorder: recorder)
        await vm.startRecording()
        XCTAssertEqual(recorder.startCallCount, 0)
    }

    // MARK: - startRecording — recorder start failure

    func test_startRecording_setupFailure_setsFailedState() async {
        let recorder = MockVoiceMemoRecorder()
        recorder.startShouldThrow = true
        let vm = makeVM(recorder: recorder)
        await vm.startRecording()
        if case .failed = vm.recordingState {
            // expected
        } else {
            XCTFail("Expected .failed, got \(vm.recordingState)")
        }
    }

    // MARK: - stopRecording

    func test_stopRecording_transitionsToSaved() async {
        let recorder = MockVoiceMemoRecorder()
        let vm = makeVM(recorder: recorder)
        await vm.startRecording()
        await vm.stopRecording()
        if case .saved = vm.recordingState {
            // expected
        } else {
            XCTFail("Expected .saved, got \(vm.recordingState)")
        }
    }

    func test_stopRecording_savedURLMatchesRecorderOutput() async {
        let expectedURL = FileManager.default.temporaryDirectory.appendingPathComponent("expected.m4a")
        let recorder = MockVoiceMemoRecorder()
        recorder.stubbedURL = expectedURL
        let vm = makeVM(recorder: recorder)
        await vm.startRecording()
        await vm.stopRecording()
        if case .saved(let url) = vm.recordingState {
            XCTAssertEqual(url, expectedURL)
        } else {
            XCTFail("Expected .saved(url:), got \(vm.recordingState)")
        }
    }

    func test_stopRecording_whenIdle_isNoOp() async {
        let recorder = MockVoiceMemoRecorder()
        let vm = makeVM(recorder: recorder)
        // Should not crash or change state.
        await vm.stopRecording()
        XCTAssertEqual(vm.recordingState, .idle)
        XCTAssertEqual(recorder.stopCallCount, 0)
    }

    // MARK: - discard

    func test_discard_resetsToIdle() async {
        let recorder = MockVoiceMemoRecorder()
        let vm = makeVM(recorder: recorder)
        await vm.startRecording()
        await vm.stopRecording()
        vm.discard()
        XCTAssertEqual(vm.recordingState, .idle)
    }

    func test_discard_resetsElapsedSeconds() async {
        let recorder = MockVoiceMemoRecorder()
        let vm = makeVM(recorder: recorder)
        await vm.startRecording()
        vm.elapsedSeconds = 42
        await vm.stopRecording()
        vm.discard()
        XCTAssertEqual(vm.elapsedSeconds, 0)
    }

    func test_discard_whenIdle_isNoOp() {
        let vm = makeVM()
        vm.discard()
        XCTAssertEqual(vm.recordingState, .idle)
    }

    // MARK: - reset

    func test_reset_fromRecording_clearsState() async {
        let recorder = MockVoiceMemoRecorder()
        let vm = makeVM(recorder: recorder)
        await vm.startRecording()
        vm.reset()
        XCTAssertEqual(vm.recordingState, .idle)
        XCTAssertEqual(vm.elapsedSeconds, 0)
    }

    func test_reset_fromFailed_clearsState() async {
        let recorder = MockVoiceMemoRecorder()
        recorder.authorizeShouldThrow = true
        let vm = makeVM(recorder: recorder)
        await vm.startRecording()
        vm.reset()
        XCTAssertEqual(vm.recordingState, .idle)
    }

    // MARK: - Double-start guard

    func test_startRecording_whileAlreadyRecording_isNoOp() async {
        let recorder = MockVoiceMemoRecorder()
        let vm = makeVM(recorder: recorder)
        await vm.startRecording()
        XCTAssertEqual(recorder.startCallCount, 1)
        // Second call while recording — should be ignored.
        await vm.startRecording()
        XCTAssertEqual(recorder.startCallCount, 1, "Second startRecording while recording must be ignored")
    }
}

// MARK: - VoiceMemoErrorTests

final class VoiceMemoErrorTests: XCTestCase {

    func test_notAuthorized_mentionsSettings() {
        let err = VoiceMemoError.notAuthorized
        XCTAssertTrue(
            (err.errorDescription ?? "").localizedCaseInsensitiveContains("settings"),
            "notAuthorized description should mention Settings"
        )
    }

    func test_allCases_haveNonEmptyDescription() {
        let cases: [VoiceMemoError] = [
            .notAuthorized,
            .alreadyRecording,
            .notRecording,
            .setupFailed("test"),
            .playbackFailed("test"),
        ]
        for c in cases {
            XCTAssertFalse(
                (c.errorDescription ?? "").isEmpty,
                "\(c) must have a non-empty errorDescription"
            )
        }
    }

    func test_setupFailed_embeds_reason() {
        let reason = "encoder exploded"
        let err = VoiceMemoError.setupFailed(reason)
        XCTAssertTrue((err.errorDescription ?? "").contains(reason))
    }

    func test_playbackFailed_embeds_reason() {
        let reason = "file not found"
        let err = VoiceMemoError.playbackFailed(reason)
        XCTAssertTrue((err.errorDescription ?? "").contains(reason))
    }
}

// MARK: - VoiceMemoStateTests

final class VoiceMemoStateTests: XCTestCase {

    func test_idle_equalsIdle() {
        XCTAssertEqual(VoiceMemoState.idle, VoiceMemoState.idle)
    }

    func test_requesting_equalsRequesting() {
        XCTAssertEqual(VoiceMemoState.requesting, VoiceMemoState.requesting)
    }

    func test_stopping_equalsStopping() {
        XCTAssertEqual(VoiceMemoState.stopping, VoiceMemoState.stopping)
    }

    func test_saved_equalsSavedWithSameURL() {
        let url = URL(fileURLWithPath: "/tmp/test.m4a")
        XCTAssertEqual(VoiceMemoState.saved(url: url), VoiceMemoState.saved(url: url))
    }

    func test_saved_notEqualsSavedWithDifferentURL() {
        let url1 = URL(fileURLWithPath: "/tmp/a.m4a")
        let url2 = URL(fileURLWithPath: "/tmp/b.m4a")
        XCTAssertNotEqual(VoiceMemoState.saved(url: url1), VoiceMemoState.saved(url: url2))
    }

    func test_failed_equalsFailedWithSameMessage() {
        XCTAssertEqual(VoiceMemoState.failed(message: "x"), VoiceMemoState.failed(message: "x"))
    }

    func test_idle_notEqualsRecording() {
        XCTAssertNotEqual(VoiceMemoState.idle, VoiceMemoState.recording(startedAt: Date()))
    }
}
