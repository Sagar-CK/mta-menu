import AppKit

/// Entry point. MTAMenu is an "accessory" app: it lives in the menu bar and
/// has no Dock icon or main window.
///
/// Headless mode for debugging (works with plain `swift run`):
/// ```
/// swift run MTAMenu --print --at 40.7580,-73.9855 --lines N,A
/// ```
/// fetches the feeds once, prints the board for that location, and exits.
@main
struct MTAMenuApp {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--print") {
            printBoard(args: args)
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    private static func printBoard(args: [String]) {
        let origin = value(after: "--at", in: args).flatMap(Coordinate.parse)
            ?? Preferences.shared.manualLocation
            ?? Coordinate(latitude: 40.7580, longitude: -73.9855) // Times Square
        let lines = value(after: "--lines", in: args)
            .map { Set($0.split(separator: ",").map { String($0).uppercased() }) }
            ?? Preferences.shared.selectedRoutes

        let semaphore = DispatchSemaphore(value: 0)
        Task {
            defer { semaphore.signal() }
            do {
                let gtfs = try GTFSStatic.loadBundled()
                let pins = Preferences.shared.pinnedStops
                let feeds = MTAFeeds.feeds(for: pins.isEmpty ? lines : Set(pins.flatMap { $0.routes }))
                let fetched = await MTAFeeds.fetchTripUpdates(feeds: feeds)
                let arrivals = BoardBuilder.arrivals(from: fetched.tripUpdates, gtfs: gtfs)
                let snap = BoardBuilder.snapshot(arrivals: arrivals, gtfs: gtfs, origin: origin,
                                                 selectedRoutes: lines,
                                                 pinnedStops: Preferences.shared.pinnedStops,
                                                 nearbyRadiusMeters: Preferences.shared.nearbyRadiusMeters,
                                                 errors: fetched.errors)
                print("Location: \(origin.latitude), \(origin.longitude)   Lines: \(lines.isEmpty ? "all" : lines.sorted().joined(separator: ","))")
                print("Feeds: \(feeds.map(\.name).joined(separator: ", "))   Trips: \(fetched.tripUpdates.count)   Arrivals: \(arrivals.count)")
                print("Menu bar: " + snap.menuBar.map { "[\($0.route)] \($0.minutes)m" }.joined(separator: "  "))
                for board in snap.boards {
                    print("\n\(board.station.name) · \(formatDistance(meters: board.distanceMeters))")
                    for (direction, list) in [(Direction.north, board.northbound), (.south, board.southbound)] where !list.isEmpty {
                        print("  \(direction.label)")
                        for a in list {
                            print("    [\(a.route)] \(a.minutes(from: snap.updatedAt)) min → \(a.destination ?? "?")")
                        }
                    }
                }
                for error in fetched.errors { print("warning: \(error)") }
            } catch {
                print("error: \(error)")
            }
        }
        semaphore.wait()
    }
}
