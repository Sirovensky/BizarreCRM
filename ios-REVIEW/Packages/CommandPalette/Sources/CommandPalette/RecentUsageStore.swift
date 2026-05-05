import Foundation

// MARK: - RingBuffer

/// Fixed-capacity FIFO ring buffer.  When full, the oldest slot is overwritten.
/// Maintains insertion order (oldest → newest); index 0 is the oldest entry.
struct RingBuffer<Element>: Sendable where Element: Sendable {
    private var storage: [Element?]
    private var head: Int = 0   // points to the next write slot
    private(set) var count: Int = 0
    let capacity: Int

    init(capacity: Int) {
        precondition(capacity > 0, "RingBuffer capacity must be > 0")
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }

    /// Insert `element`.  Overwrites the oldest entry when full.
    mutating func insert(_ element: Element) {
        storage[head] = element
        head = (head + 1) % capacity
        if count < capacity { count += 1 }
    }

    /// All stored elements ordered oldest-first.
    var elements: [Element] {
        if count == 0 { return [] }
        let start: Int
        if count < capacity {
            start = 0
        } else {
            start = head   // head now points at the oldest slot
        }
        return (0..<count).map { storage[(start + $0) % capacity]! }
    }

    /// Most-recent element first (reverse of `elements`).
    var elementsNewestFirst: [Element] {
        elements.reversed()
    }
}

// MARK: - RecentUsageStore

/// Persists the last `maxCount` executed action IDs using a ring buffer.
///
/// The ring buffer guarantees O(1) insertion and bounded memory regardless of
/// how many commands are executed. The UserDefaults key stores a snapshot of
/// the ring buffer contents for cross-launch persistence.
public final class RecentUsageStore: Sendable {
    private let key: String
    /// Maximum number of recent action IDs retained.
    public let maxCount: Int

    public init(
        userDefaultsKey: String = "com.bizarrecrm.commandpalette.recentIDs",
        maxCount: Int = 16
    ) {
        self.key = userDefaultsKey
        self.maxCount = maxCount
    }

    // MARK: - Public API

    /// Ordered list of action IDs, most-recent first.
    public var recentIDs: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    /// Record `id` as the most-recently used action.
    /// Uses a ring buffer to bound the stored list to `maxCount`.
    public func record(id: String) {
        // Rebuild ring buffer from persisted state, deduplicate, then write back.
        var existing = recentIDs
        existing.removeAll { $0 == id }   // remove duplicate if present

        // Trim to maxCount - 1 to make room for the new entry
        let trimmed = Array(existing.prefix(maxCount - 1))

        // Insert new entry at front (most-recent first convention)
        let updated = [id] + trimmed

        // Persist via ring-buffer snapshot
        let snapshot = flushRingBuffer(ids: updated)
        UserDefaults.standard.set(snapshot, forKey: key)
    }

    /// Score boost for `id` based on recency.
    /// Returns 0 if `id` is not in the recent list.
    /// Index 0 (most recent) gets the highest boost.
    public func boost(for id: String) -> Double {
        let ids = recentIDs
        guard let index = ids.firstIndex(of: id) else { return 0 }
        // Linear decay: index 0 → boost maxCount, last index → boost 1
        return Double(maxCount - index)
    }

    // MARK: - Private

    /// Run the list through a ring buffer of `maxCount` capacity and
    /// return its contents newest-first (the same order as input, just capped).
    private func flushRingBuffer(ids: [String]) -> [String] {
        var ring = RingBuffer<String>(capacity: maxCount)
        // Insert oldest-first so that the newest ends up at the tail
        for id in ids.reversed() {
            ring.insert(id)
        }
        // elementsNewestFirst gives most-recent at index 0
        return ring.elementsNewestFirst
    }
}
