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
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var sqlLogger: ((TFYSwiftSQLLogEvent) -> Void)?
        var bindingLogPolicy: TFYSwiftSQLBindingLogPolicy = .redacted
    }

    private static let state = State()

    public static func setSQLLogger(
        _ logger: ((TFYSwiftSQLLogEvent) -> Void)?,
        bindingPolicy: TFYSwiftSQLBindingLogPolicy = .redacted
    ) {
        state.lock.lock()
        state.sqlLogger = logger
        state.bindingLogPolicy = bindingPolicy
        state.lock.unlock()
    }

    static func emit(_ event: TFYSwiftSQLLogEvent) {
        state.lock.lock()
        let logger = state.sqlLogger
        state.lock.unlock()
        logger?(event)
    }

    static func describe(_ bindings: [TFYSQLiteBindValue?]) -> [String] {
        state.lock.lock()
        let policy = state.bindingLogPolicy
        state.lock.unlock()

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
