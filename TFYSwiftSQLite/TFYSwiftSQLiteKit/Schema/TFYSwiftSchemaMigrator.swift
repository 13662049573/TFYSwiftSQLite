import Foundation

public enum TFYSwiftSchemaMigrator {
    public static let journalTableName = "__tfy_schema_journal"

    public static func migrate<Model: TFYSwiftDBModel>(_ modelType: Model.Type, connection: TFYSwiftDBConnection) throws -> TFYSwiftMigrationReport {
        try ensureJournalTable(using: connection)
        let schema = try TFYSwiftModelMirror.schema(for: modelType)
        try modelType.willMigrate(using: connection, schema: schema)

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
            try recordMigration(report: report, schema: schema, using: connection)
            try modelType.didMigrate(report: report, using: connection, schema: schema)
            return report
        }

        let existingColumns = try connection.pragmaTableInfo(tableName: schema.tableName)
        let existingColumnMap = Dictionary(uniqueKeysWithValues: existingColumns.map { ($0.name, $0) })
        var rebuildReasons: [String] = []

        for column in schema.persistedColumns {
            if existingColumnMap[column.name] == nil {
                let sql = TFYSwiftTableBuilder.addColumnSQL(tableName: schema.tableName, column: column)
                try connection.execute(sql)
                report.addAddedColumnSQL(sql)
                continue
            }

            guard let existing = existingColumnMap[column.name] else { continue }
            if existing.type.uppercased() != column.sqliteType.uppercased() {
                rebuildReasons.append("Column \(column.name) type differs: existing \(existing.type), expected \(column.sqliteType).")
            }
            if existing.isPrimaryKey != column.isPrimaryKey {
                rebuildReasons.append("Column \(column.name) primary key flag differs.")
            }
            let existingDefault = existing.defaultValueSQL?.trimmingCharacters(in: .whitespacesAndNewlines)
            let expectedDefault = column.defaultSQL?.trimmingCharacters(in: .whitespacesAndNewlines)
            if existingDefault != expectedDefault, expectedDefault != nil {
                rebuildReasons.append("Column \(column.name) default differs: existing \(existingDefault ?? "nil"), expected \(expectedDefault ?? "nil").")
            }
        }

        let expectedColumnNames = Set(schema.persistedColumns.map(\.name))
        let removedColumns = existingColumns.map(\.name).filter { !expectedColumnNames.contains($0) }
        if !removedColumns.isEmpty {
            rebuildReasons.append("Columns removed from model: \(removedColumns.joined(separator: ", ")).")
        }

        if !rebuildReasons.isEmpty {
            switch schema.migrationPolicy {
            case .safe:
                for reason in rebuildReasons {
                    report.addWarning("\(reason) Safe migration leaves table as-is.")
                }
            case .rebuildTable:
                try rebuildTable(
                    modelType,
                    schema: schema,
                    existingColumns: existingColumns,
                    connection: connection,
                    report: &report,
                    reasons: rebuildReasons
                )
            }
        }

        let expectedIndexes = TFYSwiftIndexBuilder.expectedIndexes(for: schema)
        let existingIndexes = report.rebuildSQL.isEmpty ? try connection.pragmaIndexList(tableName: schema.tableName) : []
        let existingSignatures = Set(existingIndexes.map { "\($0.unique ? "unique" : "index")|\($0.columns.joined(separator: ","))" })
        let existingNames = Set(existingIndexes.map(\.name))

        for index in expectedIndexes where !existingNames.contains(index.name) && !existingSignatures.contains(index.signature) {
            let sql = TFYSwiftIndexBuilder.createIndexSQL(for: index)
            try connection.execute(sql)
            report.addCreatedIndexSQL(sql)
        }

        try recordMigration(report: report, schema: schema, using: connection)
        try modelType.didMigrate(report: report, using: connection, schema: schema)
        return report
    }

    private static func ensureJournalTable(using connection: TFYSwiftDBConnection) throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS \(TFYSwiftSQL.escapeIdentifier(journalTableName)) (
            "table_name" TEXT PRIMARY KEY,
            "model_name" TEXT NOT NULL,
            "database_name" TEXT NOT NULL,
            "schema_signature" TEXT NOT NULL,
            "updated_at" REAL NOT NULL,
            "report_json" TEXT NOT NULL
        );
        """
        try connection.execute(sql)
    }

    private static func recordMigration(
        report: TFYSwiftMigrationReport,
        schema: TFYSwiftModelSchema,
        using connection: TFYSwiftDBConnection
    ) throws {
        let payload: [String: Any] = [
            "modelName": report.modelName,
            "tableName": report.tableName,
            "databaseName": report.databaseName,
            "databasePath": report.databasePath,
            "createdTableSQL": report.createdTableSQL,
            "addedColumnSQL": report.addedColumnSQL,
            "createdIndexSQL": report.createdIndexSQL,
            "warnings": report.warnings,
            "hasChanges": report.hasChanges
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw TFYSwiftDBError.encoding("Unable to serialize migration report journal payload.")
        }

        let sql = """
        INSERT INTO \(TFYSwiftSQL.escapeIdentifier(journalTableName))
        ("table_name", "model_name", "database_name", "schema_signature", "updated_at", "report_json")
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT("table_name") DO UPDATE SET
            "model_name" = excluded."model_name",
            "database_name" = excluded."database_name",
            "schema_signature" = excluded."schema_signature",
            "updated_at" = excluded."updated_at",
            "report_json" = excluded."report_json";
        """

        try connection.execute(
            sql,
            bindings: [
                .text(schema.tableName),
                .text(schema.modelName),
                .text(schema.databaseName),
                .text(schema.signature),
                .double(Date().timeIntervalSince1970),
                .text(json)
            ]
        )
    }

    private static func rebuildTable<Model: TFYSwiftDBModel>(
        _ modelType: Model.Type,
        schema: TFYSwiftModelSchema,
        existingColumns: [TFYSQLiteTableColumnInfo],
        connection: TFYSwiftDBConnection,
        report: inout TFYSwiftMigrationReport,
        reasons: [String]
    ) throws {
        let temporaryTableName = "__tfy_rebuild_\(schema.tableName)_\(Int(Date().timeIntervalSince1970))"
        let existingColumnNames = Set(existingColumns.map(\.name))
        let renamedColumns = try modelType.renamedColumns(for: schema, existingColumns: existingColumns)
        let customExpressions = try modelType.rebuildExpressions(for: schema, existingColumns: existingColumns)

        var destinationColumns: [String] = []
        var selectExpressions: [String] = []

        for column in schema.persistedColumns {
            let expression = customExpressions[column.name]
                ?? defaultRebuildExpression(
                    for: column,
                    existingColumnNames: existingColumnNames,
                    renamedColumns: renamedColumns
                )
            guard let expression else {
                continue
            }
            destinationColumns.append(column.name)
            selectExpressions.append(expression)
        }

        let plan = TFYSwiftRebuildPlan(
            oldTableName: schema.tableName,
            temporaryTableName: temporaryTableName,
            destinationColumns: destinationColumns,
            selectExpressions: selectExpressions
        )
        try modelType.willRebuildTable(using: connection, schema: schema, plan: plan)

        try connection.withTransaction {
            let createSQL = TFYSwiftTableBuilder.createTableSQL(for: schema, tableName: temporaryTableName)
            try connection.execute(createSQL)
            report.addRebuildSQL(createSQL)

            if !destinationColumns.isEmpty {
                let destination = destinationColumns.map(TFYSwiftSQL.escapeIdentifier).joined(separator: ", ")
                let insertSQL = """
                INSERT INTO \(TFYSwiftSQL.escapeIdentifier(temporaryTableName)) (\(destination))
                SELECT \(selectExpressions.joined(separator: ", "))
                FROM \(TFYSwiftSQL.escapeIdentifier(schema.tableName));
                """
                try connection.execute(insertSQL)
                report.addRebuildSQL(insertSQL)
            }

            try modelType.validateRebuiltTable(using: connection, schema: schema, plan: plan)

            let dropSQL = "DROP TABLE \(TFYSwiftSQL.escapeIdentifier(schema.tableName));"
            try connection.execute(dropSQL)
            report.addRebuildSQL(dropSQL)

            let renameSQL = """
            ALTER TABLE \(TFYSwiftSQL.escapeIdentifier(temporaryTableName))
            RENAME TO \(TFYSwiftSQL.escapeIdentifier(schema.tableName));
            """
            try connection.execute(renameSQL)
            report.addRebuildSQL(renameSQL)
        }

        for reason in reasons {
            report.addWarning("\(reason) Rebuilt table under rebuildTable policy.")
        }
        try modelType.didRebuildTable(report: report, using: connection, schema: schema, plan: plan)
    }

    private static func defaultRebuildExpression(
        for column: TFYSwiftColumn,
        existingColumnNames: Set<String>,
        renamedColumns: [String: String]
    ) -> String? {
        if existingColumnNames.contains(column.name) {
            return TFYSwiftSQL.escapeIdentifier(column.name)
        }
        if let oldName = renamedColumns[column.name], existingColumnNames.contains(oldName) {
            return TFYSwiftSQL.escapeIdentifier(oldName)
        }
        if let defaultSQL = column.defaultSQL {
            return defaultSQL
        }
        if column.isOptional {
            return "NULL"
        }
        return "NULL"
    }
}
