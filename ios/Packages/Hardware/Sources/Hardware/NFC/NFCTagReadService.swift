import Foundation
import Core

#if canImport(CoreNFC)
import CoreNFC
#endif

// MARK: - NFC tag read service
//
// §17.5 — "Core NFC read" — scan a tag whose payload is a device serial /
// IMEI / inventory id and return it as a string. Caller (Tickets intake,
// Inventory edit, Customer device picker) decides what to do with the value.
//
// This service is a deliberately thin wrapper around `NFCNDEFReaderSession`:
//   • Single-read sessions (`invalidateAfterFirstRead = true`) — matches the
//     "tap a tag → fill a field" interaction we ship today.
//   • Returns the first NDEF text/URI record's payload, lower-cased + trimmed.
//   • Throws `NFCReadError.unsupported` if the runtime says NFC is off — the
//     UI must always pre-check `NFCAvailabilityService.shared.isAvailable`,
//     but this is a defence-in-depth.
//
// Write-path is intentionally NOT implemented in this batch — server schema
// for `nfc_tag_id` is blocked behind NFC-PARITY-001.

public enum NFCReadError: Error, LocalizedError, Sendable {
    case unsupported
    case sessionInvalidated(String)
    case noPayload
    case userCancelled

    public var errorDescription: String? {
        switch self {
        case .unsupported:
            return "NFC isn't available on this device. See Settings → Hardware → NFC."
        case .sessionInvalidated(let reason):
            return reason
        case .noPayload:
            return "The tag was empty or contained no readable text."
        case .userCancelled:
            return "Scan cancelled."
        }
    }
}

/// Result returned to the caller after a successful single-tag read.
public struct NFCReadResult: Sendable, Equatable {
    public let payload: String
    public let format: NFCTagFormat

    public init(payload: String, format: NFCTagFormat) {
        self.payload = payload
        self.format = format
    }
}

#if canImport(CoreNFC)

/// Concrete reader. Holds onto the session delegate for the lifetime of the
/// scan via a continuation; the delegate is detached as soon as the
/// continuation is resumed.
public final class NFCTagReadService: NSObject, @unchecked Sendable {

    public static let shared = NFCTagReadService()

    private var activeDelegate: SessionDelegate?

    public override init() {}

    /// Begin a one-shot tag read. Throws if NFC is unavailable on the device.
    /// The caller is expected to `await` and present any returned payload as
    /// a form-field fill on the main actor.
    public func readNDEF(prompt: String = "Hold the tag near the top of your device.") async throws -> NFCReadResult {
        guard NFCNDEFReaderSession.readingAvailable else { throw NFCReadError.unsupported }

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = SessionDelegate(continuation: continuation) { [weak self] in
                self?.activeDelegate = nil
            }
            self.activeDelegate = delegate
            let session = NFCNDEFReaderSession(delegate: delegate, queue: nil, invalidateAfterFirstRead: true)
            session.alertMessage = prompt
            delegate.session = session
            session.begin()
        }
    }

    // MARK: - Delegate

    private final class SessionDelegate: NSObject, NFCNDEFReaderSessionDelegate, @unchecked Sendable {
        private var continuation: CheckedContinuation<NFCReadResult, Error>?
        private let onFinish: () -> Void
        weak var session: NFCNDEFReaderSession?

        init(continuation: CheckedContinuation<NFCReadResult, Error>, onFinish: @escaping () -> Void) {
            self.continuation = continuation
            self.onFinish = onFinish
        }

        func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
            for message in messages {
                for record in message.records {
                    if let payload = decodePayload(record) {
                        finish(.success(NFCReadResult(payload: payload, format: .ndef)))
                        session.invalidate()
                        return
                    }
                }
            }
            finish(.failure(NFCReadError.noPayload))
            session.invalidate(errorMessage: "No readable text on this tag.")
        }

        func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
            // First-read sessions invalidate after success — only emit if continuation still pending.
            if let nfcError = error as? NFCReaderError {
                switch nfcError.code {
                case .readerSessionInvalidationErrorUserCanceled,
                     .readerSessionInvalidationErrorFirstNDEFTagRead:
                    finish(.failure(NFCReadError.userCancelled))
                    return
                default:
                    break
                }
            }
            finish(.failure(NFCReadError.sessionInvalidated(error.localizedDescription)))
        }

        // Required by some SDK versions even though we don't use multi-tag detection.
        func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {}

        // MARK: - Helpers

        private func decodePayload(_ record: NFCNDEFPayload) -> String? {
            // URI record — most inventory stickers are written as URIs.
            if let url = record.wellKnownTypeURIPayload() {
                return url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // Text record — first byte is status, then ISO language code, then text.
            let (textOpt, _) = record.wellKnownTypeTextPayload()
            if let text = textOpt, !text.isEmpty {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // Fallback: raw payload as UTF-8.
            if let text = String(data: record.payload, encoding: .utf8) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            return nil
        }

        private func finish(_ result: Result<NFCReadResult, Error>) {
            guard let cont = continuation else { return }
            continuation = nil
            cont.resume(with: result)
            onFinish()
        }
    }
}

#else

// Mac / non-iOS builds — service is a stub that always throws `.unsupported`.
public final class NFCTagReadService: @unchecked Sendable {
    public static let shared = NFCTagReadService()
    public init() {}
    public func readNDEF(prompt: String = "") async throws -> NFCReadResult {
        throw NFCReadError.unsupported
    }
}

#endif
