import Foundation

/// One predicted stop on a trip, from `TripUpdate.stop_time_update`.
struct RTStopTimeUpdate: Equatable {
    var stopId: String?
    /// Predicted arrival, seconds since the Unix epoch.
    var arrivalTime: Int64?
    /// Predicted departure, seconds since the Unix epoch.
    var departureTime: Int64?

    /// Best available time for "when does a train show up here".
    /// The MTA omits `arrival` for the first stop of a trip, so fall back to departure.
    var time: Int64? { arrivalTime ?? departureTime }
}

/// A `TripUpdate` entity: one train run with its upcoming stops.
struct RTTripUpdate: Equatable {
    var tripId: String?
    var routeId: String?
    var stopTimeUpdates: [RTStopTimeUpdate] = []
}

/// Decodes the subset of GTFS-Realtime we need, using `ProtobufReader`.
///
/// Field numbers come from the official schema
/// (https://gtfs.org/documentation/realtime/proto/). Only the fields listed
/// below are read; everything else (vehicle positions, alerts, the NYCT
/// extensions) is skipped.
///
/// ```
/// FeedMessage      { 2: repeated FeedEntity entity }
/// FeedEntity       { 3: TripUpdate trip_update }
/// TripUpdate       { 1: TripDescriptor trip; 2: repeated StopTimeUpdate stop_time_update }
/// TripDescriptor   { 1: string trip_id; 5: string route_id }
/// StopTimeUpdate   { 2: StopTimeEvent arrival; 3: StopTimeEvent departure; 4: string stop_id }
/// StopTimeEvent    { 2: int64 time }
/// ```
enum GTFSRealtime {
    static func parseTripUpdates(_ data: Data) throws -> [RTTripUpdate] {
        var updates: [RTTripUpdate] = []
        var feed = ProtobufReader(data)
        while let field = try feed.nextField() {
            guard field.number == 2, let entityBytes = field.value.message else { continue }
            if let update = try parseEntity(entityBytes) {
                updates.append(update)
            }
        }
        return updates
    }

    private static func parseEntity(_ bytes: ArraySlice<UInt8>) throws -> RTTripUpdate? {
        var reader = ProtobufReader(bytes)
        while let field = try reader.nextField() {
            if field.number == 3, let tripUpdateBytes = field.value.message {
                return try parseTripUpdate(tripUpdateBytes)
            }
        }
        return nil
    }

    private static func parseTripUpdate(_ bytes: ArraySlice<UInt8>) throws -> RTTripUpdate {
        var update = RTTripUpdate()
        var reader = ProtobufReader(bytes)
        while let field = try reader.nextField() {
            switch field.number {
            case 1:
                if let descriptor = field.value.message {
                    (update.tripId, update.routeId) = try parseTripDescriptor(descriptor)
                }
            case 2:
                if let stu = field.value.message {
                    update.stopTimeUpdates.append(try parseStopTimeUpdate(stu))
                }
            default:
                break
            }
        }
        return update
    }

    private static func parseTripDescriptor(_ bytes: ArraySlice<UInt8>) throws -> (tripId: String?, routeId: String?) {
        var tripId: String?
        var routeId: String?
        var reader = ProtobufReader(bytes)
        while let field = try reader.nextField() {
            switch field.number {
            case 1: tripId = field.value.string
            case 5: routeId = field.value.string
            default: break
            }
        }
        return (tripId, routeId)
    }

    private static func parseStopTimeUpdate(_ bytes: ArraySlice<UInt8>) throws -> RTStopTimeUpdate {
        var stu = RTStopTimeUpdate()
        var reader = ProtobufReader(bytes)
        while let field = try reader.nextField() {
            switch field.number {
            case 2: if let event = field.value.message { stu.arrivalTime = try parseStopTimeEvent(event) }
            case 3: if let event = field.value.message { stu.departureTime = try parseStopTimeEvent(event) }
            case 4: stu.stopId = field.value.string
            default: break
            }
        }
        return stu
    }

    private static func parseStopTimeEvent(_ bytes: ArraySlice<UInt8>) throws -> Int64? {
        var reader = ProtobufReader(bytes)
        while let field = try reader.nextField() {
            if field.number == 2 { return field.value.int64 }
        }
        return nil
    }
}
