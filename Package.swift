// swift-tools-version: 5.9
import PackageDescription

// SwiftPM versions this package through Git tags. This manifest describes the
// source and resource layout shipped by release 1.0.7.
let libraryRoot = "TFYSwiftSQLite/TFYSwiftSQLiteKit"
let librarySources = [
    "Annotation/TFYSwiftColumnAnnotations.swift",
    "Core/TFYSwiftDBConnection.swift",
    "Core/TFYSwiftDBError.swift",
    "Core/TFYSwiftDBLogging.swift",
    "Core/TFYSwiftDBStatement.swift",
    "Manager/TFYSwiftDatabaseCenter.swift",
    "ORM/TFYSwiftColumn.swift",
    "ORM/TFYSwiftDBModel.swift",
    "ORM/TFYSwiftORM.swift",
    "ORM/TFYSwiftQuery.swift",
    "ORM/TFYSwiftTableBuilder.swift",
    "Reflection/TFYSwiftModelMirror.swift",
    "Schema/TFYSwiftAutoTable.swift",
    "Schema/TFYSwiftIndexBuilder.swift",
    "Schema/TFYSwiftSchemaMigrator.swift",
    "Utils/TFYSwiftBenchmark.swift",
    "Utils/TFYSwiftTypeMapper.swift",
]
let libraryResources = [
    "PrivacyInfo.xcprivacy",
]

let package = Package(
    name: "TFYSwiftSQLiteKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
        .tvOS(.v15),
        .watchOS(.v9),
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
            path: libraryRoot,
            sources: librarySources,
            resources: libraryResources.map { .process($0) },
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .testTarget(
            name: "TFYSwiftSQLiteKitTests",
            dependencies: ["TFYSwiftSQLiteKit"],
            path: "TFYSwiftSQLiteTests",
            sources: [
                "TestModels.swift",
                "TFYSwiftSQLiteKitTests.swift",
            ]
        ),
    ]
)
