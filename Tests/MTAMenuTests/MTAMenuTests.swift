import XCTest
@testable import MTAMenu

final class ProtobufReaderTests: XCTestCase {
    func testReadsVarintStringAndNestedMessage() throws {
        // field 1 (varint) = 300; field 2 (string) = "hi"; field 3 (message) = { field 1 varint = 1 }
        let bytes: [UInt8] = [0x08, 0xAC, 0x02, 0x12, 0x02, 0x68, 0x69, 0x1A, 0x02, 0x08, 0x01]
        var reader = ProtobufReader(bytes[...])

        let f1 = try XCTUnwrap(try reader.nextField())
        XCTAssertEqual(f1.number, 1)
        XCTAssertEqual(f1.value.int64, 300)

        let f2 = try XCTUnwrap(try reader.nextField())
        XCTAssertEqual(f2.number, 2)
        XCTAssertEqual(f2.value.string, "hi")

        let f3 = try XCTUnwrap(try reader.nextField())
        XCTAssertEqual(f3.number, 3)
        var nested = ProtobufReader(try XCTUnwrap(f3.value.message))
        let inner = try XCTUnwrap(try nested.nextField())
        XCTAssertEqual(inner.value.int64, 1)
        XCTAssertNil(try reader.nextField())
    }

    func testTruncatedMessageThrows() {
        var reader = ProtobufReader([0x12, 0x05, 0x68][...])
        XCTAssertThrowsError(try reader.nextField())
    }
}

final class GTFSRealtimeTests: XCTestCase {
    /// Hand-encoded FeedMessage with one entity:
    /// trip_update { trip { trip_id "t1", route_id "N" }
    ///               stop_time_update { arrival { time 1000 } stop_id "R16N" }
    ///               stop_time_update { departure { time 2000 } stop_id "R01N" } }
    func testParsesTripUpdate() throws {
        /// Wraps `payload` as a length-delimited field with the given tag byte.
        func field(_ tag: UInt8, _ payload: [UInt8]) -> [UInt8] { [tag, UInt8(payload.count)] + payload }

        let trip: [UInt8] = [0x0A, 0x02, 0x74, 0x31, 0x2A, 0x01, 0x4E]            // trip_id "t1", route_id "N"
        var stu1: [UInt8] = [0x12, 0x03, 0x10, 0xE8, 0x07, 0x22, 0x04]            // arrival.time 1000, stop_id…
        stu1 += Array("R16N".utf8)
        var stu2: [UInt8] = [0x1A, 0x03, 0x10, 0xD0, 0x0F, 0x22, 0x04]            // departure.time 2000, stop_id…
        stu2 += Array("R01N".utf8)
        var tripUpdate: [UInt8] = field(0x0A, trip)
        tripUpdate += field(0x12, stu1)
        tripUpdate += field(0x12, stu2)
        var entity: [UInt8] = [0x0A, 0x01, 0x31]                                  // id "1"
        entity += field(0x1A, tripUpdate)
        let feed: [UInt8] = field(0x12, entity)

        let updates = try GTFSRealtime.parseTripUpdates(Data(feed))
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates[0].tripId, "t1")
        XCTAssertEqual(updates[0].routeId, "N")
        XCTAssertEqual(updates[0].stopTimeUpdates.map(\.stopId), ["R16N", "R01N"])
        XCTAssertEqual(updates[0].stopTimeUpdates.map(\.time), [1000, 2000])
    }
}

final class GTFSStaticTests: XCTestCase {
    static let stops = """
    stop_id,stop_name,stop_lat,stop_lon,location_type,parent_station
    R16,Times Sq-42 St,40.754672,-73.986754,1,
    R16N,Times Sq-42 St,40.754672,-73.986754,,R16
    R16S,Times Sq-42 St,40.754672,-73.986754,,R16
    R01,Astoria-Ditmars Blvd,40.775036,-73.912034,1,
    R01N,Astoria-Ditmars Blvd,40.775036,-73.912034,,R01
    R01S,Astoria-Ditmars Blvd,40.775036,-73.912034,,R01
    A27,42 St-Port Authority,40.757308,-73.989735,1,
    A27N,42 St-Port Authority,40.757308,-73.989735,,A27
    A27S,42 St-Port Authority,40.757308,-73.989735,,A27
    A31,14 St,40.740893,-74.00169,1,
    A31N,14 St,40.740893,-74.00169,,A31
    A31S,14 St,40.740893,-74.00169,,A31
    """
    static let routes = """
    route_id,agency_id,route_short_name,route_long_name,route_desc,route_type,route_url,route_color,route_text_color,route_sort_order
    N,MTA NYCT,N,Broadway Express,"Trains, with commas, in quotes",1,,FCCC0A,000000,14
    A,MTA NYCT,A,8 Avenue Express,"desc",1,,0062CF,FFFFFF,1
    6X,MTA NYCT,6X,Pelham Express,"desc",1,,00A65C,FFFFFF,25
    """
    let gtfs = GTFSStatic(stopsCSV: stops, routesCSV: routes)

    func testParsesStationsAndRoutes() {
        XCTAssertEqual(gtfs.stations.count, 4)
        XCTAssertEqual(gtfs.station(forStop: "R16S")?.name, "Times Sq-42 St")
        XCTAssertEqual(GTFSStatic.direction(forStop: "R16S"), .south)
        XCTAssertEqual(gtfs.route("N").color, "FCCC0A")
        XCTAssertEqual(gtfs.route("N").longName, "Broadway Express")
        XCTAssertEqual(gtfs.routes.map(\.id), ["A", "N"], "express variants are hidden from the line picker")
        XCTAssertEqual(GTFSStatic.normalizeRoute("6X"), "6")
    }

    func testBoardBuilderPicksNearestStationPerLine() {
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let updates = [
            RTTripUpdate(tripId: "n1", routeId: "N", stopTimeUpdates: [
                RTStopTimeUpdate(stopId: "R16N", arrivalTime: Int64(now.timeIntervalSince1970) + 120),
                RTStopTimeUpdate(stopId: "R01N", arrivalTime: Int64(now.timeIntervalSince1970) + 900),
            ]),
            RTTripUpdate(tripId: "a1", routeId: "A", stopTimeUpdates: [
                RTStopTimeUpdate(stopId: "A27S", arrivalTime: Int64(now.timeIntervalSince1970) + 240),
                RTStopTimeUpdate(stopId: "A31S", arrivalTime: Int64(now.timeIntervalSince1970) + 600),
            ]),
        ]
        let arrivals = BoardBuilder.arrivals(from: updates, gtfs: gtfs)
        XCTAssertEqual(arrivals.count, 4)

        // Standing at Times Square, listening to N and A.
        let origin = Coordinate(latitude: 40.7558, longitude: -73.9862)
        let snap = BoardBuilder.snapshot(arrivals: arrivals, gtfs: gtfs, origin: origin,
                                         selectedRoutes: ["N", "A"], now: now)
        XCTAssertEqual(snap.boards.map(\.station.id).sorted(), ["A27", "R16"])
        XCTAssertEqual(snap.menuBar, [MenuBarEntry(route: "N", minutes: 2), MenuBarEntry(route: "A", minutes: 4)])

        let times = snap.boards.first { $0.station.id == "R16" }!
        XCTAssertEqual(times.northbound.first?.destination, "Astoria-Ditmars Blvd")
        XCTAssertTrue(times.southbound.isEmpty)
        let portAuthority = snap.boards.first { $0.station.id == "A27" }!
        XCTAssertEqual(portAuthority.southbound.first?.destination, "14 St")

        // Terminating trains are not shown at their last stop.
        let astoria = BoardBuilder.snapshot(arrivals: arrivals, gtfs: gtfs,
                                            origin: Coordinate(latitude: 40.775, longitude: -73.912),
                                            selectedRoutes: ["N"], now: now)
        XCTAssertEqual(astoria.boards.first?.station.id, "R16")
    }

    func testNearbyRadiusHidesFarLinesButKeepsClosest() {
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let updates = [
            RTTripUpdate(tripId: "n1", routeId: "N", stopTimeUpdates: [
                RTStopTimeUpdate(stopId: "R16N", arrivalTime: Int64(now.timeIntervalSince1970) + 120),
                RTStopTimeUpdate(stopId: "R01N", arrivalTime: Int64(now.timeIntervalSince1970) + 900),
            ]),
            RTTripUpdate(tripId: "a1", routeId: "A", stopTimeUpdates: [
                RTStopTimeUpdate(stopId: "A27S", arrivalTime: Int64(now.timeIntervalSince1970) + 240),
                RTStopTimeUpdate(stopId: "A31S", arrivalTime: Int64(now.timeIntervalSince1970) + 600),
            ]),
        ]
        let arrivals = BoardBuilder.arrivals(from: updates, gtfs: gtfs)

        // Standing right at Port Authority (A); Times Sq (N) is ~350 m away.
        let origin = Coordinate(latitude: 40.757308, longitude: -73.989735)
        let wide = BoardBuilder.snapshot(arrivals: arrivals, gtfs: gtfs, origin: origin,
                                         selectedRoutes: ["N", "A"], nearbyRadiusMeters: 800, now: now)
        XCTAssertEqual(wide.boards.map(\.station.id).sorted(), ["A27", "R16"])

        let tight = BoardBuilder.snapshot(arrivals: arrivals, gtfs: gtfs, origin: origin,
                                          selectedRoutes: ["N", "A"], nearbyRadiusMeters: 100, now: now)
        XCTAssertEqual(tight.boards.map(\.station.id), ["A27"], "N is outside the radius, A is closest")
        XCTAssertEqual(tight.menuBar, [MenuBarEntry(route: "A", minutes: 4)])

        // Far from everything: the closest station is still shown.
        let far = BoardBuilder.snapshot(arrivals: arrivals, gtfs: gtfs,
                                        origin: Coordinate(latitude: 40.70, longitude: -74.01),
                                        selectedRoutes: ["N", "A"], nearbyRadiusMeters: 100, now: now)
        XCTAssertEqual(far.boards.count, 1)
    }

    func testDistanceFormatting() {
        XCTAssertEqual(formatDistance(meters: 100), "328 ft")
        XCTAssertEqual(formatDistance(meters: 800), "0.5 mi")
    }
}
