//
//  TFYSwiftSchemaMigrator.swift
//  TFYSwiftSQLiteKit
//
//  Created by 田风有 on 2021/5/9.
//

import Foundation

public enum TFYSwiftSchemaMigrator {
    public static let journalTableName = "__tfy_schema_journal"

    public static func migrate<Model: TFYSwiftDBModel>(_ modelType: Model.Type, connection: TFYSwiftDBConnection) throws -> TFYSwiftMigrationReport {
        try connection.withTransaction {
            try performMigration(modelType, connection: connection)
        }
    }

    private static func performMigration<Model: TFYSwiftDBModel>(
        _ modelType: Model.Type,
        connection: TFYSwiftDBConnection
    ) throws -> TFYSwiftMigrationReport {
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
                let sql = try validatedIndexSQL(for: index, connection: connection)
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
        var columnsToAdd: [TFYSwiftColumn] = []
        let renamedColumns = schema.migrationPolicy == .rebuildTable
            ? try modelType.renamedColumns(for: schema, existingColumns: existingColumns)
            : [:]

        for (newName, oldName) in renamedColumns {
            guard schema.column(named: newName) != nil else {
                throw TFYSwiftDBError.migrationConflict("Rename destination '\(newName)' is not declared by \(schema.modelName).")
            }
            guard existingColumnMap[oldName] != nil else {
                throw TFYSwiftDBError.migrationConflict("Rename source '\(oldName)' does not exist in table '\(schema.tableName)'.")
            }
        }

        for column in schema.persistedColumns {
            if existingColumnMap[column.name] == nil {
                if renamedColumns[column.name] != nil {
                    rebuildReasons.append("Column \(column.name) is renamed from \(renamedColumns[column.name]!).")
                    continue
                }
                if column.isPrimaryKey {
                    rebuildReasons.append("Primary key column \(column.name) cannot be added with ALTER TABLE.")
                    continue
                }

                // A populated table cannot safely gain a required column without a
                // value source. Under rebuildTable, defer it to the rebuild hooks;
                // under safe, validate before attempting ALTER TABLE.
                if !column.isOptional, column.defaultSQL == nil, schema.migrationPolicy == .rebuildTable {
                    rebuildReasons.append("Required column \(column.name) needs values supplied during table rebuild.")
                    continue
                }
                columnsToAdd.append(column)
                continue
            }

            guard let existing = existingColumnMap[column.name] else { continue }
            if existing.type.uppercased() != column.sqliteType.uppercased() {
                rebuildReasons.append("Column \(column.name) type differs: existing \(existing.type), expected \(column.sqliteType).")
            }
            if existing.isPrimaryKey != column.isPrimaryKey {
                rebuildReasons.append("Column \(column.name) primary key flag differs.")
            }
            let expectsNotNull = !column.isOptional
            if existing.isNotNull != expectsNotNull {
                rebuildReasons.append(
                    "Column \(column.name) nullability differs: existing \(existing.isNotNull ? "NOT NULL" : "NULL"), expected \(column.isOptional ? "NULL" : "NOT NULL")."
                )
            }
            let existingDefault = existing.defaultValueSQL?.trimmingCharacters(in: .whitespacesAndNewlines)
            let expectedDefault = column.defaultSQL?.trimmingCharacters(in: .whitespacesAndNewlines)
            if existingDefault != expectedDefault {
                rebuildReasons.append("Column \(column.name) default differs: existing \(existingDefault ?? "nil"), expected \(expectedDefault ?? "nil").")
            }
        }

        let expectedColumnNames = Set(schema.persistedColumns.map(\.name))
        let removedColumns = existingColumns.map(\.name).filter { !expectedColumnNames.contains($0) }
        if !removedColumns.isEmpty {
            rebuildReasons.append("Columns removed from model: \(removedColumns.joined(separator: ", ")).")
        }

        // Decide whether to rebuild before applying incremental changes so the
        // source schema snapshot and copy plan cannot become stale mid-migration.
        if !rebuildReasons.isEmpty, schema.migrationPolicy == .rebuildTable {
            try rebuildTable(
                modelType,
                schema: schema,
                existingColumns: existingColumns,
                connection: connection,
                report: &report,
                reasons: rebuildReasons
            )
        } else {
            if columnsToAdd.contains(where: { !$0.isOptional && $0.defaultSQL == nil }),
               try connection.scalar(
                   "SELECT 1 FROM \(TFYSwiftSQL.escapeIdentifier(schema.tableName)) LIMIT 1;"
               ) != nil {
                let names = columnsToAdd
                    .filter { !$0.isOptional && $0.defaultSQL == nil }
                    .map(\.name)
                    .joined(separator: ", ")
                throw TFYSwiftDBError.migrationConflict(
                    "Cannot safely add required columns without defaults to non-empty table '\(schema.tableName)': \(names). Add @TFYDefault or use rebuildTable with rename/custom expressions."
                )
            }

            for column in columnsToAdd {
                let sql = TFYSwiftTableBuilder.addColumnSQL(tableName: schema.tableName, column: column)
                try connection.execute(sql)
                report.addAddedColumnSQL(sql)
            }

            for reason in rebuildReasons {
                report.addWarning("\(reason) Safe migration leaves table as-is.")
            }
        }

        let expectedIndexes = TFYSwiftIndexBuilder.expectedIndexes(for: schema)
        let existingIndexes = try connection.pragmaIndexList(tableName: schema.tableName)
        func matches(_ existing: TFYSQLiteIndexInfo, _ expected: TFYSwiftIndexDefinition) -> Bool {
            !existing.isPartial && !existing.usesCustomComparison && existing.unique == expected.unique &&
                existing.columns.map { $0.lowercased() } == expected.columns.map { $0.lowercased() }
        }
        for index in expectedIndexes {
            if let named = existingIndexes.first(where: { $0.name.caseInsensitiveCompare(index.name) == .orderedSame }) {
                guard matches(named, index) else {
                    throw TFYSwiftDBError.migrationConflict("Index '\(index.name)' exists with a different definition.")
                }
                continue
            }
            guard !existingIndexes.contains(where: { matches($0, index) }) else { continue }
            let sql = try validatedIndexSQL(for: index, connection: connection)
            try connection.execute(sql)
            report.addCreatedIndexSQL(sql)
        }

        try recordMigration(report: report, schema: schema, using: connection)
        try modelType.didMigrate(report: report, using: connection, schema: schema)
        return report
    }

    private static func validatedIndexSQL(for index: TFYSwiftIndexDefinition, connection: TFYSwiftDBConnection) throws -> String {
        let rows = try connection.query(
            "SELECT tbl_name FROM sqlite_master WHERE type = 'index' AND name = ? COLLATE NOCASE;",
            bindings: [.text(index.name)]
        )
        if let table = rows.first?["tbl_name"],
           TFYSwiftTypeMapper.stringValue(from: table).caseInsensitiveCompare(index.tableName) != .orderedSame {
            throw TFYSwiftDBError.migrationConflict("Index '\(index.name)' belongs to another table. Index names must be unique throughout the database.")
        }
        return TFYSwiftIndexBuilder.createIndexSQL(for: index)
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
            "rebuildSQL": report.rebuildSQL,
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
        // The generated replacement cannot reproduce constraints declared only in raw SQL.
        let tableIndexes = try connection.query("PRAGMA index_list(\(TFYSwiftSQL.escapeIdentifier(schema.tableName)));")
        let extendedColumns = try connection.query("PRAGMA table_xinfo(\(TFYSwiftSQL.escapeIdentifier(schema.tableName)));")
        let tableSQL = try connection.scalar("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ? COLLATE NOCASE;",
                                             bindings: [.text(schema.tableName)]).map(TFYSwiftTypeMapper.stringValue(from:)) ?? ""
        let advancedSyntax = tableSQL.range(of: "(?i)\\b(CHECK\\s*\\(|COLLATE\\s+|WITHOUT\\s+ROWID|STRICT\\s*$)", options: .regularExpression) != nil
        guard !tableIndexes.contains(where: { $0["origin"] == .text("u") }),
              existingColumns.filter(\.isPrimaryKey).count <= 1,
              !extendedColumns.contains(where: { ($0["hidden"].map(TFYSwiftTypeMapper.numericValue(from:)) ?? 0) != 0 }),
              !advancedSyntax else {
            throw TFYSwiftDBError.migrationConflict("Automatic rebuild cannot preserve raw SQL UNIQUE/CHECK/collation/generated/compound-key or advanced table constraints. Use an explicit application migration.")
        }
        // DROP TABLE can execute ON DELETE CASCADE before a replacement is renamed.
        // This ORM does not model FK/view definitions: require an explicit application migration instead.
        let tables = try connection.query("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%';")
        for table in tables {
            guard case let .text(name)? = table["name"] else { continue }
            let foreignKeys = try connection.query("PRAGMA foreign_key_list(\(TFYSwiftSQL.escapeIdentifier(name)));")
            if (name == schema.tableName && !foreignKeys.isEmpty) || foreignKeys.contains(where: {
                guard case let .text(target)? = $0["table"] else { return false }
                return target.caseInsensitiveCompare(schema.tableName) == .orderedSame
            }) {
                throw TFYSwiftDBError.migrationConflict("Automatic rebuild of '\(schema.tableName)' is unsafe with foreign-key dependencies. Use an explicit application migration.")
            }
        }
        guard try connection.scalar("SELECT 1 FROM sqlite_master WHERE type = 'view' LIMIT 1;") == nil else {
            throw TFYSwiftDBError.migrationConflict("Automatic rebuild is disabled in databases containing views. Migrate dependent views explicitly.")
        }
        let dependentObjects = try connection.query(
            "SELECT name, type, sql FROM sqlite_master WHERE tbl_name = ? AND type IN ('trigger', 'index') AND sql IS NOT NULL;",
            bindings: [.text(schema.tableName)]
        )
        let expectedIndexNames = Set(TFYSwiftIndexBuilder.expectedIndexes(for: schema).map { $0.name.lowercased() })
        let oldIndexes = try connection.pragmaIndexList(tableName: schema.tableName)
        let managedIndexSQL = Set(oldIndexes.filter { expectedIndexNames.contains($0.name.lowercased()) }.map { $0.name })
        let sequence = try connection.tableExists("sqlite_sequence")
            ? try connection.scalar("SELECT seq FROM sqlite_sequence WHERE name = ?;", bindings: [.text(schema.tableName)])
            : nil
        let temporaryTableName = "__tfy_rebuild_\(schema.tableName)_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let existingColumnNames = Set(existingColumns.map(\.name))
        let renamedColumns = try modelType.renamedColumns(for: schema, existingColumns: existingColumns)
        let customExpressions = try modelType.rebuildExpressions(for: schema, existingColumns: existingColumns)

        var destinationColumns: [String] = []
        var selectExpressions: [String] = []

        for column in schema.persistedColumns {
            let expression = try customExpressions[column.name]
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

            // Preserve user triggers and unmanaged indexes. Invalid definitions roll back the WHOLE migration.
            for object in dependentObjects {
                guard case let .text(sql)? = object["sql"] else { continue }
                if case let .text(name)? = object["name"], managedIndexSQL.contains(name) { continue }
                try connection.execute(sql)
                report.addRebuildSQL(sql)
            }
            // CREATE TRIGGER permits unresolved NEW/OLD columns. Compile all DML paths
            // without executing them so a broken restored trigger rolls back migration.
            if dependentObjects.contains(where: { $0["type"] == .text("trigger") }) {
                let table = TFYSwiftSQL.escapeIdentifier(schema.tableName)
                let assignments = schema.persistedColumns.map {
                    let name = TFYSwiftSQL.escapeIdentifier($0.name)
                    return "\(name) = \(name)"
                }.joined(separator: ", ")
                for sql in ["EXPLAIN INSERT INTO \(table) DEFAULT VALUES;",
                            "EXPLAIN UPDATE \(table) SET \(assignments) WHERE 0;",
                            "EXPLAIN DELETE FROM \(table) WHERE 0;"] {
                    _ = try connection.prepare(sql)
                }
            }
            if let sequence, schema.primaryKeyColumn?.isAutoIncrement == true {
                // A deleted high row ID must not become eligible for reuse after rebuilding.
                let previous = TFYSwiftTypeMapper.numericValue(from: sequence)
                try connection.execute("UPDATE sqlite_sequence SET seq = MAX(seq, ?) WHERE name = ?;",
                                       bindings: [.integer(previous), .text(schema.tableName)])
                if connection.changes == 0 {
                    try connection.execute("INSERT INTO sqlite_sequence(name, seq) VALUES (?, ?);",
                                           bindings: [.text(schema.tableName), .integer(previous)])
                }
            }
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
    ) throws -> String? {
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
        throw TFYSwiftDBError.migrationConflict(
            "Cannot rebuild required column '\(column.name)' without an existing value, rename source, default, or custom expression."
        )
    }
}
