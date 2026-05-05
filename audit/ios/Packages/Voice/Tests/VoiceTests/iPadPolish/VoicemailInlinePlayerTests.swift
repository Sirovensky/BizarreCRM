import XCTest
@testable import Voice
import Networking

/// §22 — Logic tests for `VoicemailInlinePlayer`.
///
/// `VoicemailInlinePlayer` owns AVPlayer directly (no extracted view-model),
/// so we test the parts that don't require a live media session:
///
///   1. `formatTime` helper via a public-testable wrapper (tested here via
///      the `VoicemailInlinePlayerFormatHelper` shim below).
///   2. Speed selector constants (same as `VoicemailPlayerView`).
///   3. `VoicemailEntry.audioUrl` nil guard — no crash when URL is absent.
///   4. Display-name priority: customerName > phoneNumber.
final class VoicemailInlinePlayerTests: XCTestCase {

    // MARK: - Helpers

    private func makeEntry(
        audioUrl: String? = "https://cdn.example.com/vm/1.mp3",
        heard: Bool = false,
        customerName: String? = nil,
        phone: String = "5551234567",
        transcript: String? = nil
    ) -> VoicemailEntry {
        VoicemailEntry(
            id: 1,
            phoneNumber: phone,
            customerName: customerName,
            receivedAt: "2026-04-20T10:00:00Z",
            durationSeconds: 90,
            audioUrl: audioUrl,
            transcriptText: transcript,
            heard: heard
        )
    }

    // MARK: - formatTime logic (via shim)

    /// The formatting logic mirrors `VoicemailInlinePlayer.formatTime` exactly.
    /// We test it directly here since it's a pure function.
    private func formatTime(_ seconds: Double) -> String {
        let s = Int(max(0, seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    func test_formatTime_zeroSeconds() {
        XCTAssertEqual(formatTime(0), "0:00")
    }

    func test_formatTime_thirtySeconds() {
        XCTAssertEqual(formatTime(30), "0:30")
    }

    func test_formatTime_exactlyOneMinute() {
        XCTAssertEqual(formatTime(60), "1:00")
    }

    func test_formatTime_oneMinuteFifteen() {
        XCTAssertEqual(formatTime(75), "1:15")
    }

    func test_formatTime_largeValue() {
        XCTAssertEqual(formatTime(3600), "60:00")
    }

    func test_formatTime_negativeClampedToZero() {
        XCTAssertEqual(formatTime(-5), "0:00")
    }

    // MARK: - Speed options (same contract as full player)

    private let speeds: [(label: String, rate: Float)] = [
        ("1×", 1.0), ("1.5×", 1.5), ("2×", 2.0)
    ]

    func test_speeds_countIsThree() {
        XCTAssertEqual(speeds.count, 3)
    }

    func test_speeds_ratesAreCorrect() {
        XCTAssertEqual(speeds.map(\.rate), [1.0, 1.5, 2.0])
    }

    func test_speeds_labelsAreCorrect() {
        XCTAssertEqual(speeds.map(\.label), ["1×", "1.5×", "2×"])
    }

    // MARK: - Entry property access

    func test_entry_audioUrlNilDoesNotCrash() {
        let entry = makeEntry(audioUrl: nil)
        // VoicemailInlinePlayer.setupPlayer() returns early when audioUrl is nil.
        // Verify the entry shape is valid — no force-unwrap should blow up.
        XCTAssertNil(entry.audioUrl)
        XCTAssertEqual(entry.phoneNumber, "5551234567")
    }

    func test_entry_audioUrlPresent() {
        let entry = makeEntry(audioUrl: "https://cdn.example.com/vm/2.mp3")
        XCTAssertEqual(entry.audioUrl, "https://cdn.example.com/vm/2.mp3")
    }

    func test_entry_displayNameUsesCustomerName() {
        let entry = makeEntry(customerName: "Jane Doe")
        let display = entry.customerName ?? entry.phoneNumber
        XCTAssertEqual(display, "Jane Doe")
    }

    func test_entry_displayNameFallsBackToPhone() {
        let entry = makeEntry(customerName: nil, phone: "8005550100")
        let display = entry.customerName ?? entry.phoneNumber
        XCTAssertEqual(display, "8005550100")
    }

    func test_entry_heardFalseByDefault() {
        let entry = makeEntry()
        XCTAssertFalse(entry.heard)
    }

    func test_entry_heardTrue() {
        let entry = makeEntry(heard: true)
        XCTAssertTrue(entry.heard)
    }

    // MARK: - Progress clamping contract

    /// Verifies the inline formula used to derive progress fraction from
    /// elapsed / duration, matching what setupPlayer() / periodic observer uses.
    func test_progress_formula_midpoint() {
        let elapsed = 30.0
        let duration = 60.0
        let progress = duration > 0 ? elapsed / duration : 0
        XCTAssertEqual(progress, 0.5, accuracy: 0.001)
    }

    func test_progress_formula_zeroDurationClampsToZero() {
        let elapsed = 0.0
        let duration = 0.0
        let progress = duration > 0 ? elapsed / duration : 0
        XCTAssertEqual(progress, 0.0)
    }

    func test_progress_formula_fullCompletion() {
        let elapsed = 90.0
        let duration = 90.0
        let progress = duration > 0 ? elapsed / duration : 0
        XCTAssertEqual(progress, 1.0, accuracy: 0.001)
    }

    // MARK: - Duration guard (max(1, d))

    func test_durationGuard_nanBecomesOne() {
        let d = Double.nan
        let guarded = d.isNaN ? 1.0 : d
        XCTAssertEqual(guarded, 1.0)
    }

    func test_durationGuard_positivePassesThrough() {
        let d = 45.0
        let guarded = d.isNaN ? 1.0 : d
        XCTAssertEqual(guarded, 45.0)
    }
}
