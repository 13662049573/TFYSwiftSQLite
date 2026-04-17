import Foundation

public enum TFYSwiftDBError: Error, CustomStringConvertible {
    case openDatabase(path: String, message: String)
    case prepare(sql: String, message: String)
    case step(sql: String, message: String)
    case bind(index: Int, message: String)
    case unsupportedType(String)
    case invalidModel(String)
    case missingPrimaryKey(String)
    case encoding(String)
    case decoding(String)
    case migrationConflict(String)
    case notFound(String)

    public var description: String {
        switch self {
        case let .openDatabase(path, message):
            return "Failed to open database at \(path): \(message)"
        case let .prepare(sql, message):
            return "Failed to prepare SQL [\(sql)]: \(message)"
        case let .step(sql, message):
            return "Failed to execute SQL [\(sql)]: \(message)"
        case let .bind(index, message):
            return "Failed to bind parameter \(index): \(message)"
        case let .unsupportedType(message),
             let .invalidModel(message),
             let .missingPrimaryKey(message),
             let .encoding(message),
             let .decoding(message),
             let .migrationConflict(message),
             let .notFound(message):
            return message
        }
    }
}
