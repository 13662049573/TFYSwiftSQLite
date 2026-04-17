import Foundation

public enum TFYSwiftIndexBuilder {
    public nonisolated static func expectedIndexes(for schema: TFYSwiftModelSchema) -> [TFYSwiftIndexDefinition] {
        var indexes: [TFYSwiftIndexDefinition] = []

        for column in schema.persistedColumns where column.isIndexed || column.isUnique {
            let prefix = column.isUnique ? "uidx" : "idx"
            let name = "\(prefix)_\(schema.tableName)_\(column.name)"
            indexes.append(
                TFYSwiftIndexDefinition(
                    name: name,
                    tableName: schema.tableName,
                    columns: [column.name],
                    unique: column.isUnique
                )
            )
        }

        for composite in schema.compositeIndexes {
            guard !composite.columns.isEmpty else { continue }
            let prefix = composite.unique ? "uidx" : "idx"
            let generatedName = "\(prefix)_\(schema.tableName)_\(composite.columns.joined(separator: "_"))"
            indexes.append(
                TFYSwiftIndexDefinition(
                    name: composite.name ?? generatedName,
                    tableName: schema.tableName,
                    columns: composite.columns,
                    unique: composite.unique
                )
            )
        }

        return indexes
    }

    public nonisolated static func createIndexSQL(for index: TFYSwiftIndexDefinition) -> String {
        let qualifier = index.unique ? "UNIQUE " : ""
        let quotedColumns = index.columns.map(TFYSwiftSQL.escapeIdentifier).joined(separator: ", ")
        return """
        CREATE \(qualifier)INDEX IF NOT EXISTS \(TFYSwiftSQL.escapeIdentifier(index.name))
        ON \(TFYSwiftSQL.escapeIdentifier(index.tableName)) (\(quotedColumns));
        """
    }
}
