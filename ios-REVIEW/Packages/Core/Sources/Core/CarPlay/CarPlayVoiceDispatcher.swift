#if canImport(CarPlay)
import CarPlay
import Foundation

// MARK: - CarPlayVoiceCommand

/// A strongly-typed voice command that the CarPlay voice dispatcher can handle.
///
/// Commands are value types so they can be compared in unit tests without
/// spinning up a real voice-recognition stack.
public enum CarPlayVoiceCommand: Sendable, Equatable {

    /// Place a call to the named contact (e.g. "call John").
    case callContact(name: String)

    /// Open the ticket with the supplied identifier (e.g. "open ticket 42").
    case openTicket(id: String)

    /// Show the voicemail inbox.
    case showVoicemail

    /// Show the recent-calls log.
    case showCallLog

    /// An unrecognised or ambiguous command with the raw transcription.
    case unrecognised(transcript: String)
}

// MARK: - CarPlayVoiceDispatcherResult

/// The outcome returned by ``CarPlayVoiceDispatcher/handle(_:)`` after processing
/// a voice command.
public enum CarPlayVoiceDispatcherResult: Sendable, Equatable {

    /// The command was handled and navigation should proceed to `destination`.
    case navigated(to: DeepLinkDestination)

    /// The command was understood but cannot be resolved without more context
    /// (e.g. "call John" matched multiple contacts). `hint` surfaces a
    /// disambiguation message suitable for CarPlay's alert template.
    case needsDisambiguation(hint: String)

    /// The command was not recognised. `feedback` is a short string that
    /// the UI layer can speak back via CarPlay's voice feedback channel.
    case notHandled(feedback: String)
}

// MARK: - CarPlayVoiceDispatcher

/// Processes ``CarPlayVoiceCommand`` values produced by a speech-recognition
/// pipeline and maps them to navigation outcomes.
///
/// Implementors are expected to be actor-isolated or otherwise thread-safe —
/// CarPlay callbacks can arrive on background queues.
///
/// ## Example
/// ```swift
/// let result = await dispatcher.handle(.callContact(name: "Alice"))
/// switch result {
/// case .navigated(let dest):    router.navigate(to: dest)
/// case .needsDisambiguation:    showDisambiguationAlert()
/// case .notHandled(let msg):    speakFeedback(msg)
/// }
/// ```
public protocol CarPlayVoiceDispatcher: Sendable {

    /// Handle the given `command` and return a ``CarPlayVoiceDispatcherResult``.
    ///
    /// - Parameter command: The parsed voice command.
    /// - Returns: The resolution outcome.
    func handle(_ command: CarPlayVoiceCommand) async -> CarPlayVoiceDispatcherResult

    /// The tenant slug used when constructing deep-link destinations.
    var tenantSlug: String { get }
}

#endif // canImport(CarPlay)
