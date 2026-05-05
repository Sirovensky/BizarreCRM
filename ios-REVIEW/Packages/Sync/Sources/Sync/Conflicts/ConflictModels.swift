import Foundation

// Ground truth: packages/server/src/routes/syncConflicts.routes.ts
//   GET  /api/v1/sync/conflicts             → paginated list
//   GET  /api/v1/sync/conflicts/:id         → single conflict detail
//   POST /api/v1/sync/conflicts/:id/resolve → { resolution, resolution_notes }
//
// Envelope: { success: Bool, data: T?, message: String? }

// MARK: - ConflictType

/// Maps to the `conflict_type` column on the server.
public enum ConflictType: String, Decodable, Sendable, CaseIterable {
    case concurrentUpdate = "concurrent_update"
    case staleWrite       = "stale_write"
    case duplicateCreate  = "duplicate_create"
    case deletedRemote    = "deleted_remote"

    /// Human-readable label for display.
    public var displayName: String {
        switch self {
        case .concurrentUpdate: return "Concurrent Update"
        case .staleWrite:       return "Stale Write"
        case .duplicateCreate:  return "Duplicate Create"
        case .deletedRemote:    return "Deleted on Server"
        }
    }
}

// MARK: - ConflictStatus

/// Maps to the `status` column on the server.
public enum ConflictStatus: String, Decodable, Sendable, CaseIterable {
    case pending  = "pending"
    case resolved = "resolved"
    case rejected = "rejected"
    case deferred = "deferred"

    public var displayName: String {
        rawValue.capitalized
    }

    /// Whether the conflict is in a terminal state (no further action required).
    public var isTerminal: Bool {
        self == .resolved || self == .rejected
    }
}

// MARK: - Resolution

/// Maps to the `resolution` column on the server.
public enum Resolution: String, Encodable, Sendable, CaseIterable {
    case keepClient = "keep_client"
    case keepServer = "keep_server"
    case merge      = "merge"
    case manual     = "manual"
    case rejected   = "rejected"

    public var displayName: String {
        switch self {
        case .keepClient: return "Keep Local"
        case .keepServer: return "Keep Server"
        case .merge:      return "Merge"
        case .manual:     return "Manual"
        case .rejected:   return "Rejected"
        }
    }
}

// MARK: - ConflictField

/// A single diffed field extracted from the local vs server JSON blobs.
/// Created client-side by comparing `clientVersionJson` and `serverVersionJson`.
public struct ConflictField: Identifiable, Sendable, Equatable {
    public let id: String          // field key, e.g. "status", "notes"
    public let key: String
    public let localValue: String?
    public let serverValue: String?

    /// Whether the two values actually differ.
    public var isDifferent: Bool {
        localValue != serverValue
    }

    public init(key: String, localValue: String?, serverValue: String?) {
        self.id = key
        self.key = key
        self.localValue = localValue
        self.serverValue = serverValue
    }
}

// MARK: - ConflictSide

/// Identifies which side of a conflict is being referenced.
public enum ConflictSide: String, Sendable {
    case local  = "local"
    case server = "server"

    public var displayName: String {
        switch self {
        case .local:  return "Local (Your Changes)"
        case .server: return "Server (Remote Version)"
        }
    }
}

// MARK: - ConflictItem

/// A single sync conflict record returned by `GET /api/v1/sync/conflicts` or
/// `GET /api/v1/sync/conflicts/:id`.
///
/// Server column mapping:
///   id, entity_kind, entity_id, conflict_type, status, resolution,
///   resolution_notes, reporter_user_id, reporter_device_id, reporter_platform,
///   reported_at, resolved_by_user_id, resolved_at,
///   reporter_first_name, reporter_last_name,
///   resolver_first_name, resolver_last_name,
///   client_version_json, server_version_json  (detail only)
public struct ConflictItem: Identifiable, Sendable {
    public let id: Int
    public let entityKind: String
    public let entityId: Int
    public let conflictType: ConflictType
    public let status: ConflictStatus
    public let resolution: Resolution?
    public let resolutionNotes: String?
    public let reporterUserId: Int?
    public let reporterDeviceId: String?
    public let reporterPlatform: String?
    public let reportedAt: String
    public let resolvedByUserId: Int?
    public let resolvedAt: String?
    public let reporterFirstName: String?
    public let reporterLastName: String?
    public let resolverFirstName: String?
    public let resolverLastName: String?
    /// Raw JSON blob for the local version — only present in detail responses.
    public let clientVersionJson: String?
    /// Raw JSON blob for the server version — only present in detail responses.
    public let serverVersionJson: String?

    // MARK: Computed helpers

    public var reporterDisplayName: String {
        let parts = [reporterFirstName, reporterLastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        guard !parts.isEmpty else { return "User \(reporterUserId ?? 0)" }
        return parts.joined(separator: " ")
    }

    public var resolverDisplayName: String? {
        let parts = [resolverFirstName, resolverLastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        guard !parts.isEmpty else { return resolvedByUserId.map { "User \($0)" } }
        return parts.joined(separator: " ")
    }

    /// Diff the two JSON blobs into a flat list of `ConflictField`s.
    /// Returns an empty array when version JSON is unavailable (list-level items).
    public var diffedFields: [ConflictField] {
        guard
            let clientRaw = clientVersionJson,
            let serverRaw = serverVersionJson,
            let clientData = clientRaw.data(using: .utf8),
            let serverData = serverRaw.data(using: .utf8),
            let clientDict = (try? JSONSerialization.jsonObject(with: clientData)) as? [String: Any],
            let serverDict = (try? JSONSerialization.jsonObject(with: serverData)) as? [String: Any]
        else { return [] }

        let allKeys = Set(clientDict.keys).union(Set(serverDict.keys)).sorted()
        return allKeys.map { key in
            ConflictField(
                key: key,
                localValue: clientDict[key].map { "\($0)" },
                serverValue: serverDict[key].map { "\($0)" }
            )
        }
    }

    // MARK: Init

    public init(
        id: Int,
        entityKind: String,
        entityId: Int,
        conflictType: ConflictType,
        status: ConflictStatus,
        resolution: Resolution? = nil,
        resolutionNotes: String? = nil,
        reporterUserId: Int? = nil,
        reporterDeviceId: String? = nil,
        reporterPlatform: String? = nil,
        reportedAt: String,
        resolvedByUserId: Int? = nil,
        resolvedAt: String? = nil,
        reporterFirstName: String? = nil,
        reporterLastName: String? = nil,
        resolverFirstName: String? = nil,
        resolverLastName: String? = nil,
        clientVersionJson: String? = nil,
        serverVersionJson: String? = nil
    ) {
        self.id = id
        self.entityKind = entityKind
        self.entityId = entityId
        self.conflictType = conflictType
        self.status = status
        self.resolution = resolution
        self.resolutionNotes = resolutionNotes
        self.reporterUserId = reporterUserId
        self.reporterDeviceId = reporterDeviceId
        self.reporterPlatform = reporterPlatform
        self.reportedAt = reportedAt
        self.resolvedByUserId = resolvedByUserId
        self.resolvedAt = resolvedAt
        self.reporterFirstName = reporterFirstName
        self.reporterLastName = reporterLastName
        self.resolverFirstName = resolverFirstName
        self.resolverLastName = resolverLastName
        self.clientVersionJson = clientVersionJson
        self.serverVersionJson = serverVersionJson
    }
}

// MARK: - Decodable

extension ConflictItem: Decodable {
    enum CodingKeys: String, CodingKey {
        case id
        case entityKind           = "entity_kind"
        case entityId             = "entity_id"
        case conflictType         = "conflict_type"
        case status
        case resolution
        case resolutionNotes      = "resolution_notes"
        case reporterUserId       = "reporter_user_id"
        case reporterDeviceId     = "reporter_device_id"
        case reporterPlatform     = "reporter_platform"
        case reportedAt           = "reported_at"
        case resolvedByUserId     = "resolved_by_user_id"
        case resolvedAt           = "resolved_at"
        case reporterFirstName    = "reporter_first_name"
        case reporterLastName     = "reporter_last_name"
        case resolverFirstName    = "resolver_first_name"
        case resolverLastName     = "resolver_last_name"
        case clientVersionJson    = "client_version_json"
        case serverVersionJson    = "server_version_json"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(Int.self, forKey: .id)
        entityKind       = try c.decode(String.self, forKey: .entityKind)
        entityId         = try c.decode(Int.self, forKey: .entityId)
        // conflict_type may arrive as an unknown string in future; fall back gracefully.
        let typeRaw      = try c.decode(String.self, forKey: .conflictType)
        conflictType     = ConflictType(rawValue: typeRaw) ?? .concurrentUpdate
        let statusRaw    = try c.decode(String.self, forKey: .status)
        status           = ConflictStatus(rawValue: statusRaw) ?? .pending
        let resolutionRaw = try? c.decode(String.self, forKey: .resolution)
        resolution       = resolutionRaw.flatMap { Resolution(rawValue: $0) }
        resolutionNotes  = try? c.decode(String.self, forKey: .resolutionNotes)
        reporterUserId   = try? c.decode(Int.self, forKey: .reporterUserId)
        reporterDeviceId = try? c.decode(String.self, forKey: .reporterDeviceId)
        reporterPlatform = try? c.decode(String.self, forKey: .reporterPlatform)
        reportedAt       = try c.decode(String.self, forKey: .reportedAt)
        resolvedByUserId = try? c.decode(Int.self, forKey: .resolvedByUserId)
        resolvedAt       = try? c.decode(String.self, forKey: .resolvedAt)
        reporterFirstName = try? c.decode(String.self, forKey: .reporterFirstName)
        reporterLastName  = try? c.decode(String.self, forKey: .reporterLastName)
        resolverFirstName = try? c.decode(String.self, forKey: .resolverFirstName)
        resolverLastName  = try? c.decode(String.self, forKey: .resolverLastName)
        clientVersionJson = try? c.decode(String.self, forKey: .clientVersionJson)
        serverVersionJson = try? c.decode(String.self, forKey: .serverVersionJson)
    }
}

// MARK: - ConflictListResponse

/// Envelope `data` array from `GET /api/v1/sync/conflicts`.
public struct ConflictListResponse: Decodable, Sendable {
    public let items: [ConflictItem]
    public let total: Int
    public let page: Int
    public let pageSize: Int
    public let pages: Int
}

// MARK: - ResolveRequest

/// Body sent to `POST /api/v1/sync/conflicts/:id/resolve`.
public struct ResolveConflictRequest: Encodable, Sendable {
    public let resolution: String          // Resolution.rawValue
    public let resolutionNotes: String?

    enum CodingKeys: String, CodingKey {
        case resolution
        case resolutionNotes = "resolution_notes"
    }

    public init(resolution: Resolution, notes: String?) {
        self.resolution = resolution.rawValue
        self.resolutionNotes = notes?.isEmpty == false ? notes : nil
    }
}

// MARK: - ResolveConflictResult

/// Data field from `POST /api/v1/sync/conflicts/:id/resolve`.
public struct ResolveConflictResult: Decodable, Sendable {
    public let id: Int
    public let status: String
    public let resolution: String
    public let resolvedByUserId: Int
    public let resolvedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case resolution
        case resolvedByUserId = "resolved_by_user_id"
        case resolvedAt       = "resolved_at"
    }
}
