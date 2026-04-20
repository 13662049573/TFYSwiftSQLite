import Foundation
import SQLite3

public enum TFYSQLiteBindValue: Equatable {
    case integer(Int64)
    case double(Double)
    case text(String)
    case blob(Data)
    case null
}

extension TFYSQLiteBindValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .integer(value):
            return "integer(\(value))"
        case let .double(value):
            return "double(\(value))"
        case let .text(value):
            return "text(\(value))"
        case let .blob(data):
            return "blob(\(data.count) bytes)"
        case .null:
            return "null"
        }
    }
}

public enum TFYSQLiteValue: Equatable {
    case integer(Int64)
    case double(Double)
    case text(String)
    case blob(Data)
    case null
}

extension TFYSQLiteValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .integer(value):
            return "integer(\(value))"
        case let .double(value):
            return "double(\(value))"
        case let .text(value):
            return "text(\(value))"
        case let .blob(data):
            return "blob(\(data.count) bytes)"
        case .null:
            return "null"
        }
    }
}

public final class TFYSwiftDBStatement {
    private let sql: String
    private let connection: OpaquePointer?
    private var statement: OpaquePointer?

    public init(connection: OpaquePointer?, sql: String) throws {
        self.connection = connection
        self.sql = sql
        let code = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard code == SQLITE_OK else {
            throw TFYSwiftDBError.prepare(sql: sql, message: TFYSwiftDBStatement.lastErrorMessage(connection))
        }
    }

    deinit {
        sqlite3_finalize(statement)
    }

    public func bind(_ bindings: [TFYSQLiteBindValue?]) throws {
        for (index, value) in bindings.enumerated() {
            try bind(value ?? .null, at: Int32(index + 1))
        }
    }

    public func step() throws -> Bool {
        let code = sqlite3_step(statement)
        switch code {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw TFYSwiftDBError.step(sql: sql, message: TFYSwiftDBStatement.lastErrorMessage(connection))
        }
    }

    public func row() -> [String: TFYSQLiteValue] {
        let count = sqlite3_column_count(statement)
        var row: [String: TFYSQLiteValue] = [:]
        for index in 0..<count {
            let name = String(cString: sqlite3_column_name(statement, index))
            row[name] = columnValue(at: index)
        }
        return row
    }

    private func bind(_ value: TFYSQLiteBindValue, at index: Int32) throws {
        let code: Int32
        switch value {
        case let .integer(number):
            code = sqlite3_bind_int64(statement, index, number)
        case let .double(number):
            code = sqlite3_bind_double(statement, index, number)
        case let .text(text):
            code = text.withCString {
                sqlite3_bind_text(statement, index, $0, -1, TFYSwiftDBStatement.sqliteTransient)
            }
        case let .blob(data):
            code = data.withUnsafeBytes { buffer in
                sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), TFYSwiftDBStatement.sqliteTransient)
            }
        case .null:
            code = sqlite3_bind_null(statement, index)
        }

        guard code == SQLITE_OK else {
            throw TFYSwiftDBError.bind(index: Int(index), message: TFYSwiftDBStatement.lastErrorMessage(connection))
        }
    }

    private func columnValue(at index: Int32) -> TFYSQLiteValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .double(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            guard let textPointer = sqlite3_column_text(statement, index) else { return .null }
            return .text(String(cString: textPointer))
        case SQLITE_BLOB:
            let bytes = sqlite3_column_blob(statement, index)
            let length = Int(sqlite3_column_bytes(statement, index))
            guard let base = bytes, length > 0 else { return .blob(Data()) }
            return .blob(Data(bytes: base, count: length))
        default:
            return .null
        }
    }

    private static var sqliteTransient: sqlite3_destructor_type? {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    private static func lastErrorMessage(_ connection: OpaquePointer?) -> String {
        guard let connection else { return "Unknown SQLite error." }
        return String(cString: sqlite3_errmsg(connection))
    }
}
