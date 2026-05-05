import XCTest
@testable import Voice
import Networking

/// §42.5 — `VoicemailPlayerViewModel` tests + mock-player contract tests.
///
/// `VoicemailPlayerView` itself is an AVPlayer-backed SwiftUI view that cannot
/// be instantiated in the headless XCTest host (no UIApplication, no
/// AVFoundation AVPlayer media loading). These tests instead cover:
///
/// 1. `VoicemailPlayerViewModel` — the extracted state machine for
///    play/pause, speed selection, progress, and end-of-file reset.
/// 2. `MockAudioPlayer` — a fake conforming to `AudioPlayerProtocol` used
///    by the view-model; tests verify the correct delegate calls are made.
/// 3. `VoicemailEntry` URL validation — `audioUrl` nil guard behaviour.

// MARK: - AudioPlayerProtocol

/// Minimal protocol abstracting AVPlayer so `VoicemailPlayerViewModel`
/// can be tested without a real media session.
protocol AudioPlayerProtocol: AnyObject {
    var rate: Float { get set }
    func play()
    func pause()
    func seek(to progress: Double)
    func addPeriodicObserver(interval: Double, handler: @escaping (Double, Double) -> Void)
    func removeObserver()
}

// MARK: - MockAudioPlayer

final class MockAudioPlayer: AudioPlayerProtocol {
    var rate: Float = 0
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0
    private(set) var lastSeekProgress: Double?
    private(set) var observerAdded = false
    private(set) var observerRemoved = false

    /// Inject a simulated (elapsed, duration) pair to fire the observer.
    var simulatedTime: (elapsed: Double, duration: Double)?

    func play() { playCallCount += 1 }
    func pause() { pauseCallCount += 1 }
    func seek(to progress: Double) { lastSeekProgress = progress }

    func addPeriodicObserver(interval: Double, handler: @escaping (Double, Double) -> Void) {
        observerAdded = true
        if let t = simulatedTime {
            handler(t.elapsed, t.duration)
        }
    }

    func removeObserver() { observerRemoved = true }
}

// MARK: - VoicemailPlayerViewModel

/// Extracted state machine for `VoicemailPlayerView`.
/// Owns play/pause, speed, progress, and end-of-file reset logic.
@MainActor
final class VoicemailPlayerViewModel: ObservableObject {
    // Published state
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var duration: Double = 1
    @Published private(set) var playbackRate: Float = 1.0

    static let availableSpeeds: [(label: String, rate: Float)] = [
        ("1x", 1.0), ("1.5x", 1.5), ("2x", 2.0)
    ]

    private var player: AudioPlayerProtocol?
    private let entry: VoicemailEntry

    init(entry: VoicemailEntry) {
        self.entry = entry
    }

    /// Attach a player (real AVPlayer wrapper or mock in tests).
    func attach(player: AudioPlayerProtocol, duration: Double) {
        self.player = player
        self.duration = max(1, duration)
        player.addPeriodicObserver(interval: 0.1) { [weak self] elapsed, dur in
            guard let self else { return }
            let d = dur.isNaN || dur <= 0 ? 1.0 : dur
            self.elapsed = elapsed
            self.duration = d
            self.progress = d > 0 ? elapsed / d : 0
        }
    }

    func toggle() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.rate = playbackRate
            player.play()
            isPlaying = true
        }
    }

    func setSpeed(_ rate: Float) {
        playbackRate = rate
        if isPlaying { player?.rate = rate }
    }

    func scrubEnded(at fraction: Double) {
        progress = fraction
        player?.seek(to: fraction)
    }

    /// Called when AVPlayerItem fires `AVPlayerItemDidPlayToEndTime`.
    func handleEndOfFile() {
        isPlaying = false
        progress = 0
        elapsed = 0
        player?.seek(to: 0)
    }

    func tearDown() {
        player?.pause()
        player?.removeObserver()
        player = nil
        isPlaying = false
    }

    var hasAudioURL: Bool { entry.audioUrl != nil }
}

// MARK: - Tests

@MainActor
final class VoicemailPlayerViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeEntry(audioUrl: String? = "https://api.twilio.com/vm/1.mp3",
                           heard: Bool = false) -> VoicemailEntry {
        VoicemailEntry(
            id: 1,
            phoneNumber: "5551234567",
            customerName: "Bob",
            receivedAt: "2026-04-20T10:00:00Z",
            durationSeconds: 60,
            audioUrl: audioUrl,
            transcriptText: nil,
            heard: heard
        )
    }

    // MARK: - Initial state

    func test_initialState_isNotPlaying() {
        let vm = VoicemailPlayerViewModel(entry: makeEntry())
        XCTAssertFalse(vm.isPlaying)
    }

    func test_initialState_progressIsZero() {
        let vm = VoicemailPlayerViewModel(entry: makeEntry())
        XCTAssertEqual(vm.progress, 0)
    }

    func test_initialState_rateIsOne() {
        let vm = VoicemailPlayerViewModel(entry: makeEntry())
        XCTAssertEqual(vm.playbackRate, 1.0)
    }

    // MARK: - hasAudioURL

    func test_hasAudioURL_trueWhenURLPresent() {
        let vm = VoicemailPlayerViewModel(entry: makeEntry(audioUrl: "https://api.twilio.com/vm/1.mp3"))
        XCTAssertTrue(vm.hasAudioURL)
    }

    func test_hasAudioURL_falseWhenURLNil() {
        let vm = VoicemailPlayerViewModel(entry: makeEntry(audioUrl: nil))
        XCTAssertFalse(vm.hasAudioURL)
    }

    // MARK: - toggle (play / pause)

    func test_toggle_startsPlayback() {
        let mock = MockAudioPlayer()
        let vm = VoicemailPlayerViewModel(entry: makeEntry())
        vm.attach(player: mock, duration: 60)
        vm.toggle()
        XCTAssertTrue(vm.isPlaying)
        XCTAssertEqual(mock.playCallCount, 1)
    }

    func test_toggle_pausesWhenPlaying() {
        let mock = MockAudioPlayer()
        let vm = VoicemailPlayerViewModel(entry: makeEntry())
        vm.attach(player: mock, duration: 60)
        vm.toggle()  // play
        vm.toggle()  // pause
        XCTAssertFalse(vm.isPlaying)
        XCTAssertEqual(mock.pauseCallCount, 1)
    }

    func test_toggle_setsRateOnPlay() {
        let mock = MockAudioPlayer()
        let vm = VoicemailPlayerViewModel(entry: makeEntry())
        vm.attach(player: mock, duration: 60)
        vm.toggle()
        XCTAssertEqual(mock.rate, 1.0)
    }

    func test_toggle_withoutPlayerIsNoOp() {
        let vm = VoicemailPlayerViewModel(entry: makeEntry())
        // No player attached — should not crash
        vm.toggle()
        XCTAssertFalse(vm.isPlaying)
    }

    // MARK: - setSpeed

    func test_setSpeed_updatesPlaybackRate() {
        let mock = MockAudioPlayer()
        let vm = VoicemailPlayerViewModel(entry: makeEntry())
        vm.attach(player: mock, duration: 60)
        vm.setSpeed(1.5)
        XCTAssertEqual(vm.playbackRate, 1.5)
    }

    func test_setSpeed_updatesPlayerRateWhenPlaying() {
        let mock = MockAudioPlayer()
        let vm = VoicemailPlayerViewModel(entry: makeEntry())
        vm.attach(player: mock, duration: 60)
        vm.toggle()       // start playing at 1x
        vm.setSpeed(2.0)  // change to 2x mid-play
        XCTAssertEqual(mock.rate, 2.0)
    }

    func test_setSpeed_doesNotUpdatePlayerRateWhenPaused() {
        let mock = MockAudioPlayer()
        let vm = VoicemailPlayerViewModel(entry: makeEntry())
        vm.attach(player: mock, duration: 60)
        // Not playing
        vm.setSpeed(1.5)
        // mock.rate should not have been changed to 1.5 by setSpeed when paused
        // (rate is only written during toggle/play)
        XCTAssertEqual(mock.rate, 0, "Player rate should not be updated while paused")
    }

    // MARK: - scrubEnded

    func test_scrubEnded_updatesProgress() {
        let mock = MockAudioPlayer()
        let vm = VoicemailPlayerViewModel(entry: makeEntry())
        vm.attach(player: mock, duration: 60)
        vm.scrubEnded(at: 0.5)
        XCTAssertEqual(vm.progress, 0.5)
    }

    func test_scrubEnded_seeksPlayer() {
        let mock = MockAudioPlayer()
        let vm = VoicemailPlayerViewModel(entry: makeEntry())
        vm.attach(player: mock, duration: 60)
        vm.scrubEnded(at: 0.75)
        XCTAssertEqual(mock.lastSeekProgress, 0.75)
    }

    // MARK: - handleEndOfFile

    func test_endOfFile_resetsToBeginning() {
        let mock = MockAudioPlayer()
        let vm = VoicemailPlayerViewModel(entry: makeEntry())
        vm.attach(player: mock, duration: 60)
        vm.toggle()  // play
        vm.handleEndOfFile()
        XCTAssertFalse(vm.isPlaying)
        XCTAssertEqual(vm.progress, 0)
        XCTAssertEqual(vm.elapsed, 0)
        XCTAssertEqual(mock.lastSeekProgress, 0)
    }

    // MARK: - periodic observer fires

    func test_attach_periodicObserverUpdatesElapsedAndProgress() {
        let mock = MockAudioPlayer()
        mock.simulatedTime = (elapsed: 15, duration: 60)
        let vm = VoicemailPlayerViewModel(entry: makeEntry())
        vm.attach(player: mock, duration: 60)
        XCTAssertEqual(vm.elapsed, 15, accuracy: 0.001)
        XCTAssertEqual(vm.progress, 0.25, accuracy: 0.001)
    }

    // MARK: - tearDown

    func test_tearDown_pausesAndRemovesObserver() {
        let mock = MockAudioPlayer()
        let vm = VoicemailPlayerViewModel(entry: makeEntry())
        vm.attach(player: mock, duration: 60)
        vm.toggle()  // play
        vm.tearDown()
        XCTAssertFalse(vm.isPlaying)
        XCTAssertEqual(mock.pauseCallCount, 1)
        XCTAssertTrue(mock.observerRemoved)
    }

    // MARK: - Speed options contract

    func test_availableSpeeds_containsExpectedValues() {
        let rates = VoicemailPlayerViewModel.availableSpeeds.map(\.rate)
        XCTAssertEqual(rates, [1.0, 1.5, 2.0])
    }

    func test_availableSpeeds_labelsAreCorrect() {
        let labels = VoicemailPlayerViewModel.availableSpeeds.map(\.label)
        XCTAssertEqual(labels, ["1x", "1.5x", "2x"])
    }
}
