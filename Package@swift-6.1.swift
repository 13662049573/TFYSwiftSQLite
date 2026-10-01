// swift-tools-version: 6.1
//
//  Package@swift-6.1.swift
//  TFYSwiftSQLiteKit
//
//  Created by 田风有 on 2021/5/9.
//

import PackageDescription

// SwiftPM versions this package through Git tags. This manifest describes the
// source and resource layout shipped by release 1.1.0.
let libraryRoot = "TFYSwiftSQLite/TFYSwiftSQLiteKit"
let librarySources = [
    "Annotation/TFYSwiftColumnAnnotations.swift",
    "Core/TFYSwiftDBConnection.swift",
    "Core/TFYSwiftDBError.swift",
    "Core/TFYSwiftDBEncryption.swift",
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
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9),
    ],
    products: [
        .library(
            name: "TFYSwiftSQLiteKit",
            targets: ["TFYSwiftSQLiteKit"]
        ),
    ],
    traits: [
        .trait(name: "SQLCipher", description: "Use the official SQLCipher backend for plaintext and encrypted databases"),
    ],
    dependencies: [
        .package(url: "https://github.com/sqlcipher/SQLCipher.swift.git", exact: "4.19.0"),
    ],
    targets: [
        .target(
            name: "CTFYSQLCipher",
            dependencies: [.product(name: "SQLCipher", package: "SQLCipher.swift")],
            path: "Sources/CTFYSQLCipher",
            publicHeadersPath: "include",
            cSettings: [.define("SQLITE_HAS_CODEC", to: "1")]
        ),
        .target(
            name: "TFYSwiftSQLiteKit",
            dependencies: [
                .product(name: "SQLCipher", package: "SQLCipher.swift", condition: .when(traits: ["SQLCipher"])),
                .target(name: "CTFYSQLCipher", condition: .when(traits: ["SQLCipher"])),
            ],
            path: libraryRoot,
            sources: librarySources,
            resources: libraryResources.map { .process($0) },
            swiftSettings: [
                .define("TFY_SQLCIPHER", .when(traits: ["SQLCipher"])),
            ]
        ),
        .testTarget(
            name: "TFYSwiftSQLiteKitTests",
            dependencies: ["TFYSwiftSQLiteKit"],
            path: "TFYSwiftSQLiteTests",
            sources: [
                "TestModels.swift",
                "TFYSwiftSQLiteKitTests.swift",
                "TFYSwiftSQLiteHardeningTests.swift",
                "TFYSwiftSQLiteEncryptionTests.swift",
            ]
        ),
    ]
)
