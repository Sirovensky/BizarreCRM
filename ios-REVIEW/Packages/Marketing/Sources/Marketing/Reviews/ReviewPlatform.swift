import Foundation

// MARK: - ReviewPlatform

public enum ReviewPlatform: Sendable, Hashable, Codable, CaseIterable {
    case google
    case yelp
    case facebook
    case other(name: String, url: URL)

    // CaseIterable only covers non-associated-value cases
    public static var allCases: [ReviewPlatform] { [.google, .yelp, .facebook] }

    public var displayName: String {
        switch self {
        case .google:           return "Google"
        case .yelp:             return "Yelp"
        case .facebook:         return "Facebook"
        case .other(let n, _):  return n
        }
    }

    public var systemIconName: String {
        switch self {
        case .google:   return "g.circle.fill"
        case .yelp:     return "star.circle.fill"
        case .facebook: return "f.circle.fill"
        case .other:    return "link.circle.fill"
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey { case type, name, url }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type_ = try c.decode(String.self, forKey: .type)
        switch type_ {
        case "google":   self = .google
        case "yelp":     self = .yelp
        case "facebook": self = .facebook
        default:
            let name = try c.decode(String.self, forKey: .name)
            let urlString = try c.decode(String.self, forKey: .url)
            guard let url = URL(string: urlString) else {
                throw DecodingError.dataCorruptedError(forKey: .url, in: c, debugDescription: "Invalid URL")
            }
            self = .other(name: name, url: url)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .google:   try c.encode("google", forKey: .type)
        case .yelp:     try c.encode("yelp", forKey: .type)
        case .facebook: try c.encode("facebook", forKey: .type)
        case .other(let name, let url):
            try c.encode("other", forKey: .type)
            try c.encode(name, forKey: .name)
            try c.encode(url.absoluteString, forKey: .url)
        }
    }
}

// MARK: - ReviewLastRequestResponse

public struct ReviewLastRequestResponse: Decodable, Sendable {
    public let lastRequestedAt: Date?

    public init(lastRequestedAt: Date?) {
        self.lastRequestedAt = lastRequestedAt
    }
}

// MARK: - ReviewRequestBody

public struct ReviewRequestBody: Encodable, Sendable {
    public let customerId: String
    public let platform: ReviewPlatform?
    public let template: String

    public init(customerId: String, platform: ReviewPlatform?, template: String) {
        self.customerId = customerId
        self.platform = platform
        self.template = template
    }
}

// MARK: - ReviewRequestResponse

public struct ReviewRequestResponse: Decodable, Sendable {
    public let sent: Bool

    public init(sent: Bool) {
        self.sent = sent
    }
}

// MARK: - ReviewPlatformSettings

public struct ReviewPlatformSettings: Codable, Sendable {
    public var googleBusinessURL: URL?
    public var yelpURL: URL?
    public var facebookURL: URL?
    public var otherPlatforms: [OtherPlatform]

    public struct OtherPlatform: Codable, Sendable, Identifiable {
        public let id: String
        public var name: String
        public var url: URL

        public init(id: String, name: String, url: URL) {
            self.id = id
            self.name = name
            self.url = url
        }
    }

    public init(
        googleBusinessURL: URL? = nil,
        yelpURL: URL? = nil,
        facebookURL: URL? = nil,
        otherPlatforms: [OtherPlatform] = []
    ) {
        self.googleBusinessURL = googleBusinessURL
        self.yelpURL = yelpURL
        self.facebookURL = facebookURL
        self.otherPlatforms = otherPlatforms
    }
}
