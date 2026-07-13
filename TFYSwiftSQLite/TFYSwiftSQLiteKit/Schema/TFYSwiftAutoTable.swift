import Foundation

public enum TFYSwiftAutoTable {
    @discardableResult
    public static func create<Model: TFYSwiftDBModel>(_ modelType: Model.Type) throws -> TFYSwiftMigrationReport {
        let connection = try TFYSwiftDatabaseCenter.shared.open(named: modelType.databaseName)
        return try TFYSwiftSchemaMigrator.migrate(modelType, connection: connection)
    }
}
