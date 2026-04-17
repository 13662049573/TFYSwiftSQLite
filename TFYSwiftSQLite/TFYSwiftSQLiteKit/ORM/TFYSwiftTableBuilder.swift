import Foundation

public enum TFYSwiftTableBuilder {
    public nonisolated static func createTableSQL(for schema: TFYSwiftModelSchema) -> String {
        let definitions = schema.persistedColumns.map(columnDefinition(for:))
        let body = definitions.joined(separator: ",\n")
        return """
        CREATE TABLE IF NOT EXISTS \(TFYSwiftSQL.escapeIdentifier(schema.tableName)) (
        \(body)
        );
        """
    }

    public nonisolated static func addColumnSQL(tableName: String, column: TFYSwiftColumn) -> String {
        """
        ALTER TABLE \(TFYSwiftSQL.escapeIdentifier(tableName))
        ADD COLUMN \(columnDefinition(for: column));
        """
    }

    private nonisolated static func columnDefinition(for column: TFYSwiftColumn) -> String {
        var parts: [String] = [
            TFYSwiftSQL.escapeIdentifier(column.name),
            column.sqliteType
        ]

        if column.isPrimaryKey {
            parts.append("PRIMARY KEY")
            if column.isAutoIncrement && column.sqliteType == "INTEGER" {
                parts.append("AUTOINCREMENT")
            }
        }

        if let defaultSQL = column.defaultSQL {
            parts.append("DEFAULT \(defaultSQL)")
        }

        return parts.joined(separator: " ")
    }
}
