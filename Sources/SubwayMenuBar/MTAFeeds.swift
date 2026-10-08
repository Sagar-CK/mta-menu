import Foundation

/// The MTA's public GTFS-Realtime subway feeds.
///
/// The subway system is split across eight feeds by line group. As of 2024 the
/// feeds need no API key. Reference: https://api.mta.info/#/subwayRealTimeFeeds
enum MTAFeeds {
    static let baseURL = "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2F"

    struct Feed {
        let name: String
        /// Routes (normalized IDs, see `GTFSStatic.normalizeRoute`) carried by this feed.
        let routes: Set<String>
        var url: URL { URL(string: baseURL + name)! }
    }

    static let all: [Feed] = [
        Feed(name: "gtfs",      routes: ["1", "2", "3", "4", "5", "6", "7", "GS"]),
        Feed(name: "gtfs-ace",  routes: ["A", "C", "E", "H", "FS"]),
        Feed(name: "gtfs-bdfm", routes: ["B", "D", "F", "M"]),
        Feed(name: "gtfs-g",    routes: ["G"]),
        Feed(name: "gtfs-jz",   routes: ["J", "Z"]),
        Feed(name: "gtfs-nqrw", routes: ["N", "Q", "R", "W"]),
        Feed(name: "gtfs-l",    routes: ["L"]),
        Feed(name: "gtfs-si",   routes: ["SI"]),
    ]

    /// Feeds needed to cover `routes`. An empty set means "all lines".
    static func feeds(for routes: Set<String>) -> [Feed] {
        if routes.isEmpty { return all }
        return all.filter { !$0.routes.isDisjoint(with: routes) }
    }

    struct FetchResult {
        var tripUpdates: [RTTripUpdate] = []
        var errors: [String] = []
    }

    /// Downloads and decodes the given feeds concurrently. A failing feed is
    /// reported in `errors` rather than failing the whole refresh, so one flaky
    /// feed doesn't blank out the menu bar.
    static func fetchTripUpdates(feeds: [Feed], session: URLSession = .shared) async -> FetchResult {
        await withTaskGroup(of: (String, Result<[RTTripUpdate], Error>).self) { group in
            for feed in feeds {
                group.addTask {
                    do {
                        var request = URLRequest(url: feed.url)
                        request.timeoutInterval = 10
                        request.cachePolicy = .reloadIgnoringLocalCacheData
                        let (data, response) = try await session.data(for: request)
                        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                            throw NSError(domain: "MTAFeeds", code: http.statusCode,
                                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
                        }
                        return (feed.name, .success(try GTFSRealtime.parseTripUpdates(data)))
                    } catch {
                        return (feed.name, .failure(error))
                    }
                }
            }
            var result = FetchResult()
            for await (name, outcome) in group {
                switch outcome {
                case .success(let updates): result.tripUpdates.append(contentsOf: updates)
                case .failure(let error): result.errors.append("\(name): \(error.localizedDescription)")
                }
            }
            return result
        }
    }
}
