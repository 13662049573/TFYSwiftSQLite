import XCTest
import TFYSwiftSQLiteKit

@MainActor
final class TFYSwiftSQLiteKitTests: XCTestCase {
    override func setUpWithError() throws {
        TFYSwiftDatabaseCenter.shared.closeAll()
        try TFYSwiftDatabaseCenter.shared.removeDatabase(named: User.databaseName)
        try TFYSwiftDatabaseCenter.shared.removeDatabase(named: Order.databaseName)
        try TFYSwiftDatabaseCenter.shared.removeDatabase(named: "test_json")
        try TFYSwiftDatabaseCenter.shared.removeDatabase(named: "audit")
        try TFYSwiftDatabaseCenter.shared.removeDatabase(named: "rebuild")
        TFYSwiftDBRuntime.setSQLLogger(nil)
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

    func testBatchInsertPagingAndCount() throws {
        _ = try User.createTable()

        try User.insert([
            User(id: 0, username: "u1", email: "u1@example.com", nickname: "n1", age: 10, cacheOnlyField: "", address: DemoAddress(city: "A", zipCode: "1")),
            User(id: 0, username: "u2", email: "u2@example.com", nickname: "n2", age: 20, cacheOnlyField: "", address: DemoAddress(city: "B", zipCode: "2")),
            User(id: 0, username: "u3", email: "u3@example.com", nickname: "n3", age: 30, cacheOnlyField: "", address: DemoAddress(city: "C", zipCode: "3"))
        ])

        XCTAssertEqual(try User.count(), 3)
        XCTAssertTrue(try User.exists(where: "username = ?", bindings: [.text("u2")]))

        let page = try User.fetchPage(orderBy: "\"age\" DESC", limit: 2, offset: 0)
        XCTAssertEqual(page.map(\.username), ["u3", "u2"])

        let query = User.query()
            .where((User.ageField >= 20) && User.usernameField != "u3")
            .orderBy(User.ageField.ascending())
        let typedRows = try User.fetchAll(query)
        XCTAssertEqual(typedRows.map(\.username), ["u2"])

        let generatedFieldRows = try User.fetchAll(
            User.query()
                .where((User.fields.age >= 20) && User.fields.username.starts(with: "u"))
                .orderBy(User.fields.age.descending())
        )
        XCTAssertEqual(generatedFieldRows.map(\.username), ["u3", "u2"])
    }

    func testMigrationJournalAndSQLLogger() throws {
        var events: [TFYSwiftSQLLogEvent] = []
        TFYSwiftDBRuntime.setSQLLogger { events.append($0) }

        _ = try AuditLog.createTable()
        try AuditLog.insert([
            AuditLog(id: 0, message: "a", payload: DemoAddress(city: "X", zipCode: "1")),
            AuditLog(id: 0, message: "b", payload: DemoAddress(city: "Y", zipCode: "2"))
        ])

        let connection = try TFYSwiftDatabaseCenter.shared.open(named: AuditLog.databaseName)
        let journalRows = try connection.query(
            "SELECT table_name, report_json FROM \(TFYSwiftSQL.escapeIdentifier(TFYSwiftSchemaMigrator.journalTableName)) WHERE table_name = ?;",
            bindings: [.text(AuditLog.tableName)]
        )

        XCTAssertEqual(journalRows.count, 1)
        XCTAssertTrue(events.contains(where: { $0.sql.contains("CREATE TABLE") }))
        XCTAssertTrue(events.contains(where: { $0.sql.contains("INSERT") }))
    }

    func testRebuildTableMigrationPreservesAndTransformsRows() throws {
        _ = try LegacyRebuildLog.createTable()
        try LegacyRebuildLog(id: 0, city: "Chengdu", legacyFlag: 9).insert()

        let report = try RebuiltLog.createTable()
        XCTAssertFalse(report.rebuildSQL.isEmpty)
        XCTAssertTrue(report.warnings.contains(where: { $0.contains("Rebuilt table") }))

        let rows = try RebuiltLog.fetchAll()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.message, "rebuilt")
        XCTAssertEqual(rows.first?.payload.city, "Chengdu")
        XCTAssertEqual(rows.first?.payload.zipCode, "610000")
    }

    func testBenchmarkReportsThroughput() throws {
        _ = try User.createTable()

        let report = try TFYSwiftBenchmark.write(
            User.self,
            name: "unit_write",
            iterations: 2,
            batchSize: 5
        ) { index in
            User(
                id: 0,
                username: "bench_\(index)",
                email: "bench_\(index)@example.com",
                nickname: "bench",
                age: index,
                cacheOnlyField: "",
                address: DemoAddress(city: "Bench", zipCode: "100000")
            )
        }

        XCTAssertEqual(report.iterations, 2)
        XCTAssertEqual(report.batchSize, 5)
        XCTAssertGreaterThan(report.operationsPerSecond, 0)
        XCTAssertEqual(try User.count(), 10)
    }

    func testGeneratedFieldsRejectUnknownPropertyNames() throws {
        _ = try User.createTable()

        XCTAssertThrowsError(
            try User.fetchAll(
                User.query()
                    .where(User.fields.usernme == "bob")
            )
        ) { error in
            guard case let TFYSwiftDBError.invalidModel(message) = error else {
                return XCTFail("Expected invalidModel error, got \(error)")
            }
            XCTAssertTrue(message.contains("User"))
            XCTAssertTrue(message.contains("usernme"))
        }
    }

    func testStringBasedFieldDefinitionsRejectUnknownColumns() throws {
        _ = try User.createTable()

        let invalidField = User.field("wrongName", as: String.self)
        XCTAssertThrowsError(
            try User.fetchAll(
                User.query()
                    .where(invalidField == "bob")
            )
        ) { error in
            guard case let TFYSwiftDBError.invalidModel(message) = error else {
                return XCTFail("Expected invalidModel error, got \(error)")
            }
            XCTAssertTrue(message.contains("User"))
            XCTAssertTrue(message.contains("wrongName"))
        }
    }

    func testSchemaValidationRejectsInvalidCompositeIndexColumns() throws {
        XCTAssertThrowsError(try TFYSwiftModelMirror.schema(for: InvalidCompositeIndexModel.self)) { error in
            guard case let TFYSwiftDBError.invalidModel(message) = error else {
                return XCTFail("Expected invalidModel error, got \(error)")
            }
            XCTAssertTrue(message.contains("InvalidCompositeIndexModel"))
            XCTAssertTrue(message.contains("missingColumn"))
        }
    }
}

private struct AuditLog: TFYSwiftDBModel {
    @TFYPrimaryKey(autoIncrement: true)
    var id: Int = 0

    var message: String = ""

    @TFYColumn(storageStrategy: .json)
    var payload: DemoAddress = DemoAddress()

    static var databaseName: String { "audit" }
}

private struct LegacyRebuildLog: TFYSwiftDBModel {
    @TFYPrimaryKey(autoIncrement: true)
    var id: Int = 0

    var city: String = ""
    var legacyFlag: Int = 0

    static var tableName: String { "rebuild_log" }
    static var databaseName: String { "rebuild" }
}

private struct RebuiltLog: TFYSwiftDBModel {
    @TFYPrimaryKey(autoIncrement: true)
    var id: Int = 0

    @TFYDefault("rebuilt")
    var message: String = ""

    @TFYColumn(storageStrategy: .json)
    var payload: DemoAddress = DemoAddress()

    static var tableName: String { "rebuild_log" }
    static var databaseName: String { "rebuild" }
    static var migrationPolicy: TFYMigrationPolicy { .rebuildTable }

    static func renamedColumns(for schema: TFYSwiftModelSchema, existingColumns: [TFYSQLiteTableColumnInfo]) throws -> [String: String] {
        ["message": "city"]
    }

    static func rebuildExpressions(for schema: TFYSwiftModelSchema, existingColumns: [TFYSQLiteTableColumnInfo]) throws -> [String: String] {
        [
            "payload": """
            json_object('city', COALESCE("city", ''), 'zipCode', '610000')
            """,
            "message": TFYSwiftSQL.escapeStringLiteral("rebuilt")
        ]
    }

    static func validateRebuiltTable(using connection: TFYSwiftDBConnection, schema: TFYSwiftModelSchema, plan: TFYSwiftRebuildPlan) throws {
        let rows = try connection.query(
            "SELECT COUNT(*) AS count FROM \(TFYSwiftSQL.escapeIdentifier(plan.temporaryTableName)) WHERE \"message\" IS NULL OR \"payload\" IS NULL;"
        )
        let count = rows.first?["count"].map(TFYSwiftTypeMapper.numericValue(from:)) ?? 0
        if count > 0 {
            throw TFYSwiftDBError.migrationConflict("RebuiltLog validation failed with \(count) invalid rows.")
        }
    }
}

private struct InvalidCompositeIndexModel: TFYSwiftDBModel {
    @TFYPrimaryKey(autoIncrement: true)
    var id: Int = 0

    var username: String = ""

    static var tableName: String { "invalid_index_model" }
    static var compositeIndexes: [TFYCompositeIndex] {
        [
            TFYCompositeIndex(columns: ["username", "missingColumn"], unique: true)
        ]
    }
}
