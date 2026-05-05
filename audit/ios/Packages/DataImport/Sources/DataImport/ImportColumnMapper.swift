import Foundation

// MARK: - ImportColumnMapper

/// Auto-maps source CSV column names to CRM target fields using:
/// 1. Exact lowercased match
/// 2. Levenshtein distance < 3 (fuzzy)
///
/// Immutable: produces a new mapping dict, never mutates.
public enum ImportColumnMapper {

    // MARK: - Public API

    /// Produce an initial mapping of source columns → CRM field raw values for the given entity type.
    /// Columns that can't be mapped are left unmapped (not present in result).
    /// - Parameters:
    ///   - sourceColumns: Column names from the uploaded file.
    ///   - entity: The import entity type to scope mapping to.
    /// - Returns: `[sourceColumn: CRMField.rawValue]` for matched columns.
    public static func autoMap(
        sourceColumns: [String],
        entity: ImportEntityType = .customers
    ) -> [String: String] {
        let targets = CRMField.fields(for: entity)
        var result: [String: String] = [:]
        for source in sourceColumns {
            if let match = bestMatch(for: source, among: targets) {
                result[source] = match.rawValue
            }
        }
        return result
    }

    /// Returns true iff the mapping covers all required CRM fields for the entity.
    public static func allRequiredMapped(
        _ mapping: [String: String],
        entity: ImportEntityType = .customers
    ) -> Bool {
        let mapped = Set(mapping.values)
        return CRMField.requiredFields(for: entity).allSatisfy { mapped.contains($0.rawValue) }
    }

    /// Returns the set of required fields still missing from the mapping for the entity.
    public static func missingRequired(
        _ mapping: [String: String],
        entity: ImportEntityType = .customers
    ) -> [CRMField] {
        let mapped = Set(mapping.values)
        return CRMField.requiredFields(for: entity).filter { !mapped.contains($0.rawValue) }
    }

    // MARK: - Internal matching

    static func bestMatch(for source: String, among targets: [CRMField]) -> CRMField? {
        let normalizedSource = normalize(source)

        // 1. Exact match (lowercased / normalized)
        for target in targets {
            if normalize(target.rawValue) == normalizedSource { return target }
            if normalize(target.displayName) == normalizedSource { return target }
        }

        // 2. Fuzzy: Levenshtein distance < 3 — pick the closest
        var bestTarget: CRMField? = nil
        var bestDistance = 3 // exclusive upper bound

        for target in targets {
            let d1 = levenshtein(normalizedSource, normalize(target.displayName))
            let d2 = levenshtein(normalizedSource, normalize(target.rawValue))
            let d = min(d1, d2)
            if d < bestDistance {
                bestDistance = d
                bestTarget = target
            }
        }
        return bestTarget
    }

    /// Normalize: lowercase, strip entity prefixes, strip punctuation.
    static func normalize(_ s: String) -> String {
        var result = s.lowercased()
        for prefix in ["customer.", "inventory.", "ticket."] {
            result = result.replacingOccurrences(of: prefix, with: "")
        }
        return result
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    /// Classic DP Levenshtein distance.
    static func levenshtein(_ a: String, _ b: String) -> Int {
        let aArr = Array(a)
        let bArr = Array(b)
        let aLen = aArr.count
        let bLen = bArr.count

        if aLen == 0 { return bLen }
        if bLen == 0 { return aLen }

        var matrix = Array(repeating: Array(repeating: 0, count: bLen + 1), count: aLen + 1)

        for i in 0...aLen { matrix[i][0] = i }
        for j in 0...bLen { matrix[0][j] = j }

        for i in 1...aLen {
            for j in 1...bLen {
                let cost = aArr[i - 1] == bArr[j - 1] ? 0 : 1
                matrix[i][j] = Swift.min(
                    matrix[i - 1][j] + 1,          // deletion
                    matrix[i][j - 1] + 1,           // insertion
                    matrix[i - 1][j - 1] + cost     // substitution
                )
            }
        }
        return matrix[aLen][bLen]
    }
}
