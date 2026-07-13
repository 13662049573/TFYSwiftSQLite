import Foundation

public enum TFYSwiftDBError: Error, CustomStringConvertible, LocalizedError, Sendable {
    case openDatabase(path: String, message: String)
    case closeDatabase(path: String, message: String)
    case databaseClosed(path: String)
    case invalidConfiguration(String)
    case prepare(sql: String, message: String)
    case step(sql: String, message: String)
    case bind(index: Int, message: String)
    case bindingCount(sql: String, expected: Int, actual: Int)
    case unsupportedType(String)
    case invalidModel(String)
    case missingPrimaryKey(String)
    case encoding(String)
    case decoding(String)
    case invalidQuery(String)
    case migrationConflict(String)
    case notFound(String)

    public var description: String {
        switch self {
        case let .openDatabase(path, message):
            return "Failed to open database at \(path): \(message)"
        case let .closeDatabase(path, message):
            return "Failed to close database at \(path): \(message)"
        case let .databaseClosed(path):
            return "Database connection at \(path) is closed."
        case let .invalidConfiguration(message):
            return message
        case let .prepare(sql, message):
            return "Failed to prepare SQL [\(sql)]: \(message)"
        case let .step(sql, message):
            return "Failed to execute SQL [\(sql)]: \(message)"
        case let .bind(index, message):
            return "Failed to bind parameter \(index): \(message)"
        case let .bindingCount(sql, expected, actual):
            return "SQL [\(sql)] expects \(expected) bindings, but received \(actual)."
        case let .unsupportedType(message),
             let .invalidModel(message),
             let .missingPrimaryKey(message),
             let .encoding(message),
             let .decoding(message),
             let .invalidQuery(message),
             let .migrationConflict(message),
             let .notFound(message):
            return message
        }
    }

    public var errorDescription: String? {
        description
    }
}
