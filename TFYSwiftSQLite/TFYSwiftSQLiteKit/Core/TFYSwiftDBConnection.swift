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
    public let path: String
    private let handle: OpaquePointer?

    public init(path: String) throws {
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
        let statement = try TFYSwiftDBStatement(connection: handle, sql: sql)
        try statement.bind(bindings)
        while try statement.step() {}
    }

    public func query(_ sql: String, bindings: [TFYSQLiteBindValue?] = []) throws -> [[String: TFYSQLiteValue]] {
        let statement = try TFYSwiftDBStatement(connection: handle, sql: sql)
        try statement.bind(bindings)

        var rows: [[String: TFYSQLiteValue]] = []
        while try statement.step() {
            rows.append(statement.row())
        }
        return rows
    }

    public func withTransaction<T>(_ block: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            let result = try block()
            try execute("COMMIT;")
            return result
        } catch {
            try? execute("ROLLBACK;")
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
}
