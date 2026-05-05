import Foundation

// MARK: - MileageCalculator

/// Pure stateless calculator. Uses haversine formula for great-circle distance.
/// All money in cents. No mutation of inputs.
public enum MileageCalculator {

    // MARK: - Constants

    private static let earthRadiusMiles: Double = 3_958.8

    // MARK: - Haversine distance

    /// Returns the great-circle distance in miles between two lat/lon points.
    public static func distanceMiles(
        fromLat: Double, fromLon: Double,
        toLat: Double, toLon: Double
    ) -> Double {
        let dLat = toRadians(toLat - fromLat)
        let dLon = toRadians(toLon - fromLon)
        let lat1 = toRadians(fromLat)
        let lat2 = toRadians(toLat)

        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusMiles * c
    }

    // MARK: - Total reimbursement

    /// Returns reimbursement in cents: `round(miles × rateCentsPerMile)`.
    public static func totalCents(miles: Double, rateCentsPerMile: Int) -> Int {
        Int((miles * Double(rateCentsPerMile)).rounded())
    }

    /// Convenience: computes distance then total from coordinate pairs.
    public static func reimbursementCents(
        fromLat: Double, fromLon: Double,
        toLat: Double, toLon: Double,
        rateCentsPerMile: Int
    ) -> (miles: Double, totalCents: Int) {
        let miles = distanceMiles(fromLat: fromLat, fromLon: fromLon, toLat: toLat, toLon: toLon)
        return (miles, totalCents(miles: miles, rateCentsPerMile: rateCentsPerMile))
    }

    // MARK: - Private helpers

    private static func toRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }
}
