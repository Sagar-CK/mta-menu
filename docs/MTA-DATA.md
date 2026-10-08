# MTA data sources

Subway Menu Bar uses two kinds of MTA open data. Neither requires an API key.

## Realtime: GTFS-Realtime feeds

Base URL: `https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2F<feed>`

| Feed | Lines |
| --- | --- |
| `gtfs` | 1 2 3 4 5 6 7, 42 St Shuttle (GS) |
| `gtfs-ace` | A C E, Rockaway Park Shuttle (H), Franklin Av Shuttle (FS) |
| `gtfs-bdfm` | B D F M |
| `gtfs-g` | G |
| `gtfs-jz` | J Z |
| `gtfs-nqrw` | N Q R W |
| `gtfs-l` | L |
| `gtfs-si` | Staten Island Railway (SI) |

Each feed is a protobuf `FeedMessage` (schema:
https://gtfs.org/documentation/realtime/proto/). The MTA refreshes them about
every 30 seconds; feeds are 5–150 KB each.

Fields we read:

| Message | Field | Use |
| --- | --- | --- |
| `FeedMessage` | `entity` (2) | list of entities |
| `FeedEntity` | `trip_update` (3) | we ignore `vehicle` and `alert` |
| `TripUpdate` | `trip` (1), `stop_time_update` (2) | |
| `TripDescriptor` | `trip_id` (1), `route_id` (5) | `route_id` is `N`, `6X`, etc. |
| `StopTimeUpdate` | `arrival` (2), `departure` (3), `stop_id` (4) | |
| `StopTimeEvent` | `time` (2) | Unix seconds |

Quirks worth knowing:

- The first stop of a trip has only `departure`; later stops usually have both.
  `RTStopTimeUpdate.time` prefers arrival and falls back to departure.
- `route_id` can be an express variant (`6X`, `7X`, `FX`). We normalize these.
- Stop IDs are platform-level (`R16N`). The `N`/`S` suffix is the direction.
- A stop remains in the feed until the train leaves it, so predicted times can
  be slightly in the past. We treat anything newer than 60 s ago as "now".
- The MTA extends `TripDescriptor` with `nyct_trip_descriptor` (train ID,
  direction, assignment). We skip it; everything we need is in the base schema.

Official documentation: https://api.mta.info/#/subwayRealTimeFeeds and
https://new.mta.info/developers.

## Static: GTFS bundle

Download: `https://rrgtfsfeeds.s3.amazonaws.com/gtfs_subway.zip`

We ship two files from it in `Sources/SubwayMenuBar/Resources/`:

**`stops.txt`** (~1,500 rows). Columns used: `stop_id`, `stop_name`,
`stop_lat`, `stop_lon`, `location_type`, `parent_station`. Rows with
`location_type = 1` are stations; the `…N` / `…S` rows are platforms whose
`parent_station` points at the station.

**`routes.txt`** (~30 rows). Columns used: `route_id`, `route_short_name`,
`route_long_name`, `route_color`, `route_text_color`, `route_sort_order`.
`route_color` / `route_text_color` are the MTA's official hex colors (e.g.
`FCCC0A` with black text for the N/Q/R/W), so the bullets match signage.

The bundle changes when stations open, close, or are renamed. To update,
re-download and replace the two files (see the README's Development section).
The app also tolerates stop IDs it does not know by stripping the direction
suffix and trying again.

## Terms

MTA data is provided under the MTA's developer data terms
(https://www.mta.info/developers). This project is not affiliated with the MTA.
