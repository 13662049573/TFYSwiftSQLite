//
//  TFYSwiftSQLiteHardeningTests.swift
//  TFYSwiftSQLiteKit
//
//  Created by 田风有 on 2021/5/9.
//

import Foundation
import XCTest
import TFYSwiftSQLiteKit

final class TFYSwiftSQLiteHardeningTests: XCTestCase {
    override func setUpWithError() throws {
        TFYSwiftDBRuntime.setSQLLogger(nil)
        try TFYSwiftDatabaseCenter.shared.removeDatabase(named: EdgeModel.databaseName)
    }

    override func tearDownWithError() throws {
        TFYSwiftDBRuntime.setSQLLogger(nil)
        try TFYSwiftDatabaseCenter.shared.removeDatabase(named: EdgeModel.databaseName)
    }

    func testRegisteredConfigurationFlowsThroughORMAndReopen() throws {
        let config = TFYSwiftDBConfiguration(journalMode: .delete, synchronousMode: .full)
        try EdgeModel.configureDatabase(config)
        _ = try EdgeModel.createTable()
        let rowID = try EdgeModel().insertReturningRowID()
        XCTAssertEqual(rowID, 1)
        XCTAssertEqual(try EdgeModel.count(), 1)
        let center = TFYSwiftDatabaseCenter.shared
        XCTAssertEqual(try center.open(named: EdgeModel.databaseName).configuration, config)
        XCTAssertThrowsError(try center.open(named: EdgeModel.databaseName, configuration: .default))
        XCTAssertTrue(center.close(named: EdgeModel.databaseName))
        XCTAssertEqual(try center.open(named: EdgeModel.databaseName).configuration, config)
        XCTAssertEqual(try EdgeModel.fetch(byPrimaryKey: rowID)?._label, "preserved")
    }

    func testUnderscorePropertiesAndJSONFragmentsRoundTrip() throws {
        _ = try EdgeModel.createTable()
        var model = EdgeModel()
        model.fragment = "json scalar"
        model.number = 42
        model.flag = true
        try model.insert()
        let row = try XCTUnwrap(EdgeModel.fetchAll().first)
        XCTAssertEqual(row._label, "preserved")
        XCTAssertEqual(row.fragment, "json scalar")
        XCTAssertEqual(row.number, 42)
        XCTAssertTrue(row.flag)
    }

    func testSingleStatementValidationAllowsCommentsAndRejectsHiddenSQL() throws {
        let connection = try TFYSwiftDBConnection(path: ":memory:", databaseName: "validation")
        XCTAssertEqual(try connection.scalar("SELECT 1; -- comment\n /* tail */"), .integer(1))
        XCTAssertEqual(try connection.scalar("SELECT ';';"), .text(";"))
        XCTAssertThrowsError(try connection.execute("CREATE TABLE a(id); CREATE TABLE b(id);"))
        XCTAssertFalse(try connection.tableExists("a"))
        XCTAssertThrowsError(try connection.execute("SELECT 1; invalid SQL"))
        XCTAssertThrowsError(try connection.execute("SELECT 1\0; SELECT 2;"))
        XCTAssertThrowsError(try connection.execute("-- no statement"))
        XCTAssertThrowsError(try connection.execute("SELECT ?;", bindings: [.double(.nan)]))
        XCTAssertThrowsError(try TFYSwiftDBConnection(path: "test\0.db", databaseName: "invalid"))
    }

    func testStatementRetainsOwnerAndClosedCacheIsRefreshed() throws {
        var connection: TFYSwiftDBConnection? = try TFYSwiftDBConnection(path: ":memory:", databaseName: "lifetime")
        weak var weakConnection = connection
        var statement: TFYSwiftDBStatement? = try connection?.prepare("SELECT 'alive';")
        connection = nil
        XCTAssertNotNil(weakConnection)
        XCTAssertTrue(try XCTUnwrap(statement).step())
        XCTAssertEqual(statement?.value(at: 0), .text("alive"))
        statement = nil
        XCTAssertNil(weakConnection)
        weakConnection = nil
        let center = TFYSwiftDatabaseCenter.shared
        let cached = try center.open(named: EdgeModel.databaseName)
        try cached.close()
        XCTAssertTrue(try center.open(named: EdgeModel.databaseName).isOpen)
    }

    func testBackupIncludesWALMetadataAndRejectsOverwrite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let connection = try TFYSwiftDBConnection(path: directory.appendingPathComponent("source.db").path, databaseName: "backup")
        defer { try? connection.close() }
        try connection.execute("CREATE TABLE sample(id INTEGER PRIMARY KEY, value TEXT);")
        for index in 0..<100 { try connection.execute("INSERT INTO sample VALUES (?, ?);", bindings: [.integer(Int64(index)), .text("row")]) }
        try connection.execute("PRAGMA user_version = 19;")
        try connection.execute("PRAGMA application_id = 77;")
        let backup = directory.appendingPathComponent("backup.db")
        try connection.backup(to: backup)
        XCTAssertThrowsError(try connection.backup(to: backup))
        XCTAssertThrowsError(try connection.backup(to: directory.appendingPathComponent("source.db")))
        let restored = try TFYSwiftDBConnection(path: backup.path, databaseName: "restored")
        XCTAssertEqual(try restored.scalar("SELECT count(*) FROM sample;"), .integer(100))
        XCTAssertEqual(try restored.scalar("PRAGMA user_version;"), .integer(19))
        XCTAssertEqual(try restored.scalar("PRAGMA application_id;"), .integer(77))
        XCTAssertEqual(try restored.integrityCheck(), ["ok"])
        try restored.close()
        var count = 0
        try connection.forEachRow("SELECT * FROM sample;") { _ in count += 1 }
        XCTAssertEqual(count, 100)
        XCTAssertFalse(try connection.checkpoint(.truncate).busy)
        XCTAssertThrowsError(try connection.withTransaction { try connection.backup(to: directory.appendingPathComponent("unsafe.db")) })
    }

    func testRebuildPreservesTriggersIndexesAndAutoincrementHighWaterMark() throws {
        _ = try RebuildBefore.createTable()
        let connection = try TFYSwiftDatabaseCenter.shared.open(named: EdgeModel.databaseName)
        try connection.execute("CREATE TABLE audit(value INTEGER);")
        try connection.execute("CREATE TRIGGER keep_audit AFTER INSERT ON rebuild_edge BEGIN INSERT INTO audit VALUES (new.id); END;")
        try connection.execute("CREATE INDEX custom_value ON rebuild_edge(value);")
        try connection.execute("INSERT INTO rebuild_edge VALUES (100, 'high', 1);")
        try connection.execute("DELETE FROM rebuild_edge;")
        _ = try RebuildAfter.createTable()
        let id = try RebuildAfter().insertReturningRowID()
        XCTAssertEqual(id, 101)
        XCTAssertEqual(try connection.scalar("SELECT count(*) FROM audit;"), .integer(2))
        XCTAssertTrue(try connection.pragmaIndexList(tableName: "rebuild_edge").contains { $0.name == "custom_value" })
        XCTAssertFalse(try RebuildAfter.createTable().hasChanges)
    }

    func testRebuildRejectsForeignKeyCascadeAndPreservesRows() throws {
        _ = try RebuildBefore.createTable()
        let connection = try TFYSwiftDatabaseCenter.shared.open(named: EdgeModel.databaseName)
        try connection.execute("CREATE TABLE child(parent INTEGER REFERENCES rebuild_edge(id) ON DELETE CASCADE);")
        try connection.execute("INSERT INTO rebuild_edge VALUES (1, 'parent', 1);")
        try connection.execute("INSERT INTO child VALUES (1);")
        XCTAssertThrowsError(try RebuildAfter.createTable())
        XCTAssertEqual(try connection.scalar("SELECT count(*) FROM child;"), .integer(1))
        XCTAssertEqual(try connection.scalar("SELECT count(*) FROM rebuild_edge;"), .integer(1))
    }

    func testRebuildRollsBackWhenIndexReferencesRemovedColumn() throws {
        _ = try RebuildBefore.createTable()
        let connection = try TFYSwiftDatabaseCenter.shared.open(named: EdgeModel.databaseName)
        // An unmanaged index on a removed column cannot be restored: rollback is required.
        try connection.execute("CREATE INDEX old_index ON rebuild_edge(obsolete);")
        XCTAssertThrowsError(try RebuildAfter.createTable())
        XCTAssertTrue(try connection.pragmaTableInfo(tableName: "rebuild_edge").contains { $0.name == "obsolete" })
    }

    func testRebuildRollsBackWhenTriggerReferencesRemovedColumn() throws {
        _ = try RebuildBefore.createTable()
        let connection = try TFYSwiftDatabaseCenter.shared.open(named: EdgeModel.databaseName)
        try connection.execute("CREATE TABLE audit(value INTEGER);")
        try connection.execute("CREATE TRIGGER old_trigger AFTER INSERT ON rebuild_edge BEGIN INSERT INTO audit VALUES (new.obsolete); END;")
        XCTAssertThrowsError(try RebuildAfter.createTable())
        XCTAssertTrue(try connection.pragmaTableInfo(tableName: "rebuild_edge").contains { $0.name == "obsolete" })
        try RebuildBefore().insert()
        XCTAssertEqual(try connection.scalar("SELECT count(*) FROM audit;"), .integer(1))
    }

    func testLifecycleOperationsWaitForModelTransactionToCommit() throws {
        for removing in [false, true] {
            _ = try EdgeModel.createTable()
            let started = DispatchSemaphore(value: 0)
            let finished = expectation(description: "lifecycle operation completed")
            let results = ConnectionResults()
            try EdgeModel.transaction {
                try EdgeModel().insert()
                DispatchQueue.global().async {
                    started.signal()
                    do {
                        let center = TFYSwiftDatabaseCenter.shared
                        if removing { try center.removeDatabase(named: EdgeModel.databaseName) }
                        else if !center.close(named: EdgeModel.databaseName) {
                            throw TFYSwiftDBError.invalidQuery("Concurrent close failed")
                        }
                    } catch { results.append(error: error) }
                    finished.fulfill()
                }
                XCTAssertEqual(started.wait(timeout: .now() + 2), .success)
                for _ in 0..<40 {
                    XCTAssertEqual(try EdgeModel.count(), 1)
                    Thread.sleep(forTimeInterval: 0.001)
                }
                try EdgeModel().insert()
                XCTAssertEqual(try EdgeModel.count(), 2)
            }
            wait(for: [finished], timeout: 5)
            XCTAssertTrue(results.errors.isEmpty, "\(results.errors)")
            if !removing { XCTAssertEqual(try EdgeModel.count(), 2) }
            try TFYSwiftDatabaseCenter.shared.removeDatabase(named: EdgeModel.databaseName)
        }
    }

    func testPartialIndexDoesNotReplaceFullUniqueConstraint() throws {
        let connection = try TFYSwiftDatabaseCenter.shared.open(named: EdgeModel.databaseName)
        try connection.execute("CREATE TABLE indexcollisionmodel(value TEXT NOT NULL);")
        try connection.execute("CREATE UNIQUE INDEX partial_value ON indexcollisionmodel(value) WHERE value != '';")
        _ = try IndexCollisionModel.createTable()
        var model = IndexCollisionModel()
        model.value = ""
        try model.insert()
        XCTAssertThrowsError(try model.insert())
    }

    func testIndexNameComparisonIsCaseInsensitiveAndChecksDefinition() throws {
        let connection = try TFYSwiftDatabaseCenter.shared.open(named: EdgeModel.databaseName)
        try connection.execute("CREATE TABLE indexcollisionmodel(value TEXT NOT NULL);")
        try connection.execute("CREATE UNIQUE INDEX SHARED_INDEX ON indexcollisionmodel(value) WHERE value != '';")
        XCTAssertThrowsError(try IndexCollisionModel.createTable())
        try connection.execute("DROP INDEX SHARED_INDEX;")
        try connection.execute("CREATE UNIQUE INDEX SHARED_INDEX ON indexcollisionmodel(value COLLATE NOCASE);")
        XCTAssertThrowsError(try IndexCollisionModel.createTable())
        try connection.execute("DROP INDEX SHARED_INDEX;")
        try connection.execute("CREATE UNIQUE INDEX SHARED_INDEX ON indexcollisionmodel(value);")
        _ = try IndexCollisionModel.createTable()
        XCTAssertEqual(try connection.pragmaIndexList(tableName: "indexcollisionmodel").count, 1)
    }

    func testCaseInsensitiveDuplicateIdentifiersAreRejected() throws {
        XCTAssertThrowsError(try TFYSwiftModelMirror.schema(for: DuplicateCaseModel.self))
    }

    func testRebuildRejectsUnmodeledTableConstraints() throws {
        let connection = try TFYSwiftDatabaseCenter.shared.open(named: EdgeModel.databaseName)
        for constraint in ["UNIQUE", "CHECK(length(value) > 0)", "COLLATE NOCASE"] {
            try connection.execute("CREATE TABLE rebuild_edge(id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, value TEXT NOT NULL \(constraint), obsolete INTEGER NOT NULL);")
            try connection.execute("INSERT INTO rebuild_edge(value, obsolete) VALUES ('kept', 1);")
            XCTAssertThrowsError(try RebuildAfter.createTable(), constraint)
            XCTAssertEqual(try connection.scalar("SELECT value FROM rebuild_edge;"), .text("kept"))
            XCTAssertTrue(try connection.pragmaTableInfo(tableName: "rebuild_edge").contains { $0.name == "obsolete" })
            try connection.execute("DROP TABLE rebuild_edge;")
        }
    }

    func testOpenLoggerMayReenterCenterWithoutDeadlock() throws {
        var reentered = false
        TFYSwiftDBRuntime.setSQLLogger { event in
            if event.databaseName == EdgeModel.databaseName && !reentered {
                reentered = true
                // Opening the same name during initialization is rejected instead of deadlocking.
                do {
                    _ = try TFYSwiftDatabaseCenter.shared.open(named: EdgeModel.databaseName)
                    XCTFail("Expected initialization reentrancy rejection")
                } catch {}
            }
        }
        _ = try TFYSwiftDatabaseCenter.shared.open(named: EdgeModel.databaseName)
        XCTAssertTrue(reentered)
    }

    func testCustomCodingKeysAndDatabaseColumnNamesRoundTrip() throws {
        _ = try CodingKeyModel.createTable()
        var model = CodingKeyModel()
        model.label = "renamed"
        try model.insert()
        XCTAssertEqual(try CodingKeyModel.fetchAll().first?.label, "renamed")
    }

    func testCorruptedNumericStorageThrowsInsteadOfReturningZero() throws {
        _ = try StrictNumericModel.createTable()
        let connection = try TFYSwiftDatabaseCenter.shared.open(named: EdgeModel.databaseName)
        try connection.execute("INSERT INTO strictnumericmodel(number, flag) VALUES ('invalid', 1);")
        XCTAssertThrowsError(try StrictNumericModel.fetchAll())
        try connection.execute("DELETE FROM strictnumericmodel;")
        try connection.execute("INSERT INTO strictnumericmodel(number, flag) VALUES (1.5, 1);")
        XCTAssertThrowsError(try StrictNumericModel.fetchAll())
        try connection.execute("DELETE FROM strictnumericmodel;")
        try connection.execute("INSERT INTO strictnumericmodel(number, flag) VALUES (1, 2);")
        XCTAssertThrowsError(try StrictNumericModel.fetchAll())
    }

    func testPreparedStatementCanBeReusedAfterConstraintFailure() throws {
        let connection = try TFYSwiftDBConnection(path: ":memory:", databaseName: "reuse")
        try connection.execute("CREATE TABLE sample(value INTEGER UNIQUE);")
        let statement = try connection.prepare("INSERT INTO sample VALUES (?);")
        try connection.execute(statement, bindings: [.integer(1)])
        XCTAssertThrowsError(try connection.execute(statement, bindings: [.integer(1)]))
        try connection.execute(statement, bindings: [.integer(2)])
        XCTAssertEqual(try connection.scalar("SELECT count(*) FROM sample;"), .integer(2))
    }

    func testUpsertKeepsForeignKeyChildren() throws {
        _ = try RebuildAfter.createTable()
        let connection = try TFYSwiftDatabaseCenter.shared.open(named: EdgeModel.databaseName)
        try connection.execute("CREATE TABLE child(parent INTEGER REFERENCES rebuild_edge(id) ON DELETE CASCADE);")
        var model = RebuildAfter()
        model.id = 7
        try model.insert()
        try connection.execute("INSERT INTO child VALUES (7);")
        model.value = "updated"
        try model.upsert()
        XCTAssertEqual(try connection.scalar("SELECT count(*) FROM child;"), .integer(1))
        XCTAssertEqual(try RebuildAfter.fetch(byPrimaryKey: 7)?.value, "updated")
    }

    func testConcurrentFirstOpenReturnsOneSharedConnection() throws {
        let results = ConnectionResults()
        DispatchQueue.concurrentPerform(iterations: 12) { _ in
            do {
                let connection = try TFYSwiftDatabaseCenter.shared.open(named: EdgeModel.databaseName)
                results.append(connection: connection)
            } catch { results.append(error: error) }
        }
        XCTAssertTrue(results.errors.isEmpty, "\(results.errors)")
        XCTAssertEqual(Set(results.connections).count, 1)
        XCTAssertEqual(results.connections.count, 12)
    }

    func testIndexNamesCannotSilentlyCollideAcrossTables() throws {
        let connection = try TFYSwiftDatabaseCenter.shared.open(named: EdgeModel.databaseName)
        try connection.execute("CREATE TABLE other(value TEXT);")
        try connection.execute("CREATE INDEX shared_index ON other(value);")
        XCTAssertThrowsError(try IndexCollisionModel.createTable())
        XCTAssertFalse(try connection.tableExists(IndexCollisionModel.tableName))
    }

    func testRawTransactionIsNotRolledBackByFailedManagedTransaction() throws {
        let connection = try TFYSwiftDBConnection(path: ":memory:", databaseName: "raw_transaction")
        try connection.execute("CREATE TABLE sample(value INTEGER);")
        try connection.execute("BEGIN;")
        try connection.execute("INSERT INTO sample VALUES (1);")
        XCTAssertThrowsError(try connection.withTransaction { 1 })
        XCTAssertEqual(try connection.scalar("SELECT count(*) FROM sample;"), .integer(1))
        XCTAssertThrowsError(try connection.close())
        XCTAssertTrue(connection.isOpen)
        try connection.execute("ROLLBACK;")
        XCTAssertEqual(try connection.scalar("SELECT count(*) FROM sample;"), .integer(0))
        try connection.close()
    }

    func testNegativeBenchmarkIterationsDoNotTrap() {
        let report = TFYSwiftBenchmark.measure(name: "negative", iterations: -1) { _ in XCTFail("Must not execute") }
        XCTAssertEqual(report.operationsPerSecond, 0)
    }
}

private struct EdgeModel: TFYSwiftDBModel {
    @TFYPrimaryKey(autoIncrement: true) var id: Int = 0
    var _label: String = "preserved"
    @TFYColumn(storageStrategy: .json) var fragment: String = ""
    @TFYColumn(storageStrategy: .json) var number: Int = 0
    @TFYColumn(storageStrategy: .json) var flag: Bool = false
    static var databaseName: String { "test_hardening" }
}
private struct DuplicateCaseModel: TFYSwiftDBModel {
    var name = ""
    @TFYColumn(name: "NAME") var alias = ""
}
private struct RebuildBefore: TFYSwiftDBModel {
    @TFYPrimaryKey(autoIncrement: true) var id: Int = 0
    var value = ""
    var obsolete = 0
    static var databaseName: String { EdgeModel.databaseName }
    static var tableName: String { "rebuild_edge" }
}
private struct RebuildAfter: TFYSwiftDBModel {
    @TFYPrimaryKey(autoIncrement: true) var id: Int = 0
    var value = "new"
    static var databaseName: String { EdgeModel.databaseName }
    static var tableName: String { "rebuild_edge" }
    static var migrationPolicy: TFYMigrationPolicy { .rebuildTable }
}

private struct CodingKeyModel: TFYSwiftDBModel {
    @TFYColumn(name: "db_label") var label = ""
    static var databaseName: String { EdgeModel.databaseName }
    static var databaseCodingKeys: [String: String] { ["label": "json_label"] }
    enum CodingKeys: String, CodingKey { case label = "json_label" }
}
private struct StrictNumericModel: TFYSwiftDBModel {
    var number = 0
    var flag = true
    static var databaseName: String { EdgeModel.databaseName }
}

private final class ConnectionResults: @unchecked Sendable {
    private let lock = NSLock()
    var connections: [ObjectIdentifier] = []
    var errors: [String] = []
    func append(connection: TFYSwiftDBConnection) {
        lock.lock(); defer { lock.unlock() }
        connections.append(ObjectIdentifier(connection))
    }
    func append(error: Error) {
        lock.lock(); defer { lock.unlock() }
        errors.append(String(describing: error))
    }
}

private struct IndexCollisionModel: TFYSwiftDBModel {
    var value = ""
    static var databaseName: String { EdgeModel.databaseName }
    static var compositeIndexes: [TFYCompositeIndex] { [TFYCompositeIndex(columns: ["value"], unique: true, name: "shared_index")] }
}
