import Foundation

/// A WGS-84 latitude/longitude pair.
struct Coordinate: Hashable {
    let latitude: Double
    let longitude: Double

    /// Great-circle distance in meters (haversine formula). Accurate to well
    /// under a percent, which is plenty for ranking stations by walking distance.
    func distance(to other: Coordinate) -> Double {
        let earthRadius = 6_371_000.0
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(latitude * .pi / 180) * cos(other.latitude * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Parses `"40.758, -73.985"` style input.
    static func parse(_ text: String) -> Coordinate? {
        let parts = text.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Double($0) }
        guard parts.count == 2, (-90...90).contains(parts[0]), (-180...180).contains(parts[1]) else { return nil }
        return Coordinate(latitude: parts[0], longitude: parts[1])
    }
}

/// Formats a distance the way New Yorkers read it: feet under ~0.1 mi, miles above.
func formatDistance(meters: Double) -> String {
    let feet = meters * 3.28084
    if feet < 528 { return "\(Int(feet.rounded())) ft" }
    let miles = feet / 5280
    if miles >= 10 { return String(format: "%.0f mi", miles) }
    return String(format: "%.1f mi", miles)
}
