import Foundation

public protocol TFYSwiftDBModel: Codable {
    init()

    static var tableName: String { get }
    static var databaseName: String { get }
    static var compositeIndexes: [TFYCompositeIndex] { get }
    static var migrationPolicy: TFYMigrationPolicy { get }
}

public extension TFYSwiftDBModel {
    static var tableName: String {
        String(describing: Self.self).lowercased()
    }

    static var databaseName: String {
        "default"
    }

    static var compositeIndexes: [TFYCompositeIndex] {
        []
    }

    static var migrationPolicy: TFYMigrationPolicy {
        .safe
    }

    static func createTable() throws -> TFYSwiftMigrationReport {
        try TFYSwiftAutoTable.create(Self.self)
    }

    static func fetchAll(where clause: String? = nil, bindings: [TFYSQLiteBindValue?] = []) throws -> [Self] {
        try TFYSwiftORM.fetchAll(Self.self, where: clause, bindings: bindings)
    }

    static func fetch(byPrimaryKey value: Any) throws -> Self? {
        try TFYSwiftORM.fetch(Self.self, byPrimaryKey: value)
    }

    static func delete(byPrimaryKey value: Any) throws {
        try TFYSwiftORM.delete(Self.self, byPrimaryKey: value)
    }

    func insert() throws {
        try TFYSwiftORM.insert(self)
    }

    func insertOrReplace() throws {
        try TFYSwiftORM.insertOrReplace(self)
    }

    func update() throws {
        try TFYSwiftORM.update(self)
    }

    func delete() throws {
        try TFYSwiftORM.delete(self)
    }
}
