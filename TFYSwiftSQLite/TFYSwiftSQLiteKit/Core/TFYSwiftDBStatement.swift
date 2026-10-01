//
//  TFYSwiftDBStatement.swift
//  TFYSwiftSQLiteKit
//
//  Created by 田风有 on 2021/5/9.
//

import Foundation
#if TFY_SQLCIPHER
import SQLCipher
#else
import SQLite3
#endif

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
    // Keep the originating connection alive until sqlite3_finalize.
    private let owner: TFYSwiftDBConnection?

    public convenience init(connection: OpaquePointer?, sql: String) throws {
        try self.init(connection: connection, sql: sql, connectionLock: NSRecursiveLock())
    }

    init(connection: OpaquePointer?, sql: String, connectionLock: NSRecursiveLock, owner: TFYSwiftDBConnection? = nil) throws {
        self.owner = owner
        self.connection = connection
        self.connectionLock = connectionLock
        self.sql = sql
        guard !sql.utf8.contains(0) else {
            throw TFYSwiftDBError.invalidQuery("SQL must not contain NUL bytes. Bind text values instead.")
        }
        // Parse the tail with SQLite itself, allowing whitespace/comments while rejecting a second statement.
        try sql.withCString { start in
            var tail: UnsafePointer<CChar>?
            let code = sqlite3_prepare_v2(connection, start, -1, &statement, &tail)
            guard code == SQLITE_OK else {
                sqlite3_finalize(statement)
                statement = nil
                throw TFYSwiftDBError.prepare(sql: sql, message: Self.lastErrorMessage(connection))
            }
            do {
                guard statement != nil else {
                    throw TFYSwiftDBError.invalidQuery("SQL must contain one executable statement.")
                }
                while let remainder = tail, remainder.pointee != 0 {
                    var extra: OpaquePointer?
                    var next: UnsafePointer<CChar>?
                    let tailCode = sqlite3_prepare_v2(connection, remainder, -1, &extra, &next)
                    let hasExtra = extra != nil
                    sqlite3_finalize(extra)
                    guard tailCode == SQLITE_OK, !hasExtra else {
                        throw TFYSwiftDBError.invalidQuery("Only one SQL statement is allowed per call.")
                    }
                    guard let next, next > remainder else { break }
                    tail = next
                }
            } catch {
                sqlite3_finalize(statement)
                statement = nil
                throw error
            }
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

    // sqlite3_reset reports the PREVIOUS step failure even though it successfully resets the VM.
    // Connection-level reuse must allow a successful operation after a failed constraint binding.
    func resetForReuse() {
        withLock { _ = sqlite3_reset(statement) }
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
                row[name] = columnValueUnlocked(at: index)
            }
            return row
        }
    }

    public var columnCount: Int {
        withLock { Int(sqlite3_column_count(statement)) }
    }

    /// Returns a value from the current row, or nil when the index is out of range.
    public func value(at index: Int) -> TFYSQLiteValue? {
        withLock {
            guard index >= 0, index < Int(sqlite3_column_count(statement)) else {
                return nil
            }
            return columnValueUnlocked(at: Int32(index))
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
            guard number.isFinite else {
                throw TFYSwiftDBError.bind(index: Int(index), message: "Floating-point bindings must be finite.")
            }
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

    private func columnValueUnlocked(at index: Int32) -> TFYSQLiteValue {
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
