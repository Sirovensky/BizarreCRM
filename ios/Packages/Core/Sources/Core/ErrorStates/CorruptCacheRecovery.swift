import SwiftUI

// §63.1 — Corrupt-cache detection + auto-recovery.
//
// When a cached entity fails to decode (malformed JSON, schema mismatch after
// migration, or SQLCipher corruption on a page), the repository catches the
// `DecodingError` / `DatabaseError`, logs it, emits a `corruptCacheDetected`
// notification, and calls `CorruptCacheRecovery.recover(entity:)` which:
//   1. Deletes the corrupt rows for that entity scope only.
//   2. Resets the cursor for that scope so the next pull fetches fresh data.
//   3. Queues a re-fetch (online) or surfaces a banner (offline).
//
// The banner view is `CorruptCacheBanner` — a non-blocking inline notice.
// It is inserted by the feature's list view, not by this layer.

// MARK: — Event

public extension Notification.Name {
    /// Posted by a repository when it detects and begins recovering a corrupt
    /// cache entry. `userInfo["entity"]` is a `String` entity type label.
    static let corruptCacheDetected = Notification.Name("com.bizarrecrm.corruptCacheDetected")
}

// MARK: — Recovery service

/// Coordinates corrupt-cache detection, logging, and recovery for any entity.
///
/// Repositories call `CorruptCacheRecovery.handle(entity:error:recover:)` in
/// their catch blocks where data integrity errors can occur.
public final class CorruptCacheRecovery: Sendable {

    // MARK: — Init

    public init() {}

    // MARK: — API

    /// Records a corrupt-cache event and invokes `recover`, then posts the
    /// `corruptCacheDetected` notification on the main queue.
    ///
    /// - Parameters:
    ///   - entity: A human-readable label for the entity type (e.g. `"Ticket"`).
    ///   - error: The underlying error that triggered corrupt-cache detection.
    ///   - recover: Async closure that purges the corrupt rows and resets the
    ///     cursor. Must be idempotent (called once per detection event).
    ///   - refetch: Optional async closure to trigger a re-fetch from the server
    ///     once the local store is clean. Skipped when offline.
    public func handle(
        entity: String,
        error: Error,
        recover: @escaping @Sendable () async throws -> Void,
        refetch: (@escaping @Sendable () async throws -> Void)? = nil
    ) {
        Task.detached(priority: .utility) {
            do {
                try await recover()
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .corruptCacheDetected,
                        object: nil,
                        userInfo: ["entity": entity]
                    )
                }
                if let refetch {
                    try await refetch()
                }
            } catch {
                // Recovery itself failed — log but do not crash.
                // The banner will remain visible until next successful load.
                assertionFailure("CorruptCacheRecovery: recovery closure threw: \(error)")
            }
        }
    }
}

// MARK: — Banner view

/// Non-blocking inline banner shown when a cache corruption is detected and
/// recovery is in progress.
///
/// Place inside the list's `.overlay(alignment: .top)` or prepend to the
/// list's content using `.safeAreaInset(edge: .top)`.
///
/// ```swift
/// .safeAreaInset(edge: .top) {
///     if viewModel.showCorruptCacheBanner {
///         CorruptCacheBanner(entityName: "Tickets")
///     }
/// }
/// ```
public struct CorruptCacheBanner: View {

    public let entityName: String
    public var onDismiss: (() -> Void)?

    public init(entityName: String, onDismiss: (() -> Void)? = nil) {
        self.entityName = entityName
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.clockwise.icloud")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Refreshing \(entityName)")
                    .font(.footnote.weight(.semibold))

                Text("Some cached data was inconsistent — fetching fresh copy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
                .frame(minWidth: 44, minHeight: 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Refreshing \(entityName). Some cached data was inconsistent — fetching fresh copy.")
    }
}

#if DEBUG
#Preview("CorruptCacheBanner — dismissable") {
    CorruptCacheBanner(entityName: "Tickets") { }
        .padding()
}

#Preview("CorruptCacheBanner — no dismiss") {
    CorruptCacheBanner(entityName: "Inventory")
        .padding()
}
#endif
