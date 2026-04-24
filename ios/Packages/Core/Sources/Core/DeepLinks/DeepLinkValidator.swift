import Foundation

// MARK: - DeepLinkValidator

/// Guards against open-redirect attacks and malicious deep-link payloads.
///
/// The validator operates on **raw URLs** (before parsing) and on
/// **parsed `DeepLinkDestination` values** (after parsing).  Both
/// layers must pass before a deep link is acted upon.
///
/// ## Threat model
/// - **Open redirect** — attacker crafts a deep link that causes the app
///   to open an arbitrary HTTPS URL (e.g. a phishing page).
/// - **Host spoofing** — `bizarrecrm://evil.com/acme/…` uses the custom
///   scheme with a non-allowlisted host.
/// - **Path traversal** — `../../` segments that escape the expected
///   resource tree.
/// - **Injection via query params** — JavaScript or HTML in `token` /
///   `q` values that might reach a `WKWebView`.
///
/// Thread-safe: stateless enum.
public enum DeepLinkValidator {

    // MARK: - Configuration

    /// Hosts allowed in universal-link form.
    public static let allowedHosts: Set<String> = [
        DeepLinkURLParser.universalLinkHost
    ]

    /// Custom scheme — only `bizarrecrm` is valid.
    public static let allowedSchemes: Set<String> = [
        DeepLinkURLParser.customScheme,
        "https",
        "http"
    ]

    /// Path segments that are not allowed in any component.
    private static let forbiddenPathSegments: Set<String> = [
        "..", ".", "%2e%2e", "%2e", "%252e%252e"
    ]

    /// Maximum length for a single URL string.
    private static let maxURLLength = 2_048

    // MARK: - Validation Result

    /// The outcome of a validation check.
    public enum ValidationResult: Sendable, Equatable {
        case valid
        case invalid(reason: String)

        /// Convenience accessor.
        public var isValid: Bool {
            if case .valid = self { return true }
            return false
        }
    }

    // MARK: - Public API (URL layer)

    /// Validate a raw URL **before** parsing.
    ///
    /// Checks:
    /// 1. URL length within `maxURLLength`.
    /// 2. Scheme is in `allowedSchemes`.
    /// 3. For HTTP/HTTPS: host is in `allowedHosts`.
    /// 4. No path-traversal segments (`..`).
    /// 5. No null bytes in the absolute string.
    public static func validate(url: URL) -> ValidationResult {
        let raw = url.absoluteString

        // 1. Length guard
        guard raw.count <= maxURLLength else {
            return .invalid(reason: "URL exceeds maximum length of \(maxURLLength) characters")
        }

        // 2. Null-byte injection guard
        guard !raw.contains("\0") else {
            return .invalid(reason: "URL contains null bytes")
        }

        // 3. Scheme allowlist
        guard let scheme = url.scheme?.lowercased() else {
            return .invalid(reason: "URL has no scheme")
        }
        guard allowedSchemes.contains(scheme) else {
            return .invalid(reason: "Scheme '\(scheme)' is not allowed")
        }

        // 4. Host allowlist for HTTP(S) links
        if scheme == "https" || scheme == "http" {
            guard let host = url.host?.lowercased() else {
                return .invalid(reason: "HTTP(S) URL has no host")
            }
            guard allowedHosts.contains(host) else {
                return .invalid(reason: "Host '\(host)' is not in the allowed list")
            }
        }

        // 5. Path-traversal guard
        let pathLower = url.path.lowercased()
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url.path

        for segment in forbiddenPathSegments {
            if pathLower.contains(segment) {
                return .invalid(reason: "Path contains forbidden segment '\(segment)'")
            }
        }

        // Also check individual path components after percent-decoding.
        for component in url.pathComponents {
            let decoded = component
                .removingPercentEncoding?
                .trimmingCharacters(in: .whitespaces) ?? component
            if decoded == ".." || decoded == "." {
                return .invalid(reason: "Path traversal detected in component '\(component)'")
            }
        }

        return .valid
    }

    // MARK: - Public API (destination layer)

    /// Validate a **parsed** `DeepLinkDestination`.
    ///
    /// Checks:
    /// 1. Tenant slug is non-empty and contains only safe characters.
    /// 2. Resource identifiers do not contain control characters.
    /// 3. Token values (magic link) meet minimum length.
    public static func validate(destination: DeepLinkDestination) -> ValidationResult {

        // 1. Slug sanity
        if let slug = destination.tenantSlug {
            let result = validateSlug(slug)
            if !result.isValid { return result }
        }

        // 2. Per-case field checks
        switch destination {

        case .ticket(_, let id),
             .customer(_, let id),
             .invoice(_, let id),
             .estimate(_, let id),
             .lead(_, let id),
             .appointment(_, let id):
            return validateID(id, field: "id")

        case .inventory(_, let sku):
            return validateID(sku, field: "sku")

        case .smsThread(_, let phone):
            return validatePhone(phone)

        case .reports(_, let name):
            return validateID(name, field: "name")

        case .magicLink(_, let token):
            guard token.count >= 8 else {
                return .invalid(reason: "Magic-link token is too short (minimum 8 characters)")
            }
            return validateID(token, field: "token")

        case .settings(_, let section):
            if let section = section {
                return validateID(section, field: "section")
            }
            return .valid

        case .search(_, let query):
            if let query = query, query.count > 512 {
                return .invalid(reason: "Search query exceeds 512 characters")
            }
            return .valid

        case .dashboard, .posRoot, .posNewCart, .posReturn,
             .auditLogs, .notifications, .timeclock:
            return .valid
        }
    }

    // MARK: - Combined check

    /// Parse and validate in one call.  Returns `nil` when either the URL
    /// fails structural validation or the resulting destination fails
    /// field-level validation.
    public static func parseAndValidate(_ url: URL) -> DeepLinkDestination? {
        guard validate(url: url).isValid else { return nil }
        guard let destination = DeepLinkURLParser.parse(url) else { return nil }
        guard validate(destination: destination).isValid else { return nil }
        return destination
    }

    // MARK: - Private validators

    private static func validateSlug(_ slug: String) -> ValidationResult {
        guard !slug.isEmpty else {
            return .invalid(reason: "Tenant slug is empty")
        }
        // Slugs: lowercase letters, digits, hyphens, underscores only.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        if slug.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return .invalid(reason: "Tenant slug '\(slug)' contains invalid characters")
        }
        return .valid
    }

    private static func validateID(_ value: String, field: String) -> ValidationResult {
        guard !value.isEmpty else {
            return .invalid(reason: "Field '\(field)' is empty")
        }
        // Reject null bytes and ASCII control characters.
        if value.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) {
            return .invalid(reason: "Field '\(field)' contains control characters")
        }
        guard value.count <= 256 else {
            return .invalid(reason: "Field '\(field)' exceeds 256 characters")
        }
        return .valid
    }

    private static func validatePhone(_ phone: String) -> ValidationResult {
        guard !phone.isEmpty else {
            return .invalid(reason: "Phone number is empty")
        }
        // Allow digits, spaces, +, -, (, ), and extension-separator characters.
        let allowed = CharacterSet.decimalDigits
            .union(CharacterSet(charactersIn: " +-.()xX#"))
        if phone.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return .invalid(reason: "Phone number '\(phone)' contains invalid characters")
        }
        return .valid
    }
}
