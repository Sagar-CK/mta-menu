// swift-tools-version:5.9
// MTAMenu — a macOS menu bar app for NYC subway arrivals.
// Built with Swift Package Manager only (no Xcode project required).
import PackageDescription

let package = Package(
    name: "MTAMenu",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MTAMenu",
            path: "Sources/MTAMenu",
            // stops.txt / routes.txt from the MTA static GTFS bundle are shipped
            // inside the app so it works with zero network calls for station data.
            resources: [.copy("Resources")],
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
        .testTarget(
            name: "MTAMenuTests",
            dependencies: ["MTAMenu"],
            path: "Tests/MTAMenuTests"
        ),
    ]
)
