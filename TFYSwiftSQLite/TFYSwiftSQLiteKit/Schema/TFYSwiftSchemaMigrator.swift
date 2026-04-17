import Foundation

public enum TFYSwiftSchemaMigrator {
    public static func migrate<Model: TFYSwiftDBModel>(_ modelType: Model.Type, connection: TFYSwiftDBConnection) throws -> TFYSwiftMigrationReport {
        let schema = try TFYSwiftModelMirror.schema(for: modelType)
        var report = TFYSwiftMigrationReport(
            modelName: schema.modelName,
            tableName: schema.tableName,
            databaseName: schema.databaseName,
            databasePath: connection.path
        )

        if try !connection.tableExists(schema.tableName) {
            let createSQL = TFYSwiftTableBuilder.createTableSQL(for: schema)
            try connection.execute(createSQL)
            report.addCreatedTableSQL(createSQL)

            for index in TFYSwiftIndexBuilder.expectedIndexes(for: schema) {
                let sql = TFYSwiftIndexBuilder.createIndexSQL(for: index)
                try connection.execute(sql)
                report.addCreatedIndexSQL(sql)
            }
            return report
        }

        let existingColumns = try connection.pragmaTableInfo(tableName: schema.tableName)
        let existingColumnMap = Dictionary(uniqueKeysWithValues: existingColumns.map { ($0.name, $0) })

        for column in schema.persistedColumns {
            if existingColumnMap[column.name] == nil {
                let sql = TFYSwiftTableBuilder.addColumnSQL(tableName: schema.tableName, column: column)
                try connection.execute(sql)
                report.addAddedColumnSQL(sql)
                continue
            }

            guard let existing = existingColumnMap[column.name] else { continue }
            if existing.type.uppercased() != column.sqliteType.uppercased() {
                report.addWarning("Column \(column.name) type differs: existing \(existing.type), expected \(column.sqliteType). v1 safe migration does not rewrite column types.")
            }
            if existing.isPrimaryKey != column.isPrimaryKey {
                report.addWarning("Column \(column.name) primary key flag differs. v1 safe migration does not rewrite primary keys.")
            }
            let existingDefault = existing.defaultValueSQL?.trimmingCharacters(in: .whitespacesAndNewlines)
            let expectedDefault = column.defaultSQL?.trimmingCharacters(in: .whitespacesAndNewlines)
            if existingDefault != expectedDefault, expectedDefault != nil {
                report.addWarning("Column \(column.name) default differs: existing \(existingDefault ?? "nil"), expected \(expectedDefault ?? "nil"). v1 safe migration leaves existing defaults untouched.")
            }
        }

        let expectedIndexes = TFYSwiftIndexBuilder.expectedIndexes(for: schema)
        let existingIndexes = try connection.pragmaIndexList(tableName: schema.tableName)
        let existingSignatures = Set(existingIndexes.map { "\($0.unique ? "unique" : "index")|\($0.columns.joined(separator: ","))" })
        let existingNames = Set(existingIndexes.map(\.name))

        for index in expectedIndexes where !existingNames.contains(index.name) && !existingSignatures.contains(index.signature) {
            let sql = TFYSwiftIndexBuilder.createIndexSQL(for: index)
            try connection.execute(sql)
            report.addCreatedIndexSQL(sql)
        }

        return report
    }
}
