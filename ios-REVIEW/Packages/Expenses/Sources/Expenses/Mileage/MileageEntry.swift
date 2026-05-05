import Foundation

// MARK: - MileageEntry

public struct MileageEntry: Codable, Sendable, Identifiable, Equatable {
    public let id: Int64
    public let employeeId: Int64
    public let fromLocation: String
    public let toLocation: String
    public let fromLat: Double?
    public let fromLon: Double?
    public let toLat: Double?
    public let toLon: Double?
    public let miles: Double
    public let rateCentsPerMile: Int
    public let totalCents: Int
    public let date: String         // ISO-8601 date string
    public let purpose: String?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case employeeId    = "employee_id"
        case fromLocation  = "from_location"
        case toLocation    = "to_location"
        case fromLat       = "from_lat"
        case fromLon       = "from_lon"
        case toLat         = "to_lat"
        case toLon         = "to_lon"
        case miles
        case rateCentsPerMile = "rate_cents_per_mile"
        case totalCents    = "total_cents"
        case date
        case purpose
        case createdAt     = "created_at"
    }

    public init(
        id: Int64,
        employeeId: Int64,
        fromLocation: String,
        toLocation: String,
        fromLat: Double? = nil,
        fromLon: Double? = nil,
        toLat: Double? = nil,
        toLon: Double? = nil,
        miles: Double,
        rateCentsPerMile: Int,
        totalCents: Int,
        date: String,
        purpose: String? = nil,
        createdAt: String? = nil
    ) {
        self.id = id
        self.employeeId = employeeId
        self.fromLocation = fromLocation
        self.toLocation = toLocation
        self.fromLat = fromLat
        self.fromLon = fromLon
        self.toLat = toLat
        self.toLon = toLon
        self.miles = miles
        self.rateCentsPerMile = rateCentsPerMile
        self.totalCents = totalCents
        self.date = date
        self.purpose = purpose
        self.createdAt = createdAt
    }
}

// MARK: - CreateMileageBody

public struct CreateMileageBody: Encodable, Sendable {
    public let employeeId: Int64
    public let fromLocation: String
    public let toLocation: String
    public let fromLat: Double?
    public let fromLon: Double?
    public let toLat: Double?
    public let toLon: Double?
    public let miles: Double
    public let rateCentsPerMile: Int
    public let totalCents: Int
    public let date: String
    public let purpose: String?

    enum CodingKeys: String, CodingKey {
        case employeeId   = "employee_id"
        case fromLocation = "from_location"
        case toLocation   = "to_location"
        case fromLat      = "from_lat"
        case fromLon      = "from_lon"
        case toLat        = "to_lat"
        case toLon        = "to_lon"
        case miles
        case rateCentsPerMile = "rate_cents_per_mile"
        case totalCents   = "total_cents"
        case date
        case purpose
    }

    public init(
        employeeId: Int64,
        fromLocation: String,
        toLocation: String,
        fromLat: Double? = nil,
        fromLon: Double? = nil,
        toLat: Double? = nil,
        toLon: Double? = nil,
        miles: Double,
        rateCentsPerMile: Int,
        totalCents: Int,
        date: String,
        purpose: String?
    ) {
        self.employeeId = employeeId
        self.fromLocation = fromLocation
        self.toLocation = toLocation
        self.fromLat = fromLat
        self.fromLon = fromLon
        self.toLat = toLat
        self.toLon = toLon
        self.miles = miles
        self.rateCentsPerMile = rateCentsPerMile
        self.totalCents = totalCents
        self.date = date
        self.purpose = purpose
    }
}
