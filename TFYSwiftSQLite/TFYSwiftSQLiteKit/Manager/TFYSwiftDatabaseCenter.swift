import Foundation

public final class TFYSwiftDatabaseCenter {
    public static let shared = TFYSwiftDatabaseCenter()

    private var connections: [String: TFYSwiftDBConnection] = [:]
    private let lock = NSLock()

    private init() {}

    public func open(named databaseName: String) throws -> TFYSwiftDBConnection {
        lock.lock()
        defer { lock.unlock() }

        if let cached = connections[databaseName] {
            return cached
        }

        let path = try Self.databasePath(named: databaseName)
        let connection = try TFYSwiftDBConnection(path: path)
        connections[databaseName] = connection
        return connection
    }

    public func path(named databaseName: String) throws -> String {
        try Self.databasePath(named: databaseName)
    }

    public func removeDatabase(named databaseName: String) throws {
        lock.lock()
        connections.removeValue(forKey: databaseName)
        lock.unlock()

        let path = try Self.databasePath(named: databaseName)
        let fileManager = FileManager.default
        let sidecars = [path, "\(path)-wal", "\(path)-shm"]
        for file in sidecars where fileManager.fileExists(atPath: file) {
            try fileManager.removeItem(atPath: file)
        }
    }

    public func closeAll() {
        lock.lock()
        defer { lock.unlock() }
        connections.removeAll()
    }

    public static func databasePath(named databaseName: String) throws -> String {
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
}
