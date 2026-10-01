// swift-tools-version: 6.1
//
//  Package.swift
//  TFYSwiftSQLiteKit
//
//  Created by 田风有 on 2021/5/9.
//

import PackageDescription

// The example app selects encryption without changing the library's default backend.
let package = Package(
    name: "TFYSQLiteDemoSupport",
    platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9)],
    products: [.library(name: "TFYSQLiteDemoSupport", targets: ["TFYSQLiteDemoSupport"])],
    dependencies: [.package(name: "TFYSwiftSQLiteKit", path: "../..", traits: ["SQLCipher"])],
    targets: [
        .target(name: "TFYSQLiteDemoSupport", dependencies: [.product(name: "TFYSwiftSQLiteKit", package: "TFYSwiftSQLiteKit")])
    ]
)
