import Foundation

public final class TFYSwiftDatabaseCenter: @unchecked Sendable {
    public static let shared = TFYSwiftDatabaseCenter()

    private var connections: [String: TFYSwiftDBConnection] = [:]
    private var databasesBeingRemoved: Set<String> = []
    private let lock = NSLock()

    private init() {}

    public func open(
        named databaseName: String,
        configuration: TFYSwiftDBConfiguration = .default
    ) throws -> TFYSwiftDBConnection {
        lock.lock()
        defer { lock.unlock() }

        guard !databasesBeingRemoved.contains(databaseName) else {
            throw TFYSwiftDBError.invalidConfiguration(
                "Database '\(databaseName)' is currently being removed. Retry after the removal completes."
            )
        }

        if let cached = connections[databaseName] {
            guard cached.configuration == configuration else {
                throw TFYSwiftDBError.invalidConfiguration(
                    "Database '\(databaseName)' is already open with a different configuration. Close it before reopening."
                )
            }
            return cached
        }

        let path = try Self.databasePath(named: databaseName)
        let connection = try TFYSwiftDBConnection(
            path: path,
            databaseName: databaseName,
            configuration: configuration
        )
        connections[databaseName] = connection
        return connection
    }

    public func path(named databaseName: String) throws -> String {
        try Self.databasePath(named: databaseName)
    }

    public func removeDatabase(named databaseName: String) throws {
        lock.lock()
        guard !databasesBeingRemoved.contains(databaseName) else {
            lock.unlock()
            throw TFYSwiftDBError.invalidConfiguration("Database '\(databaseName)' is already being removed.")
        }
        databasesBeingRemoved.insert(databaseName)
        let connection = connections.removeValue(forKey: databaseName)
        lock.unlock()

        defer {
            lock.lock()
            databasesBeingRemoved.remove(databaseName)
            lock.unlock()
        }

        try connection?.close()
        let path = try Self.databasePath(named: databaseName)
        let fileManager = FileManager.default
        let sidecars = [path, "\(path)-wal", "\(path)-shm"]
        for file in sidecars where fileManager.fileExists(atPath: file) {
            try fileManager.removeItem(atPath: file)
        }
    }

    public func closeAll() {
        lock.lock()
        let openConnections = Array(connections.values)
        connections.removeAll()
        lock.unlock()
        openConnections.forEach { try? $0.close() }
    }

    public func close(named databaseName: String) {
        lock.lock()
        let connection = connections.removeValue(forKey: databaseName)
        lock.unlock()
        try? connection?.close()
    }

    public static func databasePath(named databaseName: String) throws -> String {
        try validateDatabaseName(databaseName)
        let libraryURL = try databaseDirectory()
        return libraryURL.appendingPathComponent("\(databaseName).db").path
    }

    public static func databaseDirectory() throws -> URL {
        guard let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            throw TFYSwiftDBError.invalidModel("Unable to resolve Library directory for database storage.")
        }
        let directory = libraryURL.appendingPathComponent("TFYSwiftSQLite", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private static func validateDatabaseName(_ databaseName: String) throws {
        let trimmed = databaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let containsPathSeparator = databaseName.contains("/") || databaseName.contains("\\")
        let containsTraversal = databaseName == "." || databaseName == ".." || databaseName.contains("..")
        let containsControlCharacter = databaseName.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
        }

        guard !trimmed.isEmpty,
              trimmed == databaseName,
              !containsPathSeparator,
              !containsTraversal,
              !containsControlCharacter else {
            throw TFYSwiftDBError.invalidConfiguration(
                "Database name must be a non-empty file-safe name without path separators, traversal segments, or surrounding whitespace."
            )
        }
    }
}
