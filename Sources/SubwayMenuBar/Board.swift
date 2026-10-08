import Foundation

/// One upcoming train at a station.
struct Arrival: Equatable {
    /// Normalized route ID (`"N"`, `"6"`, …).
    let route: String
    let stationId: String
    let direction: Direction
    let time: Date
    /// Name of the trip's last stop, e.g. "Coney Island-Stillwell Av".
    let destination: String?
    let destinationStationId: String?

    func minutes(from now: Date) -> Int {
        max(0, Int(time.timeIntervalSince(now) / 60))
    }
}

/// Everything shown for one station in the dropdown.
struct StationBoard {
    let station: Station
    let distanceMeters: Double
    let northbound: [Arrival]
    let southbound: [Arrival]
}

/// What the menu bar shows: the soonest train for each route.
struct MenuBarEntry: Equatable {
    let route: String
    let minutes: Int
}

/// A complete, immutable refresh result that the UI renders.
struct Snapshot {
    let boards: [StationBoard]
    let menuBar: [MenuBarEntry]
    let origin: Coordinate
    let updatedAt: Date
    let errors: [String]
}

/// Turns raw trip updates + static data + a location into a `Snapshot`.
enum BoardBuilder {
    /// Flattens every trip's stop list into per-station arrivals.
    static func arrivals(from updates: [RTTripUpdate], gtfs: GTFSStatic) -> [Arrival] {
        var result: [Arrival] = []
        for update in updates {
            guard let rawRoute = update.routeId, !rawRoute.isEmpty else { continue }
            let route = GTFSStatic.normalizeRoute(rawRoute)
            let lastStop = update.stopTimeUpdates.last?.stopId
            let destinationStation = lastStop.flatMap { gtfs.station(forStop: $0) }
            for stu in update.stopTimeUpdates {
                guard let stopId = stu.stopId,
                      let seconds = stu.time,
                      let station = gtfs.station(forStop: stopId),
                      let direction = GTFSStatic.direction(forStop: stopId) else { continue }
                result.append(Arrival(route: route,
                                      stationId: station.id,
                                      direction: direction,
                                      time: Date(timeIntervalSince1970: TimeInterval(seconds)),
                                      destination: destinationStation?.name,
                                      destinationStationId: destinationStation?.id))
            }
        }
        return result
    }

    /// Picks the stations to show and the trains at them.
    ///
    /// - With lines selected: for each selected line, the nearest station it
    ///   currently serves (judged by live arrivals, so it adapts to service
    ///   changes). Stations are merged and sorted by distance.
    /// - With no selection ("All lines"): the single nearest station with any
    ///   upcoming train.
    /// - `nearbyRadiusMeters` drops stations farther than that, except the
    ///   single closest one, which is always kept. This is what makes a
    ///   commute set like {1, R, W} show only the 1 at home and only the R/W
    ///   at work. `nil` means no limit.
    ///
    /// Trains that terminate at the station are dropped (you can't board them
    /// in that direction) and trains more than a minute in the past are ignored.
    static func snapshot(arrivals: [Arrival],
                         gtfs: GTFSStatic,
                         origin: Coordinate,
                         selectedRoutes: Set<String>,
                         nearbyRadiusMeters: Double? = nil,
                         now: Date = Date(),
                         errors: [String] = [],
                         maxStations: Int = 3,
                         perDirection: Int = 4,
                         maxMenuBarEntries: Int = 4) -> Snapshot {
        let cutoff = now.addingTimeInterval(-60)
        let usable = arrivals.filter { arrival in
            arrival.time >= cutoff
                && arrival.destinationStationId != arrival.stationId
                && (selectedRoutes.isEmpty || selectedRoutes.contains(arrival.route))
        }

        var byStation: [String: [Arrival]] = [:]
        for arrival in usable { byStation[arrival.stationId, default: []].append(arrival) }

        var distances: [String: Double] = [:]
        for stationId in byStation.keys {
            if let station = gtfs.stations[stationId] {
                distances[stationId] = origin.distance(to: station.coordinate)
            }
        }

        // Choose station IDs.
        var chosen: Set<String> = []
        if selectedRoutes.isEmpty {
            if let nearest = distances.min(by: { $0.value < $1.value })?.key { chosen.insert(nearest) }
        } else {
            for route in selectedRoutes {
                let candidates = byStation.filter { $0.value.contains { $0.route == route } }.keys
                if let nearest = candidates.min(by: { (distances[$0] ?? .infinity) < (distances[$1] ?? .infinity) }) {
                    chosen.insert(nearest)
                }
            }
        }

        if let radius = nearbyRadiusMeters,
           let closest = chosen.min(by: { (distances[$0] ?? .infinity) < (distances[$1] ?? .infinity) }) {
            chosen = chosen.filter { $0 == closest || (distances[$0] ?? .infinity) <= radius }
        }

        let boards: [StationBoard] = chosen
            .compactMap { id -> StationBoard? in
                guard let station = gtfs.stations[id], let distance = distances[id] else { return nil }
                let sorted = (byStation[id] ?? []).sorted { $0.time < $1.time }
                return StationBoard(station: station,
                                    distanceMeters: distance,
                                    northbound: Array(sorted.filter { $0.direction == .north }.prefix(perDirection)),
                                    southbound: Array(sorted.filter { $0.direction == .south }.prefix(perDirection)))
            }
            .sorted { $0.distanceMeters < $1.distanceMeters }
            .prefix(maxStations)
            .map { $0 }

        // Menu bar: soonest train per route across the chosen stations.
        var soonest: [String: Int] = [:]
        for board in boards {
            for arrival in board.northbound + board.southbound {
                let minutes = arrival.minutes(from: now)
                if minutes < soonest[arrival.route, default: Int.max] { soonest[arrival.route] = minutes }
            }
        }
        let menuBar = soonest
            .map { MenuBarEntry(route: $0.key, minutes: $0.value) }
            .sorted { ($0.minutes, $0.route) < ($1.minutes, $1.route) }
            .prefix(maxMenuBarEntries)
            .map { $0 }

        return Snapshot(boards: boards, menuBar: menuBar, origin: origin, updatedAt: now, errors: errors)
    }
}
