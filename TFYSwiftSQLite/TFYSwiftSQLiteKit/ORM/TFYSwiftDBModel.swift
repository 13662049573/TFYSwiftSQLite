import Foundation

public protocol TFYSwiftDBModel: Codable {
    init()

    static var tableName: String { get }
    static var databaseName: String { get }
    static var compositeIndexes: [TFYCompositeIndex] { get }
    static var migrationPolicy: TFYMigrationPolicy { get }
    static func willMigrate(using connection: TFYSwiftDBConnection, schema: TFYSwiftModelSchema) throws
    static func didMigrate(report: TFYSwiftMigrationReport, using connection: TFYSwiftDBConnection, schema: TFYSwiftModelSchema) throws
    static func renamedColumns(for schema: TFYSwiftModelSchema, existingColumns: [TFYSQLiteTableColumnInfo]) throws -> [String: String]
    static func rebuildExpressions(for schema: TFYSwiftModelSchema, existingColumns: [TFYSQLiteTableColumnInfo]) throws -> [String: String]
    static func willRebuildTable(using connection: TFYSwiftDBConnection, schema: TFYSwiftModelSchema, plan: TFYSwiftRebuildPlan) throws
    static func validateRebuiltTable(using connection: TFYSwiftDBConnection, schema: TFYSwiftModelSchema, plan: TFYSwiftRebuildPlan) throws
    static func didRebuildTable(report: TFYSwiftMigrationReport, using connection: TFYSwiftDBConnection, schema: TFYSwiftModelSchema, plan: TFYSwiftRebuildPlan) throws
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

    static func willMigrate(using connection: TFYSwiftDBConnection, schema: TFYSwiftModelSchema) throws {}

    static func didMigrate(report: TFYSwiftMigrationReport, using connection: TFYSwiftDBConnection, schema: TFYSwiftModelSchema) throws {}

    static func renamedColumns(for schema: TFYSwiftModelSchema, existingColumns: [TFYSQLiteTableColumnInfo]) throws -> [String: String] {
        [:]
    }

    static func rebuildExpressions(for schema: TFYSwiftModelSchema, existingColumns: [TFYSQLiteTableColumnInfo]) throws -> [String: String] {
        [:]
    }

    static func willRebuildTable(using connection: TFYSwiftDBConnection, schema: TFYSwiftModelSchema, plan: TFYSwiftRebuildPlan) throws {}

    static func validateRebuiltTable(using connection: TFYSwiftDBConnection, schema: TFYSwiftModelSchema, plan: TFYSwiftRebuildPlan) throws {}

    static func didRebuildTable(report: TFYSwiftMigrationReport, using connection: TFYSwiftDBConnection, schema: TFYSwiftModelSchema, plan: TFYSwiftRebuildPlan) throws {}

    static func createTable() throws -> TFYSwiftMigrationReport {
        try TFYSwiftAutoTable.create(Self.self)
    }

    static func fetchAll(where clause: String? = nil, bindings: [TFYSQLiteBindValue?] = []) throws -> [Self] {
        try TFYSwiftORM.fetchAll(Self.self, where: clause, bindings: bindings)
    }

    static func query() -> TFYQuery<Self> {
        TFYQuery()
    }

    static var fields: TFYFields<Self> {
        TFYFields()
    }

    static func field<Value>(_ name: String, as _: Value.Type = Value.self) -> TFYField<Self, Value> {
        switch resolveFieldReference(name) {
        case let .success(columnName):
            return TFYField(name: columnName)
        case let .failure(error):
            return TFYField(name: name, validationError: error)
        }
    }

    static func fetchAll(_ query: TFYQuery<Self>) throws -> [Self] {
        try TFYSwiftORM.fetchAll(Self.self, query)
    }

    static func fetchPage(
        where clause: String? = nil,
        orderBy: String? = nil,
        limit: Int,
        offset: Int = 0,
        bindings: [TFYSQLiteBindValue?] = []
    ) throws -> [Self] {
        try TFYSwiftORM.fetchPage(
            Self.self,
            where: clause,
            orderBy: orderBy,
            limit: limit,
            offset: offset,
            bindings: bindings
        )
    }

    static func fetch(byPrimaryKey value: Any) throws -> Self? {
        try TFYSwiftORM.fetch(Self.self, byPrimaryKey: value)
    }

    static func count(where clause: String? = nil, bindings: [TFYSQLiteBindValue?] = []) throws -> Int {
        try TFYSwiftORM.count(Self.self, where: clause, bindings: bindings)
    }

    static func count(_ query: TFYQuery<Self>) throws -> Int {
        try TFYSwiftORM.count(Self.self, query)
    }

    static func exists(where clause: String? = nil, bindings: [TFYSQLiteBindValue?] = []) throws -> Bool {
        try TFYSwiftORM.exists(Self.self, where: clause, bindings: bindings)
    }

    static func exists(_ query: TFYQuery<Self>) throws -> Bool {
        try TFYSwiftORM.exists(Self.self, query)
    }

    static func transaction(_ block: () throws -> Void) throws {
        try TFYSwiftORM.transaction(Self.self, block)
    }

    static func insert(_ models: [Self]) throws {
        try TFYSwiftORM.insert(models)
    }

    static func insertOrReplace(_ models: [Self]) throws {
        try TFYSwiftORM.insertOrReplace(models)
    }

    static func delete(byPrimaryKey value: Any) throws {
        try TFYSwiftORM.delete(Self.self, byPrimaryKey: value)
    }

    static func delete(_ query: TFYQuery<Self>) throws {
        try TFYSwiftORM.delete(Self.self, query)
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

    static func resolveFieldReference(_ name: String) -> Result<String, TFYSwiftDBError> {
        do {
            return .success(try TFYSwiftModelMirror.resolveColumnName(forDeclaredField: name, in: Self.self))
        } catch let error as TFYSwiftDBError {
            return .failure(error)
        } catch {
            return .failure(TFYSwiftDBError.invalidModel("Failed to validate field '\(name)' on \(String(describing: Self.self)): \(error)"))
        }
    }
}
