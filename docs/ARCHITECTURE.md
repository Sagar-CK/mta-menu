# Architecture

MTA Menu is a single Swift Package Manager executable target with no
third-party dependencies. The code is split into small files, each with one
job, so the data pipeline can be read top to bottom.

```
Sources/MTAMenu/
├── App.swift              Entry point; GUI run loop or --print headless mode
├── AppDelegate.swift      Status item, dropdown menu, refresh timer, actions
├── Bullets.swift          Draws route bullets; builds attributed strings for UI
├── Board.swift            Arrival / StationBoard / Snapshot models + BoardBuilder
├── MTAFeeds.swift         Feed URLs, route→feed mapping, concurrent fetching
├── GTFSRealtime.swift     Decodes TripUpdate entities from protobuf bytes
├── ProtobufDecoder.swift  Minimal protobuf wire-format reader
├── GTFSStatic.swift       Loads stops.txt / routes.txt; station & route lookups; CSV parser
├── Geo.swift              Coordinate, haversine distance, distance formatting
├── LocationService.swift  CoreLocation wrapper
├── Preferences.swift      UserDefaults-backed settings
└── Resources/             stops.txt, routes.txt (MTA static GTFS)
Tests/MTAMenuTests/  XCTest unit tests for the non-UI layers
scripts/                   build-app.sh (bundle), run.sh (bundle + launch), product-shot.swift (screenshot)
Info.plist                 Bundle metadata, LSUIElement, location usage strings
```

## Data flow

```
LocationService ─┐
Preferences ─────┼─▶ AppDelegate.refresh()
                 │        │
                 │        ▼
                 │   MTAFeeds.fetchTripUpdates(feeds:)      (network, concurrent)
                 │        │  Data per feed
                 │        ▼
                 │   GTFSRealtime.parseTripUpdates          (ProtobufReader)
                 │        │  [RTTripUpdate]
                 │        ▼
                 └─▶ BoardBuilder.arrivals(from:gtfs:)      (stop IDs → stations/directions)
                          │  [Arrival]
                          ▼
                     BoardBuilder.snapshot(...)             (pick stations, sort, cap)
                          │  Snapshot
                          ▼
                     AppDelegate.applyTitle() / rebuildMenu()   (Bullets.*)
```

Every refresh produces an immutable `Snapshot`. The UI only ever renders a
snapshot; it never mutates partial state. That keeps the menu consistent even
if a refresh is in flight when the user opens it.

## Key decisions

**Hand-written protobuf reader.** SwiftProtobuf would need `protoc` and the
`protoc-gen-swift` plugin at build time. The subset of GTFS-Realtime we read is
six message types and nine fields, so `ProtobufReader` (~100 lines) implements
just the wire format and `GTFSRealtime` walks the schema by field number.
Unknown fields, including the MTA's `nyct_trip_descriptor` extension, are
skipped safely.

**Direction from the stop ID suffix.** NYCT platform stop IDs end in `N` or
`S`. That suffix is the direction; the parent station is the ID without it (or
the `parent_station` column, which we prefer). This avoids needing
`direction_id`, which the MTA does not populate.

**Destination = last stop in the trip update.** The MTA feed includes every
remaining stop for a trip, so the last `stop_time_update` is the terminal.
This is how we show "→ Coney Island-Stillwell Av" without `trips.txt`
(which is tens of megabytes).

**Which stations serve a line is derived from live data.** The static GTFS
would need `stop_times.txt` (very large) to answer "does the N stop here?".
Instead a station "serves" a line if the live feed has an upcoming train for
that line there. A side effect is that the app naturally follows reroutes and
weekend service changes.

**Nearby radius, with the closest station always kept.** A commuter follows
the lines for both ends of the trip, but only wants to see the ones near them
right now. `BoardBuilder.snapshot` drops any chosen station beyond
`nearbyRadiusMeters`, but never the closest one, so there is always something
in the menu bar even far from the followed lines.

**Terminating trains are hidden.** If a trip's last stop is the station being
shown, the train is arriving to end its run; you cannot board it to go
anywhere in that direction, so it is filtered out.

**Express variants fold into the parent line.** `6X`, `7X`, `FX` are shown and
selected as `6`, `7`, `F`. Their bullets use the same colors on real signage.

**One feed per line group, fetched only as needed.** `MTAFeeds.feeds(for:)`
maps the selected lines to the minimal set of feeds. Following only the L
means one ~25 KB download per refresh instead of eight.

**App bundle, not a bare binary.** CoreLocation only shows the permission
prompt for an app with an `Info.plist`, and `LSUIElement` is what hides the
Dock icon. `scripts/build-app.sh` assembles the bundle from the SwiftPM build
output and ad-hoc signs it so the permission sticks.

## Concurrency

The package uses Swift tools version 5.9 (Swift 5 language mode) to keep AppKit
interop simple. `AppDelegate` is `@MainActor`. Network fetching runs in a
`TaskGroup`; parsing happens inside the same tasks. Results are handed back to
the main actor before touching the UI.

## Testing

`Tests/MTAMenuTests` covers the pure layers: the protobuf reader, the
GTFS-RT decoder (with a hand-encoded feed), the CSV/static loader, distance
formatting, and `BoardBuilder` station selection. UI code is exercised
manually and via the `--print` headless mode.
