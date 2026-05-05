import Foundation
import Networking

// MARK: - PricingRulesRepository

/// §16 — Repository protocol for POS pricing-rule CRUD + reorder.
///
/// All server calls are routed through typed `APIClient+PosRules` wrappers
/// (sdk-ban containment: no bare path strings in this file).
public protocol PricingRulesRepository: Sendable {
    /// Fetch all rules for the tenant, sorted by `priority` ascending.
    func listRules() async throws -> [PricingRule]

    /// Persist a new or updated rule.
    /// - If the rule's `id` already exists server-side, performs a PUT.
    /// - If it is a locally-generated UUID not yet on the server, performs a POST.
    func updateRule(_ rule: PricingRule) async throws

    /// Delete rule by id.
    func deleteRule(id: String) async throws

    /// Batch-update the priority order.
    /// `orderedIds` is the full rule-id list in desired ascending priority order.
    func reorderRules(orderedIds: [String]) async throws
}

// MARK: - PricingRulesRepositoryImpl

/// Production implementation backed by `APIClient+PosRules`.
public struct PricingRulesRepositoryImpl: PricingRulesRepository {

    private let api: any APIClient

    public init(api: any APIClient) {
        self.api = api
    }

    // MARK: - List

    public func listRules() async throws -> [PricingRule] {
        let dtos = try await api.listPosPricingRules()
        return dtos.map(PricingRule.init(dto:)).sorted { $0.priority < $1.priority }
    }

    // MARK: - Update (create or replace)

    public func updateRule(_ rule: PricingRule) async throws {
        let dto = PricingRuleDTO(rule: rule)
        _ = try await api.updatePosPricingRule(dto)
    }

    // MARK: - Delete

    public func deleteRule(id: String) async throws {
        try await api.deletePosPricingRule(id: id)
    }

    // MARK: - Reorder

    public func reorderRules(orderedIds: [String]) async throws {
        try await api.reorderPosPricingRules(orderedIds: orderedIds)
    }
}

// MARK: - PricingRule ↔ PricingRuleDTO mapping

private extension PricingRule {
    /// Map from wire DTO to domain model.
    init(dto: PricingRuleDTO) {
        self.init(
            id: dto.id,
            name: dto.name,
            type: PricingRuleType(rawValue: dto.type) ?? .tieredVolume,
            targetSku: dto.targetSku,
            targetCategory: dto.targetCategory,
            targetSegment: dto.targetSegment,
            bundleQuantity: dto.bundleQuantity,
            bundlePriceCents: dto.bundlePriceCents,
            triggerQuantity: dto.triggerQuantity,
            freeQuantity: dto.freeQuantity,
            tiers: dto.tiers?.map { PricingTier(minQty: $0.minQty, maxQty: $0.maxQty, unitPriceCents: $0.unitPriceCents) },
            segmentDiscountPercent: dto.segmentDiscountPercent,
            targetLocationSlug: dto.targetLocationSlug,
            locationDiscountPercent: dto.locationDiscountPercent,
            promotionActive: dto.promotionActive,
            promotionLabel: dto.promotionLabel,
            promotionDiscountPercent: dto.promotionDiscountPercent,
            validFrom: dto.validFrom,
            validTo: dto.validTo,
            enabled: dto.enabled,
            priority: dto.priority
        )
    }
}

private extension PricingRuleDTO {
    /// Map from domain model to wire DTO for write operations.
    init(rule: PricingRule) {
        self.init(
            id: rule.id,
            name: rule.name,
            type: rule.type.rawValue,
            enabled: rule.enabled,
            priority: rule.priority,
            targetSku: rule.targetSku,
            targetCategory: rule.targetCategory,
            targetSegment: rule.targetSegment,
            bundleQuantity: rule.bundleQuantity,
            bundlePriceCents: rule.bundlePriceCents,
            triggerQuantity: rule.triggerQuantity,
            freeQuantity: rule.freeQuantity,
            tiers: rule.tiers?.map { PricingTierDTO(minQty: $0.minQty, maxQty: $0.maxQty, unitPriceCents: $0.unitPriceCents) },
            segmentDiscountPercent: rule.segmentDiscountPercent,
            targetLocationSlug: rule.targetLocationSlug,
            locationDiscountPercent: rule.locationDiscountPercent,
            promotionActive: rule.promotionActive,
            promotionLabel: rule.promotionLabel,
            promotionDiscountPercent: rule.promotionDiscountPercent,
            validFrom: rule.validFrom,
            validTo: rule.validTo
        )
    }
}
