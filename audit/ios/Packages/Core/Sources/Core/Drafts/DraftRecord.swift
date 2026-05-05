import Foundation

// §63 Draft recovery — DraftRecord
// Phase 0 foundation

/// Metadata record stored for every saved draft.
/// The raw encoded bytes are stored separately in `DraftStore`; this record
/// exposes enough context to build a "recover a draft" list without decoding
/// the payload.
public struct DraftRecord: Codable, Sendable, Identifiable {
    /// Stable composite key: `"\(screen)|\(entityId ?? "")"`.
    public let id: String
    /// Screen identifier (matches `DraftRecoverable.screenId`).
    public let screen: String
    /// Optional entity ID when editing an existing record.
    public let entityId: String?
    /// When the draft was last saved.
    public let updatedAt: Date
    /// Size of the encoded draft payload in bytes.
    public let bytes: Int

    public init(screen: String, entityId: String?, updatedAt: Date, bytes: Int) {
        self.id = DraftRecord.makeId(screen: screen, entityId: entityId)
        self.screen = screen
        self.entityId = entityId
        self.updatedAt = updatedAt
        self.bytes = bytes
    }

    // MARK: — Helpers

    static func makeId(screen: String, entityId: String?) -> String {
        "\(screen)|\(entityId ?? "")"
    }
}
