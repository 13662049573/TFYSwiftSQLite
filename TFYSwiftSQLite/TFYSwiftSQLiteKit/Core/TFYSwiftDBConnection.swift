//
//  TFYSwiftDBConnection.swift
//  TFYSwiftSQLiteKit
//
//  Created by 田风有 on 2021/5/9.
//

import Foundation
import Darwin
#if TFY_SQLCIPHER
import SQLCipher
#if SWIFT_PACKAGE
import CTFYSQLCipher
#endif
#else
import SQLite3
#endif

public struct TFYSwiftDBConfiguration: Equatable, Sendable {
    public enum JournalMode: String, Sendable {
        case delete
        case truncate
        case persist
        case memory
        case wal
        case off
    }

    public enum SynchronousMode: String, Sendable {
        case off = "OFF"
        case normal = "NORMAL"
        case full = "FULL"
        case extra = "EXTRA"
    }

    public static let `default` = TFYSwiftDBConfiguration()

    public var foreignKeysEnabled: Bool
    public var journalMode: JournalMode
    public var synchronousMode: SynchronousMode
    public var busyTimeout: TimeInterval
    public var walAutoCheckpoint: Int?
    public var encryption: TFYSwiftDBEncryption?

    public init(
        foreignKeysEnabled: Bool = true,
        journalMode: JournalMode = .wal,
        synchronousMode: SynchronousMode = .normal,
        busyTimeout: TimeInterval = 5,
        walAutoCheckpoint: Int? = 1_000,
        encryption: TFYSwiftDBEncryption? = nil
    ) {
        self.foreignKeysEnabled = foreignKeysEnabled
        self.journalMode = journalMode
        self.synchronousMode = synchronousMode
        self.busyTimeout = busyTimeout
        self.walAutoCheckpoint = walAutoCheckpoint
        self.encryption = encryption
    }
}

public struct TFYSQLiteTableColumnInfo: Equatable, Sendable {
    public let name: String
    public let type: String
    public let defaultValueSQL: String?
    public let isPrimaryKey: Bool
    public let isNotNull: Bool
}

public struct TFYSQLiteIndexInfo: Equatable, Sendable {
    public let name: String
    public let columns: [String]
    public let unique: Bool
    public let isPartial: Bool
    /// Expressions, descending keys or a non-BINARY collation cannot satisfy a plain ORM index.
    public let usesCustomComparison: Bool
}

public final class TFYSwiftDBConnection: @unchecked Sendable {
    public let databaseName: String
    public let path: String
    private var storedConfiguration: TFYSwiftDBConfiguration
    public var configuration: TFYSwiftDBConfiguration {
        withConnectionLock { storedConfiguration }
    }

    private var handle: OpaquePointer?
    private let connectionLock = NSRecursiveLock()
    private var transactionDepth = 0

    public init(
        path: String,
        databaseName: String,
        configuration: TFYSwiftDBConfiguration = .default
    ) throws {
        try Self.validate(configuration)
        guard !path.utf8.contains(0), !path.isEmpty else {
            throw TFYSwiftDBError.invalidConfiguration("Database path must be non-empty and contain no NUL bytes.")
        }
        self.databaseName = databaseName
        self.path = path
        self.storedConfiguration = configuration

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let code = sqlite3_open_v2(path, &database, flags, nil)
        guard code == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error."
            sqlite3_close(database)
            throw TFYSwiftDBError.openDatabase(path: path, message: message)
        }
        handle = database

        do {
            sqlite3_extended_result_codes(database, 1)
            try applyEncryption(configuration.encryption, to: database)
            let timeoutMilliseconds = Int32((configuration.busyTimeout * 1_000).rounded())
            let timeoutCode = sqlite3_busy_timeout(database, timeoutMilliseconds)
            guard timeoutCode == SQLITE_OK else {
                throw TFYSwiftDBError.invalidConfiguration(
                    "Failed to configure SQLite busy timeout: \(String(cString: sqlite3_errmsg(database)))."
                )
            }

            try execute("PRAGMA foreign_keys = \(configuration.foreignKeysEnabled ? "ON" : "OFF");")
            try execute("PRAGMA journal_mode = \(configuration.journalMode.rawValue.uppercased());")
            try execute("PRAGMA synchronous = \(configuration.synchronousMode.rawValue);")
            if configuration.journalMode == .wal, let checkpoint = configuration.walAutoCheckpoint {
                try execute("PRAGMA wal_autocheckpoint = \(checkpoint);")
            }
        } catch {
            sqlite3_close_v2(database)
            handle = nil
            throw error
        }
    }

    deinit {
        connectionLock.lock()
        if let handle {
            sqlite3_close_v2(handle)
            self.handle = nil
        }
        connectionLock.unlock()
    }

    public var isOpen: Bool {
        withConnectionLock { handle != nil }
    }

    public var lastInsertedRowID: Int64 {
        withConnectionLock {
            guard let handle else { return 0 }
            return sqlite3_last_insert_rowid(handle)
        }
    }

    /// Number of rows changed by the most recently completed INSERT, UPDATE, or DELETE.
    public var changes: Int64 {
        withConnectionLock {
            guard let handle else { return 0 }
            if #available(iOS 15.4, macOS 12.3, tvOS 15.4, watchOS 8.5, *) {
                return sqlite3_changes64(handle)
            }
            return Int64(sqlite3_changes(handle))
        }
    }

    /// Total number of rows changed since this connection was opened.
    public var totalChanges: Int64 {
        withConnectionLock {
            guard let handle else { return 0 }
            if #available(iOS 15.4, macOS 12.3, tvOS 15.4, watchOS 8.5, *) {
                return sqlite3_total_changes64(handle)
            }
            return Int64(sqlite3_total_changes(handle))
        }
    }

    public func close() throws {
        try withConnectionLock {
            guard let handle else { return }
            guard transactionDepth == 0, sqlite3_get_autocommit(handle) != 0 else {
                throw TFYSwiftDBError.closeDatabase(
                    path: path,
                    message: "Cannot close a database from inside an active transaction."
                )
            }
            // sqlite3_close_v2 reports success while outstanding statements keep a
            // zombie connection alive. A public close must instead fail visibly so
            // callers do not remove or replace a database that is still in use.
            let code = sqlite3_close(handle)
            guard code == SQLITE_OK else {
                throw TFYSwiftDBError.closeDatabase(
                    path: path,
                    message: String(cString: sqlite3_errmsg(handle))
                )
            }
            self.handle = nil
            transactionDepth = 0
        }
    }

    public func execute(_ sql: String, bindings: [TFYSQLiteBindValue?] = []) throws {
        try withConnectionLock {
            let handle = try requireHandle()
            try measure(sql, bindings: bindings) {
                let statement = try TFYSwiftDBStatement(
                    connection: handle,
                    sql: sql,
                    connectionLock: connectionLock
                )
                try statement.bind(bindings)
                while try statement.step() {}
            }
        }
    }

    public func prepare(_ sql: String) throws -> TFYSwiftDBStatement {
        try withConnectionLock {
            try TFYSwiftDBStatement(
                connection: requireHandle(),
                sql: sql,
                connectionLock: connectionLock,
                owner: self
            )
        }
    }

    public func execute(_ statement: TFYSwiftDBStatement, bindings: [TFYSQLiteBindValue?] = []) throws {
        try withConnectionLock {
            let handle = try requireHandle()
            guard statement.belongs(to: handle) else {
                throw TFYSwiftDBError.invalidQuery("A prepared statement must be executed by the connection that created it.")
            }
            try measure(statement.sql, bindings: bindings) {
                statement.resetForReuse()
                try statement.clearBindings()
                try statement.bind(bindings)
                while try statement.step() {}
            }
        }
    }

    public func query(_ sql: String, bindings: [TFYSQLiteBindValue?] = []) throws -> [[String: TFYSQLiteValue]] {
        try withConnectionLock {
            let handle = try requireHandle()
            return try measure(sql, bindings: bindings) {
                let statement = try TFYSwiftDBStatement(
                    connection: handle,
                    sql: sql,
                    connectionLock: connectionLock
                )
                try statement.bind(bindings)

                var rows: [[String: TFYSQLiteValue]] = []
                while try statement.step() {
                    rows.append(statement.row())
                }
                return rows
            }
        }
    }

    public func query(
        _ statement: TFYSwiftDBStatement,
        bindings: [TFYSQLiteBindValue?] = []
    ) throws -> [[String: TFYSQLiteValue]] {
        try withConnectionLock {
            let handle = try requireHandle()
            guard statement.belongs(to: handle) else {
                throw TFYSwiftDBError.invalidQuery("A prepared statement must be queried by the connection that created it.")
            }
            return try measure(statement.sql, bindings: bindings) {
                statement.resetForReuse()
                try statement.clearBindings()
                try statement.bind(bindings)

                var rows: [[String: TFYSQLiteValue]] = []
                while try statement.step() {
                    rows.append(statement.row())
                }
                return rows
            }
        }
    }

    public func withTransaction<T>(_ block: () throws -> T) throws -> T {
        try withConnectionLock {
            let database = try requireHandle()
            let currentDepth = transactionDepth
            guard currentDepth > 0 || sqlite3_get_autocommit(database) != 0 else {
                throw TFYSwiftDBError.invalidQuery("A raw SQL transaction is already active. Finish it before using withTransaction.")
            }
            transactionDepth += 1
            let savepointName = "tfy_savepoint_\(transactionDepth)"

            do {
                if currentDepth == 0 {
                    try execute("BEGIN IMMEDIATE TRANSACTION;")
                } else {
                    try execute("SAVEPOINT \(TFYSwiftSQL.escapeIdentifier(savepointName));")
                }

                let result = try block()
                if currentDepth == 0 {
                    try execute("COMMIT;")
                } else {
                    try execute("RELEASE SAVEPOINT \(TFYSwiftSQL.escapeIdentifier(savepointName));")
                }
                transactionDepth -= 1
                return result
            } catch {
                if currentDepth == 0 {
                    try? execute("ROLLBACK;")
                } else {
                    try? execute("ROLLBACK TO SAVEPOINT \(TFYSwiftSQL.escapeIdentifier(savepointName));")
                    try? execute("RELEASE SAVEPOINT \(TFYSwiftSQL.escapeIdentifier(savepointName));")
                }
                transactionDepth -= 1
                throw error
            }
        }
    }

    public func tableExists(_ tableName: String) throws -> Bool {
        let rows = try query(
            """
            SELECT name FROM sqlite_master
            WHERE type = 'table' AND name = ? COLLATE NOCASE;
            """,
            bindings: [.text(tableName)]
        )
        return !rows.isEmpty
    }

    public func pragmaTableInfo(tableName: String) throws -> [TFYSQLiteTableColumnInfo] {
        let rows = try query("PRAGMA table_info(\(TFYSwiftSQL.escapeIdentifier(tableName)));")
        return rows.compactMap { row in
            guard let name = row["name"].map(TFYSwiftTypeMapper.stringValue),
                  let type = row["type"].map(TFYSwiftTypeMapper.stringValue) else {
                return nil
            }
            return TFYSQLiteTableColumnInfo(
                name: name,
                type: type,
                defaultValueSQL: row["dflt_value"].flatMap { $0 == .null ? nil : TFYSwiftTypeMapper.stringValue(from: $0) },
                isPrimaryKey: (row["pk"].map(TFYSwiftTypeMapper.numericValue(from:)) ?? 0) > 0,
                isNotNull: row["notnull"].map(TFYSwiftTypeMapper.numericValue(from:)) == 1
            )
        }
    }

    public func pragmaIndexList(tableName: String) throws -> [TFYSQLiteIndexInfo] {
        let listRows = try query("PRAGMA index_list(\(TFYSwiftSQL.escapeIdentifier(tableName)));")
        var indexes: [TFYSQLiteIndexInfo] = []

        for row in listRows {
            guard let nameValue = row["name"] else { continue }
            let name = TFYSwiftTypeMapper.stringValue(from: nameValue)
            if name.hasPrefix("sqlite_autoindex") {
                continue
            }
            let unique = row["unique"].map(TFYSwiftTypeMapper.numericValue(from:)) == 1
            let infoRows = try query("PRAGMA index_xinfo(\(TFYSwiftSQL.escapeIdentifier(name)));")
            let keyRows = infoRows.filter { $0["key"] == .integer(1) }
            let columns = keyRows.sorted {
                TFYSwiftTypeMapper.numericValue(from: $0["seqno"] ?? .integer(0)) <
                TFYSwiftTypeMapper.numericValue(from: $1["seqno"] ?? .integer(0))
            }.compactMap { infoRow -> String? in
                guard case let .text(name)? = infoRow["name"] else { return nil }
                return name
            }
            let custom = keyRows.contains {
                guard case let .text(collation)? = $0["coll"] else { return true }
                return $0["name"] == .null || $0["desc"] == .integer(1) || collation.caseInsensitiveCompare("BINARY") != .orderedSame
            }
            indexes.append(TFYSQLiteIndexInfo(name: name, columns: columns, unique: unique,
                                              isPartial: row["partial"] == .integer(1), usesCustomComparison: custom))
        }

        return indexes
    }

    public func scalar(_ sql: String, bindings: [TFYSQLiteBindValue?] = []) throws -> TFYSQLiteValue? {
        try withConnectionLock {
            let handle = try requireHandle()
            return try measure(sql, bindings: bindings) {
                let statement = try TFYSwiftDBStatement(
                    connection: handle,
                    sql: sql,
                    connectionLock: connectionLock
                )
                try statement.bind(bindings)
                guard try statement.step() else { return nil }
                return statement.value(at: 0)
            }
        }
    }

    /// SQLCipher is an explicitly selected backend; encryption never falls back to plaintext.
    public static var supportsEncryption: Bool {
        #if TFY_SQLCIPHER
        true
        #else
        false
        #endif
    }

    public var isEncrypted: Bool { configuration.encryption != nil }

    public func cipherVersion() throws -> String? {
        guard Self.supportsEncryption else { return nil }
        guard case let .text(version)? = try scalar("PRAGMA cipher_version;") else { return nil }
        return version
    }

    /// Changes an already encrypted database's key. The key is never passed through SQL logging.
    public func rekey(_ key: TFYSwiftDBKey) throws {
        try withConnectionLock {
            let database = try requireHandle()
            guard transactionDepth == 0, sqlite3_get_autocommit(database) != 0,
                  sqlite3_next_stmt(database, nil) == nil else {
                throw TFYSwiftDBError.encryption("Rekey requires no active transaction or prepared statements.")
            }
            guard let encryption = storedConfiguration.encryption else {
                throw TFYSwiftDBError.encryption("Use export(to:encryption:) to encrypt a plaintext database.")
            }
            #if TFY_SQLCIPHER
            let code = key.withBytes {
                #if SWIFT_PACKAGE
                tfy_sqlcipher_rekey(UnsafeMutableRawPointer(database), $0, $1)
                #else
                sqlite3_rekey(database, $0, $1)
                #endif
            }
            guard code == SQLITE_OK else {
                throw TFYSwiftDBError.encryption("SQLCipher rekey failed (code \(code)).")
            }
            storedConfiguration.encryption = TFYSwiftDBEncryption(key: key, compatibility: encryption.compatibility)
            #else
            throw TFYSwiftDBError.encryptionUnavailable
            #endif
        }
    }

    public enum CheckpointMode: Int32, Sendable {
        case passive = 0, full = 1, restart = 2, truncate = 3
    }

    public struct CheckpointResult: Equatable, Sendable {
        public let busy: Bool
        public let logFrames: Int32
        public let checkpointedFrames: Int32
    }

    public func checkpoint(_ mode: CheckpointMode = .passive) throws -> CheckpointResult {
        try withConnectionLock {
            let database = try requireHandle()
            try requireMaintenanceState(database)
            var logFrames: Int32 = 0
            var checkpointedFrames: Int32 = 0
            let code = sqlite3_wal_checkpoint_v2(database, "main", mode.rawValue, &logFrames, &checkpointedFrames)
            guard code == SQLITE_OK || code == SQLITE_BUSY else {
                throw TFYSwiftDBError.maintenance("WAL checkpoint failed (code \(code)).")
            }
            return CheckpointResult(busy: code == SQLITE_BUSY, logFrames: logFrames, checkpointedFrames: checkpointedFrames)
        }
    }

    public func integrityCheck() throws -> [String] {
        try query("PRAGMA integrity_check;").flatMap { $0.values.map(TFYSwiftTypeMapper.stringValue(from:)) }
    }

    /// SQLCipher HMAC validation returns no rows on success.
    public func cipherIntegrityCheck() throws -> [String] {
        guard Self.supportsEncryption, isEncrypted else {
            throw TFYSwiftDBError.encryption("Cipher integrity checks require an encrypted SQLCipher connection.")
        }
        return try query("PRAGMA cipher_integrity_check;").flatMap { $0.values.map(TFYSwiftTypeMapper.stringValue(from:)) }
    }

    /// Visits rows without materializing the entire result. The connection is locked for the callback duration.
    /// Do not wait for another thread using this connection inside the callback.
    public func forEachRow(
        _ sql: String,
        bindings: [TFYSQLiteBindValue?] = [],
        _ body: ([String: TFYSQLiteValue]) throws -> Void
    ) throws {
        try withConnectionLock {
            let statement = try prepare(sql)
            try measure(sql, bindings: bindings) {
                try statement.bind(bindings)
                while try statement.step() { try body(statement.row()) }
            }
        }
    }

    /// Captures the row ID under the same lock as INSERT, preventing competing inserts from replacing it.
    @discardableResult
    public func executeReturningRowID(_ sql: String, bindings: [TFYSQLiteBindValue?] = []) throws -> Int64 {
        try withConnectionLock {
            try execute(sql, bindings: bindings)
            return lastInsertedRowID
        }
    }

    /// A consistent file backup including committed WAL data. Never overwrites an existing destination.
    /// SQLCipher connections use export so the destination keeps the same encryption settings.
    public func backup(to destination: URL) throws {
        if let encryption = configuration.encryption {
            try export(to: destination, encryption: encryption)
            return
        }
        try withConnectionLock {
            let database = try requireHandle()
            try requireMaintenanceState(database)
            let destinationPath = try reserveDestination(destination)
            var succeeded = false
            defer { if !succeeded { Self.removeExportFiles(at: destinationPath) } }
            let target = try TFYSwiftDBConnection(
                path: destinationPath, databaseName: "backup",
                configuration: TFYSwiftDBConfiguration(journalMode: .delete, synchronousMode: .full)
            )
            do {
                guard let backup = sqlite3_backup_init(try target.requireHandle(), "main", database, "main") else {
                    throw TFYSwiftDBError.maintenance("Unable to initialize SQLite backup.")
                }
                let stepCode = sqlite3_backup_step(backup, -1)
                let finishCode = sqlite3_backup_finish(backup)
                guard stepCode == SQLITE_DONE, finishCode == SQLITE_OK else {
                    throw TFYSwiftDBError.maintenance("SQLite backup failed (code \(stepCode), finish \(finishCode)).")
                }
                guard try target.integrityCheck() == ["ok"] else {
                    throw TFYSwiftDBError.maintenance("Backup integrity check failed.")
                }
                try target.close()
                succeeded = true
            } catch {
                try? target.close()
                throw error
            }
        }
    }

    /// Copies a snapshot into a NEW file. nil encryption exports plaintext; a key encrypts it.
    /// Use this for plaintext→SQLCipher conversion, decryption, or format upgrades; the source is preserved.
    /// Encryption operations bypass the SQL logger even under bindingPolicy: .full.
    public func export(to destination: URL, encryption: TFYSwiftDBEncryption?) throws {
        #if TFY_SQLCIPHER
        try withConnectionLock {
            let database = try requireHandle()
            try requireMaintenanceState(database)
            guard let version = try cipherVersion(), !version.isEmpty else {
                throw TFYSwiftDBError.encryptionUnavailable
            }
            let destinationPath = try reserveDestination(destination)
            var succeeded = false
            defer { if !succeeded { Self.removeExportFiles(at: destinationPath) } }
            var attached = false
            do {
                try executeWithoutLogging(
                    "ATTACH DATABASE ? AS tfy_export KEY ?;",
                    bindings: [.text(destinationPath), encryption?.key.exportBinding ?? .blob(Data())]
                )
                attached = true
                if let encryption {
                    try executeWithoutLogging("PRAGMA tfy_export.cipher_compatibility = \(encryption.compatibility.rawValue);")
                }
                try executeWithoutLogging("PRAGMA tfy_export.journal_mode = DELETE;")
                try withTransaction {
                    let userVersion = try scalar("PRAGMA user_version;") ?? .integer(0)
                    let applicationID = try scalar("PRAGMA application_id;") ?? .integer(0)
                    try executeWithoutLogging("SELECT sqlcipher_export('tfy_export');")
                    try executeWithoutLogging("PRAGMA tfy_export.user_version = \(TFYSwiftTypeMapper.numericValue(from: userVersion));")
                    try executeWithoutLogging("PRAGMA tfy_export.application_id = \(TFYSwiftTypeMapper.numericValue(from: applicationID));")
                }
                try executeWithoutLogging("DETACH DATABASE tfy_export;")
                attached = false
                let target = try TFYSwiftDBConnection(
                    path: destinationPath, databaseName: "export-verification",
                    configuration: TFYSwiftDBConfiguration(journalMode: .delete, synchronousMode: .full, encryption: encryption)
                )
                do {
                    guard try target.integrityCheck() == ["ok"] else {
                        throw TFYSwiftDBError.encryption("Export integrity check failed.")
                    }
                    if encryption != nil, try !target.cipherIntegrityCheck().isEmpty {
                        throw TFYSwiftDBError.encryption("Export cipher integrity check failed.")
                    }
                    try target.close()
                } catch {
                    try? target.close()
                    throw error
                }
                succeeded = true
            } catch {
                if attached { try? executeWithoutLogging("DETACH DATABASE tfy_export;") }
                throw TFYSwiftDBError.encryption("SQLCipher export failed; the source database was preserved.")
            }
        }
        #else
        throw TFYSwiftDBError.encryptionUnavailable
        #endif
    }

    private func executeWithoutLogging(_ sql: String, bindings: [TFYSQLiteBindValue?] = []) throws {
        let statement = try TFYSwiftDBStatement(connection: requireHandle(), sql: sql, connectionLock: connectionLock)
        try statement.bind(bindings)
        while try statement.step() {}
    }

    private func requireMaintenanceState(_ database: OpaquePointer) throws {
        guard transactionDepth == 0, sqlite3_get_autocommit(database) != 0,
              sqlite3_next_stmt(database, nil) == nil else {
            throw TFYSwiftDBError.maintenance("Maintenance requires no active transaction or prepared statements.")
        }
    }

    private func reserveDestination(_ destination: URL) throws -> String {
        guard destination.isFileURL, !destination.path.utf8.contains(0) else {
            throw TFYSwiftDBError.maintenance("Destination must be a local file URL without NUL bytes.")
        }
        let destinationPath = destination.standardizedFileURL.resolvingSymlinksInPath().path
        let sourcePath = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        guard destinationPath != sourcePath,
              !FileManager.default.fileExists(atPath: destinationPath + "-wal"),
              !FileManager.default.fileExists(atPath: destinationPath + "-shm"),
              !FileManager.default.fileExists(atPath: destinationPath + "-journal") else {
            throw TFYSwiftDBError.maintenance("Destination must differ from source and have no existing database sidecars.")
        }
        // Exclusive creation closes the check/create race and restricts file permissions to the owner.
        let descriptor = Darwin.open(destinationPath, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw TFYSwiftDBError.maintenance("Cannot create destination; it may already exist or its directory is unavailable.")
        }
        Darwin.close(descriptor)
        return destinationPath
    }

    private static func removeExportFiles(at path: String) {
        for file in [path, path + "-wal", path + "-shm", path + "-journal"] {
            try? FileManager.default.removeItem(atPath: file)
        }
    }

    private func applyEncryption(_ encryption: TFYSwiftDBEncryption?, to database: OpaquePointer) throws {
        guard let encryption else { return }
        #if TFY_SQLCIPHER
        // Check the actual linked runtime too: a second SQLite library must never silently disable encryption.
        guard let version = try cipherVersion(), !version.isEmpty else {
            throw TFYSwiftDBError.encryptionUnavailable
        }
        let code = encryption.key.withBytes {
            #if SWIFT_PACKAGE
            tfy_sqlcipher_key(UnsafeMutableRawPointer(database), $0, $1)
            #else
            sqlite3_key(database, $0, $1)
            #endif
        }
        guard code == SQLITE_OK else {
            throw TFYSwiftDBError.encryption("SQLCipher key setup failed (code \(code)).")
        }
        try execute("PRAGMA cipher_compatibility = \(encryption.compatibility.rawValue);")
        do {
            _ = try scalar("SELECT count(*) FROM sqlite_master;")
        } catch {
            throw TFYSwiftDBError.encryption("Cannot read encrypted database: wrong key, incompatible format, or damaged file.")
        }
        #else
        throw TFYSwiftDBError.encryptionUnavailable
        #endif
    }

    private func requireHandle() throws -> OpaquePointer {
        guard let handle else {
            throw TFYSwiftDBError.databaseClosed(path: path)
        }
        return handle
    }

    func withConnectionLock<T>(_ work: () throws -> T) rethrows -> T {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        return try work()
    }

    private func measure<T>(_ sql: String, bindings: [TFYSQLiteBindValue?], work: () throws -> T) throws -> T {
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let result = try work()
            log(
                sql: sql,
                bindings: bindings,
                duration: CFAbsoluteTimeGetCurrent() - start,
                error: nil
            )
            return result
        } catch {
            log(
                sql: sql,
                bindings: bindings,
                duration: CFAbsoluteTimeGetCurrent() - start,
                error: error
            )
            throw error
        }
    }

    private func log(sql: String, bindings: [TFYSQLiteBindValue?], duration: TimeInterval, error: Error?) {
        let event = TFYSwiftSQLLogEvent(
            databaseName: databaseName,
            databasePath: path,
            sql: sql,
            bindings: TFYSwiftDBRuntime.describe(bindings),
            duration: duration,
            succeeded: error == nil,
            errorDescription: error.map { String(describing: $0) }
        )
        TFYSwiftDBRuntime.emit(event)
    }

    private static func validate(_ configuration: TFYSwiftDBConfiguration) throws {
        if configuration.encryption != nil, !supportsEncryption {
            throw TFYSwiftDBError.encryptionUnavailable
        }
        let timeoutMilliseconds = configuration.busyTimeout * 1_000
        guard configuration.busyTimeout.isFinite,
              timeoutMilliseconds >= 0,
              timeoutMilliseconds <= Double(Int32.max) else {
            throw TFYSwiftDBError.invalidConfiguration(
                "busyTimeout must be finite and between 0 and \(Double(Int32.max) / 1_000) seconds."
            )
        }
        if let checkpoint = configuration.walAutoCheckpoint,
           checkpoint < 0 || checkpoint > Int(Int32.max) {
            throw TFYSwiftDBError.invalidConfiguration(
                "walAutoCheckpoint must be between 0 and \(Int32.max)."
            )
        }
    }
}
