import Foundation

// §5.4 — Custom field definitions and values.
// Server routes: packages/server/src/routes/customFields.routes.ts
//   GET  /api/v1/custom-fields/definitions?entity_type=customer
//   GET  /api/v1/custom-fields/values/:entityType/:entityId
//   PUT  /api/v1/custom-fields/values/:entityType/:entityId

// MARK: - Custom field definition

/// A tenant-defined field attached to an entity type (ticket / customer / inventory / invoice).
public struct CustomFieldDefinition: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let entityType: String
    public let fieldName: String
    public let fieldType: String          // text | number | boolean | date | select | multiselect | textarea
    public let optionsRaw: String?        // JSON-encoded string array for select/multiselect
    public let isRequired: Bool
    public let sortOrder: Int

    public var options: [String] {
        guard let raw = optionsRaw,
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
    }

    enum CodingKeys: String, CodingKey {
        case id
        case entityType = "entity_type"
        case fieldName = "field_name"
        case fieldType = "field_type"
        case optionsRaw = "options"
        case isRequired = "is_required"
        case sortOrder = "sort_order"
    }
}

/// One resolved value row joined with the definition.
public struct CustomFieldValue: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let definitionId: Int64
    public let entityType: String
    public let entityId: Int64
    public let value: String
    public let fieldName: String
    public let fieldType: String

    enum CodingKeys: String, CodingKey {
        case id
        case definitionId = "definition_id"
        case entityType = "entity_type"
        case entityId = "entity_id"
        case value
        case fieldName = "field_name"
        case fieldType = "field_type"
    }
}

// MARK: - Upsert request

/// `PUT /api/v1/custom-fields/values/:entityType/:entityId` body.
/// `fields` is an array of `{ definition_id, value }`.
public struct SetCustomFieldValuesRequest: Encodable, Sendable {
    public let fields: [FieldEntry]

    public init(fields: [FieldEntry]) { self.fields = fields }

    public struct FieldEntry: Encodable, Sendable {
        public let definitionId: Int64
        public let value: String

        public init(definitionId: Int64, value: String) {
            self.definitionId = definitionId
            self.value = value
        }

        enum CodingKeys: String, CodingKey {
            case definitionId = "definition_id"
            case value
        }
    }
}

/// `PUT /api/v1/custom-fields/values/…` response.
public struct SetCustomFieldValuesResponse: Decodable, Sendable {
    public let saved: Int

    public init(saved: Int) { self.saved = saved }
}

// MARK: - APIClient extension

public extension APIClient {

    /// `GET /api/v1/custom-fields/definitions?entity_type=<entityType>`
    func customFieldDefinitions(entityType: String) async throws -> [CustomFieldDefinition] {
        let query = [URLQueryItem(name: "entity_type", value: entityType)]
        return try await get(
            "/api/v1/custom-fields/definitions",
            query: query,
            as: [CustomFieldDefinition].self
        )
    }

    /// `GET /api/v1/custom-fields/values/:entityType/:entityId`
    func customFieldValues(entityType: String, entityId: Int64) async throws -> [CustomFieldValue] {
        try await get(
            "/api/v1/custom-fields/values/\(entityType)/\(entityId)",
            as: [CustomFieldValue].self
        )
    }

    /// `PUT /api/v1/custom-fields/values/:entityType/:entityId`
    func setCustomFieldValues(
        entityType: String,
        entityId: Int64,
        fields: [SetCustomFieldValuesRequest.FieldEntry]
    ) async throws -> SetCustomFieldValuesResponse {
        let req = SetCustomFieldValuesRequest(fields: fields)
        return try await put(
            "/api/v1/custom-fields/values/\(entityType)/\(entityId)",
            body: req,
            as: SetCustomFieldValuesResponse.self
        )
    }
}
