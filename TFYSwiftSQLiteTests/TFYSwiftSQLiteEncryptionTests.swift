//
//  TFYSwiftSQLiteEncryptionTests.swift
//  TFYSwiftSQLiteKit
//
//  Created by 田风有 on 2021/5/9.
//

import Foundation
import XCTest
import TFYSwiftSQLiteKit

final class TFYSwiftSQLiteEncryptionTests: XCTestCase {
    private var directory: URL!
    private let secret = "secret-'quoted-中文-\0-key"

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try TFYSwiftDatabaseCenter.shared.removeDatabase(named: CipherModel.databaseName)
    }

    override func tearDownWithError() throws {
        TFYSwiftDBRuntime.setSQLLogger(nil)
        try TFYSwiftDatabaseCenter.shared.removeDatabase(named: CipherModel.databaseName)
        try FileManager.default.removeItem(at: directory)
    }

    private func config(_ passphrase: String? = nil, compatibility: TFYSwiftDBEncryption.Compatibility = .version4) throws -> TFYSwiftDBConfiguration {
        TFYSwiftDBConfiguration(encryption: TFYSwiftDBEncryption(key: try TFYSwiftDBKey(passphrase: passphrase ?? secret), compatibility: compatibility))
    }

    private func requireCipher() throws {
        try XCTSkipUnless(TFYSwiftDBConnection.supportsEncryption, "Run swift test --traits SQLCipher to exercise the encrypted backend")
    }

    func testKeyValidationAndRedactedDescriptions() throws {
        XCTAssertThrowsError(try TFYSwiftDBKey(passphrase: ""))
        XCTAssertThrowsError(try TFYSwiftDBKey(rawKey: Data(repeating: 1, count: 31)))
        XCTAssertThrowsError(try TFYSwiftDBKey(rawKey: Data(repeating: 1, count: 32), salt: Data()))
        let key = try TFYSwiftDBKey(passphrase: secret)
        XCTAssertFalse(String(reflecting: key).contains("secret"))
        XCTAssertFalse(String(reflecting: try config()).contains("secret"))
        XCTAssertEqual(Mirror(reflecting: key).children.first?.value as? String, "<redacted>")
    }

    func testUnavailableBackendFailsBeforeCreatingPlaintext() throws {
        try XCTSkipIf(TFYSwiftDBConnection.supportsEncryption, "System backend test")
        let path = directory.appendingPathComponent("must-not-exist.db").path
        XCTAssertThrowsError(try TFYSwiftDBConnection(path: path, databaseName: "cipher", configuration: config())) { error in
            guard case TFYSwiftDBError.encryptionUnavailable = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testEncryptedFileWrongKeyAndUnkeyedOpenFail() throws {
        try requireCipher()
        let path = directory.appendingPathComponent("encrypted.db").path
        let connection = try TFYSwiftDBConnection(path: path, databaseName: "cipher", configuration: config())
        XCTAssertNotNil(try connection.cipherVersion())
        try connection.execute("CREATE TABLE secret_table(value TEXT);")
        try connection.execute("INSERT INTO secret_table VALUES (?);", bindings: [.text("confidential-marker")])
        XCTAssertEqual(try connection.integrityCheck(), ["ok"])
        XCTAssertEqual(try connection.cipherIntegrityCheck(), [])
        try connection.close()
        let file = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertNotEqual(file.prefix(16), Data("SQLite format 3\0".utf8))
        XCTAssertNil(file.range(of: Data("confidential-marker".utf8)))
        XCTAssertThrowsError(try TFYSwiftDBConnection(path: path, databaseName: "wrong", configuration: config("wrong-key")))
        XCTAssertThrowsError(try TFYSwiftDBConnection(path: path, databaseName: "unkeyed"))
        let reopened = try TFYSwiftDBConnection(path: path, databaseName: "correct", configuration: config())
        XCTAssertEqual(try reopened.scalar("SELECT value FROM secret_table;"), .text("confidential-marker"))
        try reopened.close()
    }

    func testEncryptedORMTransactionsMigrationsAndCenterRekey() throws {
        try requireCipher()
        try CipherModel.configureDatabase(config())
        _ = try CipherModel.createTable()
        try CipherModel.insert([CipherModel(), CipherModel()])
        XCTAssertEqual(try CipherModel.count(CipherModel.query().where(CipherModel.fields.value == "stored")), 2)
        XCTAssertThrowsError(try CipherModel.transaction {
            try CipherModel().insert()
            throw NSError(domain: "rollback", code: 1)
        })
        XCTAssertEqual(try CipherModel.count(), 2)
        _ = try CipherModelV2.createTable()
        XCTAssertEqual(try CipherModelV2.fetchAll().first?.added, "default")
        let center = TFYSwiftDatabaseCenter.shared
        let connection = try center.open(named: CipherModel.databaseName)
        var statement: TFYSwiftDBStatement? = try connection.prepare("SELECT 1;")
        XCTAssertNotNil(statement)
        let newKey = try TFYSwiftDBKey(passphrase: "new-passphrase")
        XCTAssertThrowsError(try center.rekey(named: CipherModel.databaseName, key: newKey))
        statement = nil
        try center.rekey(named: CipherModel.databaseName, key: newKey)
        XCTAssertTrue(center.close(named: CipherModel.databaseName))
        XCTAssertEqual(try CipherModel.count(), 2)
        let updated = try center.open(named: CipherModel.databaseName)
        XCTAssertEqual(updated.configuration.encryption?.key, newKey)
        let path = updated.path
        XCTAssertTrue(center.close(named: CipherModel.databaseName))
        XCTAssertThrowsError(try TFYSwiftDBConnection(path: path, databaseName: "old", configuration: config()))
    }

    func testPlaintextConversionEncryptedBackupDecryptionAndMetadata() throws {
        try requireCipher()
        let source = try TFYSwiftDBConnection(path: directory.appendingPathComponent("plain.db").path, databaseName: "plain")
        defer { try? source.close() }
        try source.execute("CREATE TABLE sample(id INTEGER PRIMARY KEY AUTOINCREMENT, value TEXT UNIQUE);")
        try source.execute("CREATE TABLE audit(value TEXT);")
        try source.execute("CREATE TRIGGER audit_insert AFTER INSERT ON sample BEGIN INSERT INTO audit VALUES (new.value); END;")
        try source.execute("INSERT INTO sample(value) VALUES ('before');")
        try source.execute("UPDATE sqlite_sequence SET seq = 200 WHERE name = 'sample';")
        try source.execute("PRAGMA user_version = 23;")
        try source.execute("PRAGMA application_id = 567;")
        let encryptedURL = directory.appendingPathComponent("encrypted.db")
        try source.export(to: encryptedURL, encryption: config().encryption)
        XCTAssertThrowsError(try source.export(to: encryptedURL, encryption: config().encryption))
        let encrypted = try TFYSwiftDBConnection(path: encryptedURL.path, databaseName: "encrypted", configuration: config())
        defer { try? encrypted.close() }
        XCTAssertEqual(try encrypted.scalar("PRAGMA user_version;"), .integer(23))
        XCTAssertEqual(try encrypted.scalar("PRAGMA application_id;"), .integer(567))
        XCTAssertEqual(try encrypted.executeReturningRowID("INSERT INTO sample(value) VALUES ('after');"), 201)
        XCTAssertEqual(try encrypted.scalar("SELECT count(*) FROM audit;"), .integer(2))
        let backupURL = directory.appendingPathComponent("backup.db")
        try encrypted.backup(to: backupURL)
        let backup = try TFYSwiftDBConnection(path: backupURL.path, databaseName: "backup", configuration: config())
        XCTAssertEqual(try backup.scalar("SELECT count(*) FROM sample;"), .integer(2))
        XCTAssertEqual(try backup.scalar("SELECT seq FROM sqlite_sequence WHERE name = 'sample';"), .integer(201))
        try backup.close()
        let decryptedURL = directory.appendingPathComponent("decrypted.db")
        try encrypted.export(to: decryptedURL, encryption: nil)
        let decrypted = try TFYSwiftDBConnection(path: decryptedURL.path, databaseName: "decrypted")
        XCTAssertEqual(try decrypted.scalar("SELECT count(*) FROM sample;"), .integer(2))
        XCTAssertEqual(try decrypted.scalar("PRAGMA user_version;"), .integer(23))
        try decrypted.close()
        XCTAssertEqual(try source.scalar("SELECT count(*) FROM sample;"), .integer(1))
    }

    func testKeysNeverAppearInFullSQLLogs() throws {
        try requireCipher()
        var events: [TFYSwiftSQLLogEvent] = []
        TFYSwiftDBRuntime.setSQLLogger({ events.append($0) }, bindingPolicy: .full)
        let connection = try TFYSwiftDBConnection(path: directory.appendingPathComponent("log.db").path, databaseName: "log", configuration: config())
        try connection.execute("CREATE TABLE sample(value TEXT);")
        try connection.export(to: directory.appendingPathComponent("export.db"), encryption: config().encryption)
        try connection.rekey(TFYSwiftDBKey(passphrase: "rotation-secret"))
        try connection.close()
        let descriptions = events.map { "\($0.sql) \($0.bindings) \($0.errorDescription ?? "")" }.joined()
        XCTAssertFalse(descriptions.contains("secret-"))
        XCTAssertFalse(descriptions.contains("rotation-secret"))
        XCTAssertFalse(events.contains { $0.sql.contains("ATTACH") || $0.sql.contains("PRAGMA key") || $0.sql.contains("rekey") })
    }

    func testLegacyCompatibilityRawKeyAndExportUpgrade() throws {
        try requireCipher()
        let rawKey = try TFYSwiftDBKey(rawKey: Data(repeating: 0xAB, count: 32))
        let legacyConfig = TFYSwiftDBConfiguration(encryption: TFYSwiftDBEncryption(key: rawKey, compatibility: .version3))
        let path = directory.appendingPathComponent("v3.db").path
        let connection = try TFYSwiftDBConnection(path: path, databaseName: "legacy", configuration: legacyConfig)
        try connection.execute("CREATE TABLE sample(value TEXT);")
        try connection.execute("INSERT INTO sample VALUES ('legacy');")
        try connection.close()
        let reopened = try TFYSwiftDBConnection(path: path, databaseName: "legacy", configuration: legacyConfig)
        let upgradedURL = directory.appendingPathComponent("v4.db")
        try reopened.export(to: upgradedURL, encryption: config().encryption)
        try reopened.close()
        let upgraded = try TFYSwiftDBConnection(path: upgradedURL.path, databaseName: "upgraded", configuration: config())
        XCTAssertEqual(try upgraded.scalar("SELECT value FROM sample;"), .text("legacy"))
        try upgraded.close()
    }
}

private struct CipherModel: TFYSwiftDBModel {
    @TFYPrimaryKey(autoIncrement: true) var id: Int = 0
    var value = "stored"
    static var databaseName: String { "test_sqlcipher_orm" }
    static var tableName: String { "cipher_model" }
}
private struct CipherModelV2: TFYSwiftDBModel {
    @TFYPrimaryKey(autoIncrement: true) var id: Int = 0
    var value = "stored"
    @TFYDefault("default") var added = ""
    static var databaseName: String { CipherModel.databaseName }
    static var tableName: String { CipherModel.tableName }
}
