import Foundation

// §5 Customer Groups & Tags
//
// Ground truth: packages/server/src/routes/smsGroups.routes.ts
//   Mounted at /api/v1/sms/groups
//   GET /                 → { success, data: [CustomerGroup] }
//   GET /:id              → { success, data: { group, members, pagination } }
//   POST /                → { success, data: CustomerGroup }
//   PATCH /:id            → { success, data: CustomerGroup }
//   DELETE /:id           → { success, data: { id } }
//   POST /:id/members     → { success, data: { group_id, added, skipped } }
//   DELETE /:id/members/:customerId → { success, data: { group_id, customer_id, removed } }
//
// Note: customer_groups (discount groups) live at /api/v1/settings/customer-groups
// and are read-only from this feature's perspective. SMS groups are the
// primary groups entity managed here.

/// A customer SMS group as returned by the server.
/// `is_dynamic` is stored as INTEGER (0/1) in SQLite and serialised as a
/// JSON number — we decode it as Int then coerce to Bool manually.
public struct CustomerGroup: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let name: String
    public let description: String?
    public let isDynamic: Bool
    public let memberCountCache: Int
    public let createdByUserId: Int64?
    public let createdAt: String?
    public let updatedAt: String?

    public var displayMemberCount: String {
        memberCountCache == 1 ? "1 member" : "\(memberCountCache) members"
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case isDynamic = "is_dynamic"
        case memberCountCache = "member_count_cache"
        case createdByUserId = "created_by_user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        // is_dynamic arrives as 0 or 1 from SQLite-JSON; accept both Int and Bool.
        if let boolVal = try? c.decode(Bool.self, forKey: .isDynamic) {
            isDynamic = boolVal
        } else {
            isDynamic = (try? c.decode(Int.self, forKey: .isDynamic)) == 1
        }
        memberCountCache = try c.decode(Int.self, forKey: .memberCountCache)
        createdByUserId = try c.decodeIfPresent(Int64.self, forKey: .createdByUserId)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    /// Memberwise init for constructing updated copies (immutable pattern).
    public init(
        id: Int64,
        name: String,
        description: String?,
        isDynamic: Bool,
        memberCountCache: Int,
        createdByUserId: Int64?,
        createdAt: String?,
        updatedAt: String?
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.isDynamic = isDynamic
        self.memberCountCache = memberCountCache
        self.createdByUserId = createdByUserId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A member row inside a group detail response.
public struct CustomerGroupMember: Decodable, Sendable, Identifiable, Hashable {
    public let memberId: Int64
    public let customerId: Int64
    public let addedAt: String?
    public let firstName: String?
    public let lastName: String?
    public let phone: String?
    public let mobile: String?
    public let email: String?

    public var id: Int64 { memberId }

    public var displayName: String {
        let parts = [firstName, lastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        if !parts.isEmpty { return parts.joined(separator: " ") }
        if let e = email, !e.isEmpty { return e }
        if let m = mobile, !m.isEmpty { return m }
        if let p = phone, !p.isEmpty { return p }
        return "Customer \(customerId)"
    }

    public var contactLine: String? {
        if let m = mobile, !m.isEmpty { return m }
        if let p = phone, !p.isEmpty { return p }
        if let e = email, !e.isEmpty { return e }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case memberId = "member_id"
        case customerId = "customer_id"
        case addedAt = "added_at"
        case firstName = "first_name"
        case lastName = "last_name"
        case phone, mobile, email
    }
}

/// Pagination metadata from group detail.
public struct GroupMemberPagination: Decodable, Sendable {
    public let page: Int
    public let limit: Int
    public let total: Int
    public let pages: Int
}

/// Envelope data shape for GET /sms/groups/:id
public struct CustomerGroupDetail: Decodable, Sendable {
    public let group: CustomerGroup
    public let members: [CustomerGroupMember]
    public let pagination: GroupMemberPagination
}

/// Request body for creating a group.
public struct CreateGroupRequest: Encodable, Sendable {
    public let name: String
    public let description: String?
    public let isDynamic: Bool

    public init(name: String, description: String? = nil, isDynamic: Bool = false) {
        self.name = name
        self.description = description
        self.isDynamic = isDynamic
    }

    enum CodingKeys: String, CodingKey {
        case name, description
        case isDynamic = "is_dynamic"
    }
}

/// Request body for PATCH /sms/groups/:id
public struct UpdateGroupRequest: Encodable, Sendable {
    public let name: String?
    public let description: String?

    public init(name: String? = nil, description: String? = nil) {
        self.name = name
        self.description = description
    }
}

/// Request body for POST /sms/groups/:id/members
public struct AddGroupMembersRequest: Encodable, Sendable {
    public let customerIds: [Int64]

    public init(customerIds: [Int64]) {
        self.customerIds = customerIds
    }

    enum CodingKeys: String, CodingKey {
        case customerIds = "customer_ids"
    }
}

/// Response payload for member add.
public struct AddGroupMembersResponse: Decodable, Sendable {
    public let groupId: Int64
    public let added: Int
    public let skipped: Int

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case added, skipped
    }
}
