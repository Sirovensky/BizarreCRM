import XCTest
import Speech
@testable import Voice

// §42.5 — Voicemail transcription pipeline tests

final class VoicemailTranscriptionTests: XCTestCase {

    // MARK: - TranscriptionError

    func testTranscriptionError_permissionDenied_hasDescription() {
        let error = TranscriptionError.permissionDenied
        XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
        XCTAssertTrue(error.errorDescription?.lowercased().contains("permission") ?? false)
    }

    func testTranscriptionError_unsupportedLocale_includesLocaleId() {
        let error = TranscriptionError.unsupportedLocale("fr-BE")
        XCTAssertTrue(error.errorDescription?.contains("fr-BE") ?? false)
    }

    func testTranscriptionError_recognitionFailed_includesDetail() {
        let error = TranscriptionError.recognitionFailed("no internet")
        XCTAssertTrue(error.errorDescription?.contains("no internet") ?? false)
    }

    func testTranscriptionError_audioFileUnreadable_includesPath() {
        let error = TranscriptionError.audioFileUnreadable("/tmp/missing.m4a")
        XCTAssertTrue(error.errorDescription?.contains("/tmp/missing.m4a") ?? false)
    }

    // MARK: - VoicemailTranscriptionService — permission status

    func testTranscriptionService_permissionStatus_isAccessible() async {
        let service = VoicemailTranscriptionService()
        // currentPermissionStatus is actor-isolated; actor hop needed.
        let status = await service.currentPermissionStatus
        // In unit test context, status will be .notDetermined (never authorised in CI).
        // We just confirm the call doesn't crash and returns a valid enum case.
        let validStatuses: [SFSpeechRecognizerAuthorizationStatus] = [
            .notDetermined, .denied, .restricted, .authorized
        ]
        XCTAssertTrue(validStatuses.contains(status))
    }
}
