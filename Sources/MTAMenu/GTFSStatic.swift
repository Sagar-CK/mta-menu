import Foundation

/// Which way a train is heading, derived from the GTFS stop ID suffix.
///
/// NYCT stop IDs look like `127N` / `127S`. "N" is the railroad-north
/// direction (toward uptown / The Bronx / Queens for most lines) and "S" is
/// railroad-south (downtown / Brooklyn). The parent station is `127`.
enum Direction: String, CaseIterable {
    case north = "N"
    case south = "S"

    var label: String {
        switch self {
        case .north: return "Northbound"
        case .south: return "Southbound"
        }
    }
}

/// A subway station (a GTFS parent stop with `location_type = 1`).
struct Station: Hashable {
    let id: String
    let name: String
    let coordinate: Coordinate
}

/// A subway route (line) from `routes.txt`, including the MTA's official colors.
struct RouteInfo: Hashable {
    let id: String
    let shortName: String
    let longName: String
    /// Hex RGB without `#`, e.g. `FCCC0A` for the N/Q/R/W.
    let color: String
    /// Hex RGB for the bullet's letter, e.g. `000000` on yellow lines.
    let textColor: String
    let sortOrder: Int
}

/// Static subway data bundled with the app: stations and routes from the
/// MTA's GTFS feed (`stops.txt` and `routes.txt`).
///
/// Realtime feeds only reference stop IDs, so this is what turns `R16N` into
/// "Times Sq-42 St, Northbound" and `N` into a yellow bullet.
final class GTFSStatic {
    /// Parent station ID → station.
    let stations: [String: Station]
    /// Displayable routes in MTA sort order (express variants like `6X` are folded away).
    let routes: [RouteInfo]
    /// Route ID → route, including the express variants.
    let routeById: [String: RouteInfo]

    /// Any stop ID (parent or platform) → parent station ID.
    private let parentByStop: [String: String]

    init(stopsCSV: String, routesCSV: String) {
        var stations: [String: Station] = [:]
        var parentByStop: [String: String] = [:]
        for row in CSV.parse(stopsCSV) {
            guard let id = row["stop_id"], !id.isEmpty else { continue }
            let parent = row["parent_station"].flatMap { $0.isEmpty ? nil : $0 } ?? id
            parentByStop[id] = parent
            if row["location_type"] == "1",
               let lat = row["stop_lat"].flatMap(Double.init),
               let lon = row["stop_lon"].flatMap(Double.init) {
                stations[id] = Station(id: id, name: row["stop_name"] ?? id,
                                       coordinate: Coordinate(latitude: lat, longitude: lon))
            }
        }

        var routeById: [String: RouteInfo] = [:]
        for row in CSV.parse(routesCSV) {
            guard let id = row["route_id"], !id.isEmpty else { continue }
            routeById[id] = RouteInfo(
                id: id,
                shortName: row["route_short_name"] ?? id,
                longName: row["route_long_name"] ?? "",
                color: row["route_color"].flatMap { $0.isEmpty ? nil : $0 } ?? "808183",
                textColor: row["route_text_color"].flatMap { $0.isEmpty ? nil : $0 } ?? "FFFFFF",
                sortOrder: row["route_sort_order"].flatMap(Int.init) ?? 999
            )
        }

        self.stations = stations
        self.parentByStop = parentByStop
        self.routeById = routeById
        self.routes = routeById.values
            .filter { $0.id == GTFSStatic.normalizeRoute($0.id) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Loads `stops.txt` and `routes.txt` from the app's resource bundle.
    static func loadBundled() throws -> GTFSStatic {
        guard let stopsURL = Bundle.module.url(forResource: "stops", withExtension: "txt", subdirectory: "Resources"),
              let routesURL = Bundle.module.url(forResource: "routes", withExtension: "txt", subdirectory: "Resources") else {
            throw NSError(domain: "MTAMenu", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Bundled GTFS files are missing."])
        }
        return GTFSStatic(stopsCSV: try String(contentsOf: stopsURL, encoding: .utf8),
                          routesCSV: try String(contentsOf: routesURL, encoding: .utf8))
    }

    /// The parent station for any stop ID (`"127N"` → Times Sq-42 St).
    func station(forStop stopId: String) -> Station? {
        if let parent = parentByStop[stopId] { return stations[parent] }
        // Unknown stop (e.g. the static data is older than the feed): fall back to stripping the suffix.
        return stations[String(stopId.dropLast())]
    }

    /// Direction encoded in a platform stop ID, if any.
    static func direction(forStop stopId: String) -> Direction? {
        guard let last = stopId.last else { return nil }
        return Direction(rawValue: String(last))
    }

    /// Folds express variants into their parent line so `6X` shares the `6` bullet
    /// and the `6` line preference. (`6X`, `7X`, `FX` → `6`, `7`, `F`.)
    static func normalizeRoute(_ routeId: String) -> String {
        if routeId.count == 2, routeId.hasSuffix("X") { return String(routeId.prefix(1)) }
        return routeId
    }

    /// Route metadata, falling back to a neutral gray bullet for unknown IDs.
    func route(_ id: String) -> RouteInfo {
        routeById[id] ?? routeById[GTFSStatic.normalizeRoute(id)]
            ?? RouteInfo(id: id, shortName: id, longName: "", color: "808183", textColor: "FFFFFF", sortOrder: 999)
    }
}

/// A small RFC 4180-style CSV parser (handles quoted fields containing commas,
/// escaped quotes, and CRLF line endings). Returns one dictionary per row keyed
/// by the header line.
enum CSV {
    static func parse(_ text: String) -> [[String: String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character? = nil

        func next() -> Character? {
            if let p = pending { pending = nil; return p }
            return iterator.next()
        }

        while let ch = next() {
            if inQuotes {
                if ch == "\"" {
                    if let lookahead = next() {
                        if lookahead == "\"" { field.append("\"") } else { inQuotes = false; pending = lookahead }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
            } else {
                switch ch {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\r": break
                case "\n": row.append(field); rows.append(row); row = []; field = ""
                default: field.append(ch)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }

        guard let header = rows.first else { return [] }
        return rows.dropFirst().compactMap { values in
            guard values.count > 1 else { return nil }
            var dict: [String: String] = [:]
            for (i, key) in header.enumerated() where i < values.count { dict[key] = values[i] }
            return dict
        }
    }
}
