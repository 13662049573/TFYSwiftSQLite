import Foundation

public struct TFYSwiftSQLLogEvent {
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

public enum TFYSwiftDBRuntime {
    private static let lock = NSLock()
    private static var sqlLogger: ((TFYSwiftSQLLogEvent) -> Void)?

    public static func setSQLLogger(_ logger: ((TFYSwiftSQLLogEvent) -> Void)?) {
        lock.lock()
        sqlLogger = logger
        lock.unlock()
    }

    static func emit(_ event: TFYSwiftSQLLogEvent) {
        lock.lock()
        let logger = sqlLogger
        lock.unlock()
        logger?(event)
    }
}
