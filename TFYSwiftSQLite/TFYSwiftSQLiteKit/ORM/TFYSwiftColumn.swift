import Foundation

public enum TFYStorageStrategy: String, Codable {
    case scalar
    case json
}

public enum TFYMigrationPolicy: String, Codable {
    case safe
    case rebuildTable
}

public struct TFYCompositeIndex: Equatable, Codable {
    public let columns: [String]
    public let unique: Bool
    public let name: String?

    public init(columns: [String], unique: Bool = false, name: String? = nil) {
        self.columns = columns
        self.unique = unique
        self.name = name
    }
}

public struct TFYSwiftColumn: Equatable {
    public let propertyName: String
    public let name: String
    public let swiftType: String
    public let sqliteType: String
    public let isPrimaryKey: Bool
    public let isAutoIncrement: Bool
    public let isIndexed: Bool
    public let isUnique: Bool
    public let defaultSQL: String?
    public let isIgnored: Bool
    public let isOptional: Bool
    public let storageStrategy: TFYStorageStrategy
}

public struct TFYSwiftIndexDefinition: Equatable {
    public let name: String
    public let tableName: String
    public let columns: [String]
    public let unique: Bool

    public nonisolated var signature: String {
        "\(unique ? "unique" : "index")|\(columns.joined(separator: ","))"
    }
}

public struct TFYSwiftRebuildPlan {
    public let oldTableName: String
    public let temporaryTableName: String
    public let destinationColumns: [String]
    public let selectExpressions: [String]

    public init(
        oldTableName: String,
        temporaryTableName: String,
        destinationColumns: [String],
        selectExpressions: [String]
    ) {
        self.oldTableName = oldTableName
        self.temporaryTableName = temporaryTableName
        self.destinationColumns = destinationColumns
        self.selectExpressions = selectExpressions
    }
}

public struct TFYSwiftModelSchema {
    public let modelName: String
    public let tableName: String
    public let databaseName: String
    public let migrationPolicy: TFYMigrationPolicy
    public let columns: [TFYSwiftColumn]
    public let compositeIndexes: [TFYCompositeIndex]

    public nonisolated var persistedColumns: [TFYSwiftColumn] {
        columns.filter { !$0.isIgnored }
    }

    public nonisolated var primaryKeyColumn: TFYSwiftColumn? {
        persistedColumns.first(where: \.isPrimaryKey)
    }

    public nonisolated func column(forProperty propertyName: String) -> TFYSwiftColumn? {
        persistedColumns.first(where: { $0.propertyName == propertyName })
    }

    public nonisolated func column(named columnName: String) -> TFYSwiftColumn? {
        persistedColumns.first(where: { $0.name == columnName })
    }

    public nonisolated var signature: String {
        let columnSignature = persistedColumns.map { column in
            [
                column.name,
                column.sqliteType,
                column.isPrimaryKey ? "pk" : "",
                column.isAutoIncrement ? "ai" : "",
                column.isIndexed ? "idx" : "",
                column.isUnique ? "uniq" : "",
                column.defaultSQL ?? "",
                column.isOptional ? "optional" : "required",
                column.storageStrategy.rawValue
            ].joined(separator: "|")
        }.joined(separator: ";")

        let indexSignature = compositeIndexes.map { index in
            [
                index.name ?? "",
                index.unique ? "unique" : "index",
                index.columns.joined(separator: ",")
            ].joined(separator: "|")
        }.joined(separator: ";")

        return [modelName, tableName, databaseName, migrationPolicy.rawValue, columnSignature, indexSignature]
            .joined(separator: "#")
    }
}

public struct TFYSwiftMigrationReport {
    public let modelName: String
    public let tableName: String
    public let databaseName: String
    public let databasePath: String
    public private(set) var createdTableSQL: [String] = []
    public private(set) var addedColumnSQL: [String] = []
    public private(set) var createdIndexSQL: [String] = []
    public private(set) var rebuildSQL: [String] = []
    public private(set) var warnings: [String] = []

    public init(modelName: String, tableName: String, databaseName: String, databasePath: String) {
        self.modelName = modelName
        self.tableName = tableName
        self.databaseName = databaseName
        self.databasePath = databasePath
    }

    public nonisolated var hasChanges: Bool {
        !createdTableSQL.isEmpty || !addedColumnSQL.isEmpty || !createdIndexSQL.isEmpty || !rebuildSQL.isEmpty
    }

    public mutating func addCreatedTableSQL(_ sql: String) {
        createdTableSQL.append(sql)
    }

    public mutating func addAddedColumnSQL(_ sql: String) {
        addedColumnSQL.append(sql)
    }

    public mutating func addCreatedIndexSQL(_ sql: String) {
        createdIndexSQL.append(sql)
    }

    public mutating func addRebuildSQL(_ sql: String) {
        rebuildSQL.append(sql)
    }

    public mutating func addWarning(_ warning: String) {
        warnings.append(warning)
    }

    public nonisolated func formattedLines() -> [String] {
        var lines: [String] = []
        lines.append("Model: \(modelName)")
        lines.append("Table: \(tableName)")
        lines.append("Database: \(databaseName)")
        lines.append("Path: \(databasePath)")
        if createdTableSQL.isEmpty {
            lines.append("CREATE TABLE: none")
        } else {
            lines.append("CREATE TABLE:")
            lines.append(contentsOf: createdTableSQL.map { "  \($0)" })
        }
        if addedColumnSQL.isEmpty {
            lines.append("ADD COLUMN: none")
        } else {
            lines.append("ADD COLUMN:")
            lines.append(contentsOf: addedColumnSQL.map { "  \($0)" })
        }
        if createdIndexSQL.isEmpty {
            lines.append("CREATE INDEX: none")
        } else {
            lines.append("CREATE INDEX:")
            lines.append(contentsOf: createdIndexSQL.map { "  \($0)" })
        }
        if rebuildSQL.isEmpty {
            lines.append("REBUILD TABLE: none")
        } else {
            lines.append("REBUILD TABLE:")
            lines.append(contentsOf: rebuildSQL.map { "  \($0)" })
        }
        if warnings.isEmpty {
            lines.append("Warnings: none")
        } else {
            lines.append("Warnings:")
            lines.append(contentsOf: warnings.map { "  \($0)" })
        }
        return lines
    }
}
