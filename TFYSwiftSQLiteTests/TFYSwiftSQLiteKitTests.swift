import XCTest
@testable import TFYSwiftSQLite

@MainActor
final class TFYSwiftSQLiteKitTests: XCTestCase {
    override func setUpWithError() throws {
        TFYSwiftDatabaseCenter.shared.closeAll()
        try TFYSwiftDatabaseCenter.shared.removeDatabase(named: User.databaseName)
        try TFYSwiftDatabaseCenter.shared.removeDatabase(named: Order.databaseName)
        try TFYSwiftDatabaseCenter.shared.removeDatabase(named: "test_json")
    }

    func testReflectionMetadataMergesWrappers() throws {
        let schema = try TFYSwiftModelMirror.schema(for: User.self)
        XCTAssertEqual(schema.tableName, "user")
        XCTAssertEqual(schema.primaryKeyColumn?.name, "id")
        XCTAssertTrue(schema.persistedColumns.contains(where: { $0.name == "username" && $0.isIndexed }))
        XCTAssertTrue(schema.persistedColumns.contains(where: { $0.name == "email" && $0.isUnique }))
        XCTAssertTrue(schema.persistedColumns.contains(where: { $0.name == "nickname" && $0.defaultSQL == "'guest'" }))
        XCTAssertFalse(schema.persistedColumns.contains(where: { $0.propertyName == "cacheOnlyField" }))
        XCTAssertTrue(schema.persistedColumns.contains(where: { $0.name == "address" && $0.storageStrategy == .json }))
    }

    func testTypeMappingAndSQLGeneration() throws {
        let schema = try TFYSwiftModelMirror.schema(for: User.self)
        let createSQL = TFYSwiftTableBuilder.createTableSQL(for: schema)
        XCTAssertTrue(createSQL.contains(#""id" INTEGER PRIMARY KEY AUTOINCREMENT"#))
        XCTAssertTrue(createSQL.contains(#""nickname" TEXT DEFAULT 'guest'"#))

        let indexes = TFYSwiftIndexBuilder.expectedIndexes(for: schema)
        XCTAssertTrue(indexes.contains(where: { $0.name == "idx_user_username" }))
        XCTAssertTrue(indexes.contains(where: { $0.name == "uidx_user_email" }))
    }

    func testSchemaMigrationAddsColumnsAndIndexesIdempotently() throws {
        _ = try LegacyUser.createTable()
        let upgrade = try User.createTable()
        XCTAssertFalse(upgrade.addedColumnSQL.isEmpty)
        XCTAssertFalse(upgrade.createdIndexSQL.isEmpty)

        let secondRun = try User.createTable()
        XCTAssertTrue(secondRun.addedColumnSQL.isEmpty)
        XCTAssertTrue(secondRun.createdIndexSQL.isEmpty)
    }

    func testCRUDRoundTripAndIgnoreField() throws {
        _ = try User.createTable()

        let user = User(
            id: 0,
            username: "bob",
            email: "bob@example.com",
            nickname: "guest",
            age: 31,
            cacheOnlyField: "memory-only",
            address: DemoAddress(city: "Hangzhou", zipCode: "310000")
        )
        try user.insert()

        guard let fetched = try User.fetchAll(where: "email = ?", bindings: [.text("bob@example.com")]).first else {
            return XCTFail("Expected to fetch inserted user.")
        }
        XCTAssertEqual(fetched.username, "bob")
        XCTAssertEqual(fetched.age, 31)
        XCTAssertEqual(fetched.address, DemoAddress(city: "Hangzhou", zipCode: "310000"))
        XCTAssertEqual(fetched.cacheOnlyField, "")
    }

    func testUniqueAndCompositeUniqueIndexes() throws {
        _ = try User.createTable()
        _ = try Order.createTable()

        try User(
            id: 0,
            username: "cindy",
            email: "cindy@example.com",
            nickname: "guest",
            age: 20,
            cacheOnlyField: "",
            address: DemoAddress(city: "Suzhou", zipCode: "215000")
        ).insert()

        XCTAssertThrowsError(
            try User(
                id: 0,
                username: "cindy2",
                email: "cindy@example.com",
                nickname: "guest",
                age: 21,
                cacheOnlyField: "",
                address: DemoAddress(city: "Ningbo", zipCode: "315000")
            ).insert()
        )

        try Order(id: 0, userID: 7, orderNo: "NO-7", amount: 88).insert()
        XCTAssertThrowsError(
            try Order(id: 0, userID: 7, orderNo: "NO-7", amount: 99).insert()
        )
    }

    func testMultiDatabaseIsolation() throws {
        _ = try User.createTable()
        _ = try Order.createTable()

        let userPath = try TFYSwiftDatabaseCenter.shared.path(named: User.databaseName)
        let orderPath = try TFYSwiftDatabaseCenter.shared.path(named: Order.databaseName)

        XCTAssertNotEqual(userPath, orderPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: userPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: orderPath))
    }
}
