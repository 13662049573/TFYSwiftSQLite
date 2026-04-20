import Foundation
import SQLite3

public struct TFYSQLiteTableColumnInfo: Equatable {
    public let name: String
    public let type: String
    public let defaultValueSQL: String?
    public let isPrimaryKey: Bool
}

public struct TFYSQLiteIndexInfo: Equatable {
    public let name: String
    public let columns: [String]
    public let unique: Bool
}

public final class TFYSwiftDBConnection {
    public let databaseName: String
    public let path: String
    private let handle: OpaquePointer?
    private let transactionLock = NSRecursiveLock()
    private var transactionDepth = 0

    public init(path: String, databaseName: String) throws {
        self.databaseName = databaseName
        self.path = path
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let code = sqlite3_open_v2(path, &database, flags, nil)
        guard code == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error."
            sqlite3_close(database)
            throw TFYSwiftDBError.openDatabase(path: path, message: message)
        }
        handle = database
        try execute("PRAGMA foreign_keys = ON;")
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA synchronous = NORMAL;")
    }

    deinit {
        sqlite3_close(handle)
    }

    public var lastInsertedRowID: Int64 {
        sqlite3_last_insert_rowid(handle)
    }

    public func execute(_ sql: String, bindings: [TFYSQLiteBindValue?] = []) throws {
        try measure(sql, bindings: bindings) {
            let statement = try TFYSwiftDBStatement(connection: handle, sql: sql)
            try statement.bind(bindings)
            while try statement.step() {}
        }
    }

    public func query(_ sql: String, bindings: [TFYSQLiteBindValue?] = []) throws -> [[String: TFYSQLiteValue]] {
        try measure(sql, bindings: bindings) {
            let statement = try TFYSwiftDBStatement(connection: handle, sql: sql)
            try statement.bind(bindings)

            var rows: [[String: TFYSQLiteValue]] = []
            while try statement.step() {
                rows.append(statement.row())
            }
            return rows
        }
    }

    public func withTransaction<T>(_ block: () throws -> T) throws -> T {
        transactionLock.lock()
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
            transactionLock.unlock()
            return result
        } catch {
            if currentDepth == 0 {
                try? execute("ROLLBACK;")
            } else {
                try? execute("ROLLBACK TO SAVEPOINT \(TFYSwiftSQL.escapeIdentifier(savepointName));")
                try? execute("RELEASE SAVEPOINT \(TFYSwiftSQL.escapeIdentifier(savepointName));")
            }
            transactionDepth -= 1
            transactionLock.unlock()
            throw error
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
            bindings: bindings.map { ($0 ?? .null).description },
            duration: duration,
            succeeded: error == nil,
            errorDescription: error.map { String(describing: $0) }
        )
        TFYSwiftDBRuntime.emit(event)
    }
}
