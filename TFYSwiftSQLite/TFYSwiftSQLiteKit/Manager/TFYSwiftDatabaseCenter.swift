//
//  TFYSwiftDatabaseCenter.swift
//  TFYSwiftSQLiteKit
//
//  Created by 田风有 on 2021/5/9.
//

import Foundation

public final class TFYSwiftDatabaseCenter: @unchecked Sendable {
    public static let shared = TFYSwiftDatabaseCenter()

    private var configurations: [String: TFYSwiftDBConfiguration] = [:]
    private var databasesBeingOpened: Set<String> = []
    private var openingThreads: [String: Thread] = [:]
    private var connections: [String: TFYSwiftDBConnection] = [:]
    private var databasesBeingRemoved: Set<String> = []
    private var databasesBeingClosed: Set<String> = []
    private let lock = NSCondition()

    private init() {}

    /// Registers per-database settings used by EVERY ORM and migration operation, including after close.
    /// Call before first use. Pass nil after closing to forget the stored configuration/key.
    public func configure(named databaseName: String, configuration: TFYSwiftDBConfiguration?) throws {
        try Self.validateDatabaseName(databaseName)
        lock.lock()
        defer { lock.unlock() }
        guard connections[databaseName] == nil, !databasesBeingOpened.contains(databaseName),
              !databasesBeingClosed.contains(databaseName), !databasesBeingRemoved.contains(databaseName) else {
            throw TFYSwiftDBError.invalidConfiguration("Close the database before changing its registered configuration.")
        }
        configurations[databaseName] = configuration
    }

    public func open(
        named databaseName: String,
        configuration: TFYSwiftDBConfiguration? = nil
    ) throws -> TFYSwiftDBConnection {
        try Self.validateDatabaseName(databaseName)
        lock.lock()
        while databasesBeingOpened.contains(databaseName) {
            guard openingThreads[databaseName] !== Thread.current else {
                lock.unlock()
                throw TFYSwiftDBError.invalidConfiguration("Cannot reenter the same database while it is being initialized.")
            }
            lock.wait()
        }
        guard !databasesBeingRemoved.contains(databaseName),
              !databasesBeingClosed.contains(databaseName) else {
            lock.unlock()
            throw TFYSwiftDBError.invalidConfiguration("Database '\(databaseName)' is opening, closing, or being removed. Retry when complete.")
        }
        if let cached = connections[databaseName] {
            lock.unlock()
            // Never acquire a connection lock or invoke a logger under the center lock.
            // Transactions may reenter this center through model APIs.
            guard cached.isOpen else {
                let updated = cached.configuration
                lock.lock()
                if connections[databaseName] === cached {
                    configurations[databaseName] = updated
                    connections.removeValue(forKey: databaseName)
                }
                lock.unlock()
                return try open(named: databaseName, configuration: configuration)
            }
            if let configuration, cached.configuration != configuration {
                throw TFYSwiftDBError.invalidConfiguration("Database '\(databaseName)' is already open with a different configuration. Close it before reopening.")
            }
            return cached
        }
        let resolved = configuration ?? configurations[databaseName] ?? .default
        databasesBeingOpened.insert(databaseName)
        openingThreads[databaseName] = Thread.current
        lock.unlock()
        defer {
            lock.lock()
            databasesBeingOpened.remove(databaseName)
            openingThreads.removeValue(forKey: databaseName)
            lock.broadcast()
            lock.unlock()
        }
        let path = try Self.databasePath(named: databaseName)
        let connection = try TFYSwiftDBConnection(path: path, databaseName: databaseName, configuration: resolved)
        lock.lock()
        connections[databaseName] = connection
        configurations[databaseName] = resolved
        lock.unlock()
        return connection
    }

    /// Rotates the current key and remembers the new settings for subsequent ORM opens.
    public func rekey(named databaseName: String, key: TFYSwiftDBKey) throws {
        let connection = try open(named: databaseName)
        try connection.rekey(key)
        let updated = connection.configuration
        lock.lock()
        if connections[databaseName] === connection { configurations[databaseName] = updated }
        lock.unlock()
    }

    public func path(named databaseName: String) throws -> String {
        try Self.databasePath(named: databaseName)
    }

    public func removeDatabase(named databaseName: String) throws {
        try finishDatabase(named: databaseName, removing: true)
    }

    public func closeAll() {
        lock.lock()
        let names = Array(connections.keys)
        lock.unlock()
        for name in names { _ = close(named: name) }
    }

    @discardableResult
    public func close(named databaseName: String) -> Bool {
        do {
            try finishDatabase(named: databaseName, removing: false)
            return true
        } catch { return false }
    }

    private func finishDatabase(named databaseName: String, removing: Bool) throws {
        try Self.validateDatabaseName(databaseName)
        lock.lock()
        let connection = connections[databaseName]
        lock.unlock()

        let finish = {
            self.lock.lock()
            guard !self.databasesBeingRemoved.contains(databaseName),
                  !self.databasesBeingClosed.contains(databaseName),
                  !self.databasesBeingOpened.contains(databaseName),
                  self.connections[databaseName] === connection else {
                self.lock.unlock()
                throw TFYSwiftDBError.invalidConfiguration("Database '\(databaseName)' changed or is undergoing another lifecycle operation. Retry when complete.")
            }
            if removing { self.databasesBeingRemoved.insert(databaseName) }
            else { self.databasesBeingClosed.insert(databaseName) }
            self.lock.unlock()
            defer {
                self.lock.lock()
                self.databasesBeingRemoved.remove(databaseName)
                self.databasesBeingClosed.remove(databaseName)
                self.lock.broadcast()
                self.lock.unlock()
            }

            try connection?.close()
            let updated = connection?.configuration
            self.lock.lock()
            self.connections.removeValue(forKey: databaseName)
            if removing { self.configurations.removeValue(forKey: databaseName) }
            else if let updated { self.configurations[databaseName] = updated }
            self.lock.unlock()

            if removing {
                let path = try Self.databasePath(named: databaseName)
                let manager = FileManager.default
                for file in [path, "\(path)-wal", "\(path)-shm", "\(path)-journal"] where manager.fileExists(atPath: file) {
                    try manager.removeItem(atPath: file)
                }
            }
        }
        // Wait for the current transaction BEFORE marking the database unavailable.
        // Its model APIs may reenter open(); center locks are never held while waiting.
        if let connection { try connection.withConnectionLock(finish) }
        else { try finish() }
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
