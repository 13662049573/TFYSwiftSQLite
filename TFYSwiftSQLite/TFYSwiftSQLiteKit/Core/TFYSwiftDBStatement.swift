import Foundation
import SQLite3

public enum TFYSQLiteBindValue: Equatable, Sendable {
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

public enum TFYSQLiteValue: Equatable, Sendable {
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

public final class TFYSwiftDBStatement: @unchecked Sendable {
    public let sql: String
    private let connection: OpaquePointer?
    private let connectionLock: NSRecursiveLock
    private var statement: OpaquePointer?

    public convenience init(connection: OpaquePointer?, sql: String) throws {
        try self.init(connection: connection, sql: sql, connectionLock: NSRecursiveLock())
    }

    init(connection: OpaquePointer?, sql: String, connectionLock: NSRecursiveLock) throws {
        self.connection = connection
        self.connectionLock = connectionLock
        self.sql = sql
        let code = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard code == SQLITE_OK else {
            throw TFYSwiftDBError.prepare(sql: sql, message: TFYSwiftDBStatement.lastErrorMessage(connection))
        }
    }

    deinit {
        connectionLock.lock()
        sqlite3_finalize(statement)
        connectionLock.unlock()
    }

    public func bind(_ bindings: [TFYSQLiteBindValue?]) throws {
        try withLock {
            let expected = Int(sqlite3_bind_parameter_count(statement))
            guard bindings.count == expected else {
                throw TFYSwiftDBError.bindingCount(sql: sql, expected: expected, actual: bindings.count)
            }

            for (index, value) in bindings.enumerated() {
                try bindUnlocked(value ?? .null, at: Int32(index + 1))
            }
        }
    }

    public func reset() throws {
        try withLock {
            let code = sqlite3_reset(statement)
            guard code == SQLITE_OK else {
                throw TFYSwiftDBError.step(sql: sql, message: TFYSwiftDBStatement.lastErrorMessage(connection))
            }
        }
    }

    public func clearBindings() throws {
        try withLock {
            let code = sqlite3_clear_bindings(statement)
            guard code == SQLITE_OK else {
                throw TFYSwiftDBError.bind(index: 0, message: TFYSwiftDBStatement.lastErrorMessage(connection))
            }
        }
    }

    public func step() throws -> Bool {
        try withLock {
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
    }

    public func row() -> [String: TFYSQLiteValue] {
        withLock {
            let count = sqlite3_column_count(statement)
            var row: [String: TFYSQLiteValue] = [:]
            for index in 0..<count {
                let name = String(cString: sqlite3_column_name(statement, index))
                row[name] = columnValue(at: index)
            }
            return row
        }
    }

    func belongs(to connection: OpaquePointer?) -> Bool {
        self.connection == connection
    }

    private func bindUnlocked(_ value: TFYSQLiteBindValue, at index: Int32) throws {
        let code: Int32
        switch value {
        case let .integer(number):
            code = sqlite3_bind_int64(statement, index, number)
        case let .double(number):
            code = sqlite3_bind_double(statement, index, number)
        case let .text(text):
            let byteCount = text.utf8.count
            guard byteCount <= Int(Int32.max) else {
                throw TFYSwiftDBError.bind(index: Int(index), message: "UTF-8 text exceeds SQLite's binding size limit.")
            }
            code = text.withCString {
                sqlite3_bind_text(statement, index, $0, Int32(byteCount), TFYSwiftDBStatement.sqliteTransient)
            }
        case let .blob(data):
            guard data.count <= Int(Int32.max) else {
                throw TFYSwiftDBError.bind(index: Int(index), message: "Blob exceeds SQLite's binding size limit.")
            }
            if data.isEmpty {
                code = sqlite3_bind_zeroblob(statement, index, 0)
            } else {
                code = data.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(
                        statement,
                        index,
                        buffer.baseAddress,
                        Int32(buffer.count),
                        TFYSwiftDBStatement.sqliteTransient
                    )
                }
            }
        case .null:
            code = sqlite3_bind_null(statement, index)
        }

        guard code == SQLITE_OK else {
            throw TFYSwiftDBError.bind(index: Int(index), message: TFYSwiftDBStatement.lastErrorMessage(connection))
        }
    }

    private func withLock<T>(_ work: () throws -> T) rethrows -> T {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        return try work()
    }

    private func columnValue(at index: Int32) -> TFYSQLiteValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .double(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            guard let textPointer = sqlite3_column_text(statement, index) else { return .null }
            let length = Int(sqlite3_column_bytes(statement, index))
            let buffer = UnsafeBufferPointer(start: textPointer, count: length)
            return .text(String(decoding: buffer, as: UTF8.self))
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
