import Foundation

// MARK: - TeamChatAttachment
//
// §14.5 Image / file attachment — server has no first-class attachment columns
// on `team_chat_messages` yet (§74 gap). Until it does, attachments are
// uploaded through the existing generic uploads pipeline (`/uploads/...`)
// and a sentinel marker is appended to the message body in the form
//
//     [[attach:<absolute-or-relative-url>|<mime>|<filename>]]
//
// The marker round-trips because the server stores the `body` as-is.
// Renderers extract the marker and present the file inline; if the marker
// is malformed it's shown as plain text and the message is still readable.

public struct TeamChatAttachment: Hashable, Sendable {
    public let url: String
    public let mimeType: String
    public let fileName: String

    public init(url: String, mimeType: String, fileName: String) {
        self.url = url; self.mimeType = mimeType; self.fileName = fileName
    }

    public var isImage: Bool { mimeType.hasPrefix("image/") }
}

public enum TeamChatAttachmentEncoder {
    public static let prefix = "[[attach:"
    public static let suffix = "]]"

    /// Appends a marker to `body` (with a leading newline if body is non-empty).
    public static func encode(body: String, attachment: TeamChatAttachment) -> String {
        let marker = "\(prefix)\(attachment.url)|\(attachment.mimeType)|\(attachment.fileName)\(suffix)"
        if body.isEmpty { return marker }
        return body + "\n" + marker
    }

    /// Splits a stored body into its visible-text portion and any attachments.
    /// Order of attachments is preserved.
    public static func decode(body: String) -> (text: String, attachments: [TeamChatAttachment]) {
        var attachments: [TeamChatAttachment] = []
        var rest = body
        // Iterate to extract every marker. Cap iterations defensively.
        for _ in 0..<10 {
            guard let range = rest.range(of: prefix) else { break }
            guard let endRange = rest.range(of: suffix, range: range.upperBound..<rest.endIndex) else { break }
            let inner = rest[range.upperBound..<endRange.lowerBound]
            let parts = inner.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            if parts.count == 3 {
                attachments.append(TeamChatAttachment(
                    url: parts[0], mimeType: parts[1], fileName: parts[2]
                ))
            }
            rest.removeSubrange(range.lowerBound..<endRange.upperBound)
        }
        let text = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text, attachments)
    }
}
