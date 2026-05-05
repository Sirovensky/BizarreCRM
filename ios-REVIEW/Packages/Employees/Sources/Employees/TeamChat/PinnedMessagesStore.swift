import Foundation

// MARK: - PinnedMessagesStore
//
// §14.5 Pin messages — local persistence until the server adds an
// `is_pinned` column on `team_chat_messages` (filed §74). Per-channel set of
// message ids stored under a versioned UserDefaults key. Cross-device sync
// is intentionally out of scope here — it follows server-side support.

public protocol PinnedMessagesStore: Sendable {
    func pinnedIds(channelId: Int64) -> Set<Int64>
    func togglePin(channelId: Int64, messageId: Int64) -> Bool
    func clearAll(channelId: Int64)
}

public final class UserDefaultsPinnedMessagesStore: PinnedMessagesStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()
    private static let prefix = "teamChat.pinned.v1."

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(for channelId: Int64) -> String {
        "\(Self.prefix)\(channelId)"
    }

    public func pinnedIds(channelId: Int64) -> Set<Int64> {
        lock.lock(); defer { lock.unlock() }
        guard let raw = defaults.array(forKey: key(for: channelId)) as? [NSNumber] else {
            return []
        }
        return Set(raw.map { $0.int64Value })
    }

    /// Returns true if message is now pinned, false if unpinned.
    public func togglePin(channelId: Int64, messageId: Int64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var set = Set((defaults.array(forKey: key(for: channelId)) as? [NSNumber])?.map { $0.int64Value } ?? [])
        let nowPinned: Bool
        if set.contains(messageId) {
            set.remove(messageId)
            nowPinned = false
        } else {
            set.insert(messageId)
            nowPinned = true
        }
        defaults.set(set.map { NSNumber(value: $0) }, forKey: key(for: channelId))
        return nowPinned
    }

    public func clearAll(channelId: Int64) {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: key(for: channelId))
    }
}
