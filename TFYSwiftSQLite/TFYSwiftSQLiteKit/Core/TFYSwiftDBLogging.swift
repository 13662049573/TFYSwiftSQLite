import Foundation

public struct TFYSwiftSQLLogEvent: Sendable {
    public let databaseName: String
    public let databasePath: String
    public let sql: String
    public let bindings: [String]
    public let duration: TimeInterval
    public let succeeded: Bool
    public let errorDescription: String?

    public init(
        databaseName: String,
        databasePath: String,
        sql: String,
        bindings: [String],
        duration: TimeInterval,
        succeeded: Bool,
        errorDescription: String?
    ) {
        self.databaseName = databaseName
        self.databasePath = databasePath
        self.sql = sql
        self.bindings = bindings
        self.duration = duration
        self.succeeded = succeeded
        self.errorDescription = errorDescription
    }
}

public enum TFYSwiftSQLBindingLogPolicy: Equatable, Sendable {
    /// Logs only the SQLite value kind. This is the commercial-safe default.
    case redacted
    /// Logs values exactly as bound. Enable only in controlled development environments.
    case full
}

public enum TFYSwiftDBRuntime {
    private static let lock = NSLock()
    private static var sqlLogger: ((TFYSwiftSQLLogEvent) -> Void)?
    private static var bindingLogPolicy: TFYSwiftSQLBindingLogPolicy = .redacted

    public static func setSQLLogger(
        _ logger: ((TFYSwiftSQLLogEvent) -> Void)?,
        bindingPolicy: TFYSwiftSQLBindingLogPolicy = .redacted
    ) {
        lock.lock()
        sqlLogger = logger
        bindingLogPolicy = bindingPolicy
        lock.unlock()
    }

    static func emit(_ event: TFYSwiftSQLLogEvent) {
        lock.lock()
        let logger = sqlLogger
        lock.unlock()
        logger?(event)
    }

    static func describe(_ bindings: [TFYSQLiteBindValue?]) -> [String] {
        lock.lock()
        let policy = bindingLogPolicy
        lock.unlock()

        return bindings.map { value in
            let value = value ?? .null
            guard policy == .redacted else { return value.description }
            switch value {
            case .integer:
                return "integer(<redacted>)"
            case .double:
                return "double(<redacted>)"
            case .text:
                return "text(<redacted>)"
            case let .blob(data):
                return "blob(\(data.count) bytes)"
            case .null:
                return "null"
            }
        }
    }
}
