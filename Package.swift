// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TFYSwiftSQLiteKit",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6),
    ],
    products: [
        .library(
            name: "TFYSwiftSQLiteKit",
            targets: ["TFYSwiftSQLiteKit"]
        ),
    ],
    targets: [
        .target(
            name: "TFYSwiftSQLiteKit",
            path: "TFYSwiftSQLite/TFYSwiftSQLiteKit",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
    ]
)
