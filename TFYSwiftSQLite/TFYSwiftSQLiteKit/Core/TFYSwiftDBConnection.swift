import Foundation
import SQLite3

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

    public init(
        foreignKeysEnabled: Bool = true,
        journalMode: JournalMode = .wal,
        synchronousMode: SynchronousMode = .normal,
        busyTimeout: TimeInterval = 5,
        walAutoCheckpoint: Int? = 1_000
    ) {
        self.foreignKeysEnabled = foreignKeysEnabled
        self.journalMode = journalMode
        self.synchronousMode = synchronousMode
        self.busyTimeout = busyTimeout
        self.walAutoCheckpoint = walAutoCheckpoint
    }
}

public struct TFYSQLiteTableColumnInfo: Equatable, Sendable {
    public let name: String
    public let type: String
    public let defaultValueSQL: String?
    public let isPrimaryKey: Bool
}

public struct TFYSQLiteIndexInfo: Equatable, Sendable {
    public let name: String
    public let columns: [String]
    public let unique: Bool
}

public final class TFYSwiftDBConnection: @unchecked Sendable {
    public let databaseName: String
    public let path: String
    public let configuration: TFYSwiftDBConfiguration

    private var handle: OpaquePointer?
    private let connectionLock = NSRecursiveLock()
    private var transactionDepth = 0

    public init(
        path: String,
        databaseName: String,
        configuration: TFYSwiftDBConfiguration = .default
    ) throws {
        try Self.validate(configuration)
        self.databaseName = databaseName
        self.path = path
        self.configuration = configuration

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

    public func close() throws {
        try withConnectionLock {
            guard let handle else { return }
            let code = sqlite3_close_v2(handle)
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
                connectionLock: connectionLock
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
                try statement.reset()
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

    public func withTransaction<T>(_ block: () throws -> T) throws -> T {
        try withConnectionLock {
            let currentDepth = transactionDepth
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
            WHERE type = 'table' AND name = ?;
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
                defaultValueSQL: row["dflt_value"].map(TFYSwiftTypeMapper.stringValue),
                isPrimaryKey: row["pk"].map(TFYSwiftTypeMapper.numericValue(from:)) == 1
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
            let infoRows = try query("PRAGMA index_info(\(TFYSwiftSQL.escapeIdentifier(name)));")
            let columns = infoRows.sorted {
                TFYSwiftTypeMapper.numericValue(from: $0["seqno"] ?? .integer(0)) <
                TFYSwiftTypeMapper.numericValue(from: $1["seqno"] ?? .integer(0))
            }.compactMap { infoRow -> String? in
                guard let value = infoRow["name"] else { return nil }
                return TFYSwiftTypeMapper.stringValue(from: value)
            }

            indexes.append(TFYSQLiteIndexInfo(name: name, columns: columns, unique: unique))
        }

        return indexes
    }

    public func scalar(_ sql: String, bindings: [TFYSQLiteBindValue?] = []) throws -> TFYSQLiteValue? {
        let rows = try query(sql, bindings: bindings)
        return rows.first?.values.first
    }

    private func requireHandle() throws -> OpaquePointer {
        guard let handle else {
            throw TFYSwiftDBError.databaseClosed(path: path)
        }
        return handle
    }

    private func withConnectionLock<T>(_ work: () throws -> T) rethrows -> T {
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
        let timeoutMilliseconds = configuration.busyTimeout * 1_000
        guard configuration.busyTimeout.isFinite,
              timeoutMilliseconds >= 0,
              timeoutMilliseconds <= Double(Int32.max) else {
            throw TFYSwiftDBError.invalidConfiguration(
                "busyTimeout must be finite and between 0 and \(Double(Int32.max) / 1_000) seconds."
            )
        }
        if let checkpoint = configuration.walAutoCheckpoint, checkpoint < 0 {
            throw TFYSwiftDBError.invalidConfiguration("walAutoCheckpoint must be greater than or equal to zero.")
        }
    }
}
