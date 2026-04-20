import Foundation

public enum TFYSwiftORM {
    @discardableResult
    public static func createTable<Model: TFYSwiftDBModel>(_ modelType: Model.Type) throws -> TFYSwiftMigrationReport {
        try TFYSwiftAutoTable.create(modelType)
    }

    public static func insert<Model: TFYSwiftDBModel>(_ model: Model) throws {
        try persist(model, orReplace: false)
    }

    public static func insert<Model: TFYSwiftDBModel>(_ models: [Model]) throws {
        guard !models.isEmpty else { return }
        let schema = try TFYSwiftModelMirror.schema(for: Model.self)
        let connection = try TFYSwiftDatabaseCenter.shared.open(named: schema.databaseName)
        try connection.withTransaction {
            for model in models {
                try persist(model, orReplace: false, connection: connection)
            }
        }
    }

    public static func insertOrReplace<Model: TFYSwiftDBModel>(_ model: Model) throws {
        try persist(model, orReplace: true)
    }

    public static func insertOrReplace<Model: TFYSwiftDBModel>(_ models: [Model]) throws {
        guard !models.isEmpty else { return }
        let schema = try TFYSwiftModelMirror.schema(for: Model.self)
        let connection = try TFYSwiftDatabaseCenter.shared.open(named: schema.databaseName)
        try connection.withTransaction {
            for model in models {
                try persist(model, orReplace: true, connection: connection)
            }
        }
    }

    public static func update<Model: TFYSwiftDBModel>(_ model: Model) throws {
        let schema = try TFYSwiftModelMirror.schema(for: Model.self)
        guard let primaryKey = schema.primaryKeyColumn else {
            throw TFYSwiftDBError.missingPrimaryKey("\(schema.modelName) requires a primary key to run update(_:).")
        }

        let valueMap = try TFYSwiftModelMirror.propertyValueMap(from: model)
        guard let pkValue = valueMap[primaryKey.propertyName] else {
            throw TFYSwiftDBError.missingPrimaryKey("Missing primary key value for \(primaryKey.propertyName).")
        }

        let pkBindValue = try TFYSwiftTypeMapper.bindValue(for: pkValue, column: primaryKey)
        let assignments = schema.persistedColumns
            .filter { !$0.isPrimaryKey }
            .map { "\(TFYSwiftSQL.escapeIdentifier($0.name)) = ?" }
            .joined(separator: ", ")

        let bindings = try schema.persistedColumns
            .filter { !$0.isPrimaryKey }
            .map { column in
                let raw = valueMap[column.propertyName] ?? Optional<Int>.none as Any
                return try TFYSwiftTypeMapper.bindValue(for: raw, column: column)
            } + [pkBindValue]

        let sql = """
        UPDATE \(TFYSwiftSQL.escapeIdentifier(schema.tableName))
        SET \(assignments)
        WHERE \(TFYSwiftSQL.escapeIdentifier(primaryKey.name)) = ?;
        """

        let connection = try TFYSwiftDatabaseCenter.shared.open(named: schema.databaseName)
        try connection.execute(sql, bindings: bindings)
    }

    public static func delete<Model: TFYSwiftDBModel>(_ model: Model) throws {
        let schema = try TFYSwiftModelMirror.schema(for: Model.self)
        guard let primaryKey = schema.primaryKeyColumn else {
            throw TFYSwiftDBError.missingPrimaryKey("\(schema.modelName) requires a primary key to run delete(_:).")
        }
        let valueMap = try TFYSwiftModelMirror.propertyValueMap(from: model)
        guard let rawPrimaryKey = valueMap[primaryKey.propertyName] else {
            throw TFYSwiftDBError.missingPrimaryKey("Missing primary key value for \(primaryKey.propertyName).")
        }
        let bindValue = try TFYSwiftTypeMapper.bindValue(for: rawPrimaryKey, column: primaryKey)
        try delete(Model.self, byPrimaryKeyBindValue: bindValue)
    }

    public static func delete<Model: TFYSwiftDBModel>(_ modelType: Model.Type, byPrimaryKey value: Any) throws {
        let bindValue = try TFYSwiftTypeMapper.userBindValue(for: value)
        try delete(modelType, byPrimaryKeyBindValue: bindValue)
    }

    public static func fetchAll<Model: TFYSwiftDBModel>(_ modelType: Model.Type, where clause: String? = nil, bindings: [TFYSQLiteBindValue?] = []) throws -> [Model] {
        let suffix = clause.map { " WHERE \($0)" }
        return try fetchAll(modelType, sqlSuffix: suffix, bindings: bindings)
    }

    private static func fetchAll<Model: TFYSwiftDBModel>(
        _ modelType: Model.Type,
        sqlSuffix: String?,
        bindings: [TFYSQLiteBindValue?]
    ) throws -> [Model] {
        let schema = try TFYSwiftModelMirror.schema(for: modelType)
        let connection = try TFYSwiftDatabaseCenter.shared.open(named: schema.databaseName)
        let sql = "SELECT * FROM \(TFYSwiftSQL.escapeIdentifier(schema.tableName))\(sqlSuffix ?? "");"
        let rows = try connection.query(sql, bindings: bindings)
        return try rows.map { row in
            let object = try TFYSwiftTypeMapper.jsonObject(from: row, schema: schema, modelType: modelType)
            let data = try JSONSerialization.data(withJSONObject: object)
            return try JSONDecoder().decode(Model.self, from: data)
        }
    }

    public static func fetchAll<Model: TFYSwiftDBModel>(_ modelType: Model.Type, _ query: TFYQuery<Model>) throws -> [Model] {
        let rendered = try query.render()
        let suffix = rendered.clause.map { " \($0)" }
        return try fetchAll(modelType, sqlSuffix: suffix, bindings: rendered.bindings)
    }

    public static func fetchPage<Model: TFYSwiftDBModel>(
        _ modelType: Model.Type,
        where clause: String? = nil,
        orderBy: String? = nil,
        limit: Int,
        offset: Int = 0,
        bindings: [TFYSQLiteBindValue?] = []
    ) throws -> [Model] {
        guard limit > 0 else {
            throw TFYSwiftDBError.invalidQuery("fetchPage limit must be greater than zero.")
        }
        guard offset >= 0 else {
            throw TFYSwiftDBError.invalidQuery("fetchPage offset must be greater than or equal to zero.")
        }

        let orderClause = orderBy.map { " ORDER BY \($0)" } ?? ""
        let pageClause = " LIMIT \(limit) OFFSET \(offset)"
        let suffix = clause.map { " WHERE \($0)\(orderClause)\(pageClause)" } ?? "\(orderClause)\(pageClause)"
        return try fetchAll(modelType, sqlSuffix: suffix, bindings: bindings)
    }

    public static func fetch<Model: TFYSwiftDBModel>(_ modelType: Model.Type, byPrimaryKey value: Any) throws -> Model? {
        let schema = try TFYSwiftModelMirror.schema(for: modelType)
        guard let primaryKey = schema.primaryKeyColumn else {
            throw TFYSwiftDBError.missingPrimaryKey("\(schema.modelName) requires a primary key to run fetch(byPrimaryKey:).")
        }
        let bindValue = try TFYSwiftTypeMapper.userBindValue(for: value)
        return try fetchAll(
            modelType,
            where: "\(TFYSwiftSQL.escapeIdentifier(primaryKey.name)) = ? LIMIT 1",
            bindings: [bindValue]
        ).first
    }

    public static func count<Model: TFYSwiftDBModel>(
        _ modelType: Model.Type,
        where clause: String? = nil,
        bindings: [TFYSQLiteBindValue?] = []
    ) throws -> Int {
        let schema = try TFYSwiftModelMirror.schema(for: modelType)
        let connection = try TFYSwiftDatabaseCenter.shared.open(named: schema.databaseName)
        let suffix = clause.map { " WHERE \($0)" } ?? ""
        let sql = "SELECT COUNT(*) AS count FROM \(TFYSwiftSQL.escapeIdentifier(schema.tableName))\(suffix);"
        guard let value = try connection.scalar(sql, bindings: bindings) else {
            return 0
        }
        return Int(TFYSwiftTypeMapper.numericValue(from: value))
    }

    public static func count<Model: TFYSwiftDBModel>(_ modelType: Model.Type, _ query: TFYQuery<Model>) throws -> Int {
        let rendered = try query.render()
        let schema = try TFYSwiftModelMirror.schema(for: modelType)
        let connection = try TFYSwiftDatabaseCenter.shared.open(named: schema.databaseName)
        let suffix = rendered.clause.map { " \($0)" } ?? ""
        let sql = "SELECT COUNT(*) AS count FROM \(TFYSwiftSQL.escapeIdentifier(schema.tableName))\(suffix);"
        guard let value = try connection.scalar(sql, bindings: rendered.bindings) else {
            return 0
        }
        return Int(TFYSwiftTypeMapper.numericValue(from: value))
    }

    public static func exists<Model: TFYSwiftDBModel>(
        _ modelType: Model.Type,
        where clause: String? = nil,
        bindings: [TFYSQLiteBindValue?] = []
    ) throws -> Bool {
        try count(modelType, where: clause, bindings: bindings) > 0
    }

    public static func exists<Model: TFYSwiftDBModel>(_ modelType: Model.Type, _ query: TFYQuery<Model>) throws -> Bool {
        try count(modelType, query) > 0
    }

    public static func transaction<Model: TFYSwiftDBModel>(_ modelType: Model.Type, _ block: () throws -> Void) throws {
        let schema = try TFYSwiftModelMirror.schema(for: modelType)
        let connection = try TFYSwiftDatabaseCenter.shared.open(named: schema.databaseName)
        try connection.withTransaction(block)
    }

    private static func persist<Model: TFYSwiftDBModel>(
        _ model: Model,
        orReplace: Bool,
        connection providedConnection: TFYSwiftDBConnection? = nil
    ) throws {
        let schema = try TFYSwiftModelMirror.schema(for: Model.self)
        let valueMap = try TFYSwiftModelMirror.propertyValueMap(from: model)

        var insertColumns: [TFYSwiftColumn] = []
        var bindings: [TFYSQLiteBindValue] = []

        for column in schema.persistedColumns {
            let raw = valueMap[column.propertyName] ?? Optional<Int>.none as Any
            let bindValue = try TFYSwiftTypeMapper.bindValue(for: raw, column: column)

            if column.isPrimaryKey, column.isAutoIncrement,
               case let .integer(number) = bindValue, number == 0 {
                continue
            }

            insertColumns.append(column)
            bindings.append(bindValue)
        }

        let quotedColumns = insertColumns.map { TFYSwiftSQL.escapeIdentifier($0.name) }.joined(separator: ", ")
        let placeholders = Array(repeating: "?", count: insertColumns.count).joined(separator: ", ")
        let verb = orReplace ? "INSERT OR REPLACE" : "INSERT"
        let sql = """
        \(verb) INTO \(TFYSwiftSQL.escapeIdentifier(schema.tableName)) (\(quotedColumns))
        VALUES (\(placeholders));
        """

        let connection = try providedConnection ?? TFYSwiftDatabaseCenter.shared.open(named: schema.databaseName)
        try connection.execute(sql, bindings: bindings)
    }

    private static func delete<Model: TFYSwiftDBModel>(_ modelType: Model.Type, byPrimaryKeyBindValue value: TFYSQLiteBindValue) throws {
        let schema = try TFYSwiftModelMirror.schema(for: modelType)
        guard let primaryKey = schema.primaryKeyColumn else {
            throw TFYSwiftDBError.missingPrimaryKey("\(schema.modelName) requires a primary key to run delete(byPrimaryKey:).")
        }
        let sql = """
        DELETE FROM \(TFYSwiftSQL.escapeIdentifier(schema.tableName))
        WHERE \(TFYSwiftSQL.escapeIdentifier(primaryKey.name)) = ?;
        """
        let connection = try TFYSwiftDatabaseCenter.shared.open(named: schema.databaseName)
        try connection.execute(sql, bindings: [value])
    }

    public static func delete<Model: TFYSwiftDBModel>(_ modelType: Model.Type, _ query: TFYQuery<Model>) throws {
        let schema = try TFYSwiftModelMirror.schema(for: modelType)
        let rendered = try query.render()
        guard rendered.clause != nil else {
            throw TFYSwiftDBError.invalidQuery("Refusing to delete all rows with an empty query. Provide a predicate.")
        }
        let whereClause = rendered.clause.map { " \($0)" } ?? ""
        let sql = "DELETE FROM \(TFYSwiftSQL.escapeIdentifier(schema.tableName))\(whereClause);"
        let connection = try TFYSwiftDatabaseCenter.shared.open(named: schema.databaseName)
        try connection.execute(sql, bindings: rendered.bindings)
    }
}
