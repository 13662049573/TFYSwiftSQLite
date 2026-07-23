import Foundation

public enum TFYSwiftModelMirror {
    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var schemas: [ObjectIdentifier: TFYSwiftModelSchema] = [:]
    }

    private static let cache = Cache()

    public static func schema<Model: TFYSwiftDBModel>(for modelType: Model.Type) throws -> TFYSwiftModelSchema {
        let cacheKey = ObjectIdentifier(modelType)
        cache.lock.lock()
        let cached = cache.schemas[cacheKey]
        cache.lock.unlock()
        if let cached {
            return cached
        }

        let schema = try buildSchema(for: modelType)
        cache.lock.lock()
        cache.schemas[cacheKey] = schema
        cache.lock.unlock()
        return schema
    }

    /// Clears cached reflection metadata. Model schema declarations should normally be immutable;
    /// this hook is intended for tests and advanced dynamic configurations.
    public static func clearSchemaCache() {
        cache.lock.lock()
        cache.schemas.removeAll()
        cache.lock.unlock()
    }

    private static func buildSchema<Model: TFYSwiftDBModel>(for modelType: Model.Type) throws -> TFYSwiftModelSchema {
        let model = Model.init()
        let mirror = Mirror(reflecting: model)
        var columns: [TFYSwiftColumn] = []

        for child in mirror.children {
            guard let label = child.label else { continue }
            let parsed = try parse(label: label, value: child.value)
            guard !parsed.annotation.isIgnored else { continue }

            let sqliteType = try TFYSwiftTypeMapper.sqliteType(
                for: parsed.valueType,
                storageStrategy: parsed.annotation.storageStrategy
            )

            let column = TFYSwiftColumn(
                propertyName: parsed.propertyName,
                name: parsed.annotation.nameOverride ?? parsed.propertyName,
                swiftType: TFYSwiftTypeMapper.normalizedTypeName(from: parsed.valueType),
                sqliteType: sqliteType,
                isPrimaryKey: parsed.annotation.isPrimaryKey,
                isAutoIncrement: parsed.annotation.isAutoIncrement,
                isIndexed: parsed.annotation.isIndexed,
                isUnique: parsed.annotation.isUnique,
                defaultSQL: parsed.annotation.defaultSQL,
                isIgnored: parsed.annotation.isIgnored,
                isOptional: TFYSwiftTypeMapper.isOptionalType(parsed.valueType),
                storageStrategy: parsed.annotation.storageStrategy
            )
            columns.append(column)
        }

        let primaryKeys = columns.filter(\.isPrimaryKey)
        guard !columns.isEmpty else {
            throw TFYSwiftDBError.invalidModel("\(String(describing: modelType)) does not declare any persisted columns.")
        }
        try validateIdentifier(modelType.tableName, kind: "table", modelType: modelType)
        try validateIdentifier(modelType.databaseName, kind: "database", modelType: modelType)
        for column in columns {
            try validateIdentifier(column.name, kind: "column", modelType: modelType)
        }
        if primaryKeys.count > 1 {
            throw TFYSwiftDBError.invalidModel("\(String(describing: modelType)) declares more than one primary key. v1 supports a single primary key.")
        }

        let duplicateColumnNames = Dictionary(grouping: columns, by: \.name)
            .filter { $0.value.count > 1 }
            .keys
            .sorted()
        guard duplicateColumnNames.isEmpty else {
            throw TFYSwiftDBError.invalidModel(
                "\(String(describing: modelType)) maps multiple properties to duplicate columns: \(duplicateColumnNames.joined(separator: ", "))."
            )
        }

        for column in columns where column.isAutoIncrement {
            guard column.isPrimaryKey, column.sqliteType == "INTEGER" else {
                throw TFYSwiftDBError.invalidModel(
                    "\(String(describing: modelType)).\(column.propertyName) can use autoIncrement only on an INTEGER primary key."
                )
            }
        }

        let normalizedCompositeIndexes = try normalizeCompositeIndexes(
            modelType.compositeIndexes,
            columns: columns,
            modelType: modelType
        )

        let schema = TFYSwiftModelSchema(
            modelName: String(describing: modelType),
            tableName: modelType.tableName,
            databaseName: modelType.databaseName,
            migrationPolicy: modelType.migrationPolicy,
            columns: columns,
            compositeIndexes: normalizedCompositeIndexes
        )
        let indexes = TFYSwiftIndexBuilder.expectedIndexes(for: schema)
        for index in indexes {
            try validateIdentifier(index.name, kind: "index", modelType: modelType)
        }
        let duplicateIndexNames = Dictionary(grouping: indexes, by: \.name).filter { $0.value.count > 1 }.keys.sorted()
        guard duplicateIndexNames.isEmpty else {
            throw TFYSwiftDBError.invalidModel(
                "\(String(describing: modelType)) declares duplicate index names: \(duplicateIndexNames.joined(separator: ", "))."
            )
        }
        return schema
    }

    public static func resolveColumnName<Model: TFYSwiftDBModel>(forDeclaredField fieldName: String, in modelType: Model.Type) throws -> String {
        let schema = try schema(for: modelType)
        if let column = schema.column(forProperty: fieldName) ?? schema.column(named: fieldName) {
            return column.name
        }

        let availableFields = schema.persistedColumns
            .flatMap { column -> [String] in
                column.propertyName == column.name ? [column.name] : [column.propertyName, column.name]
            }
            .uniqued()
            .joined(separator: ", ")

        throw TFYSwiftDBError.invalidModel(
            "\(schema.modelName) field '\(fieldName)' does not match any persisted property or column on table '\(schema.tableName)'. Available fields: \(availableFields)"
        )
    }

    public static func propertyValueMap<Model: TFYSwiftDBModel>(from model: Model) throws -> [String: Any] {
        let mirror = Mirror(reflecting: model)
        var map: [String: Any] = [:]

        for child in mirror.children {
            guard let label = child.label else { continue }
            let parsed = try parse(label: label, value: child.value)
            map[parsed.propertyName] = parsed.rawValue
        }
        return map
    }

    private static func parse(label: String, value: Any) throws -> (propertyName: String, annotation: TFYColumnAnnotation, rawValue: Any, valueType: Any.Type) {
        var propertyName = label.hasPrefix("_") ? String(label.dropFirst()) : label
        var annotation = TFYColumnAnnotation()
        var currentValue = value
        var currentType: Any.Type = type(of: value)

        while let wrapper = currentValue as? any TFYAnyColumnWrapper {
            wrapper.tfyApplyMetadata(to: &annotation)
            currentType = wrapper.tfyWrappedType
            currentValue = wrapper.tfyWrappedValueAny
        }

        if let nameOverride = annotation.nameOverride, !nameOverride.isEmpty {
            propertyName = nameOverride
        }

        return (label.hasPrefix("_") ? String(label.dropFirst()) : propertyName, annotation, currentValue, currentType)
    }

    private static func normalizeCompositeIndexes<Model: TFYSwiftDBModel>(
        _ indexes: [TFYCompositeIndex],
        columns: [TFYSwiftColumn],
        modelType: Model.Type
    ) throws -> [TFYCompositeIndex] {
        try indexes.enumerated().map { indexOffset, index in
            guard !index.columns.isEmpty else {
                throw TFYSwiftDBError.invalidModel(
                    "\(String(describing: modelType)) declares composite index #\(indexOffset + 1) with no columns."
                )
            }

            let normalizedColumns = try index.columns.map { declaredColumn in
                if let column = columns.first(where: { $0.propertyName == declaredColumn || $0.name == declaredColumn }) {
                    return column.name
                }

                let availableColumns = columns
                    .flatMap { column -> [String] in
                        column.propertyName == column.name ? [column.name] : [column.propertyName, column.name]
                    }
                    .uniqued()
                    .joined(separator: ", ")

                throw TFYSwiftDBError.invalidModel(
                    "\(String(describing: modelType)) declares composite index column '\(declaredColumn)' that does not exist on table '\(modelType.tableName)'. Available fields: \(availableColumns)"
                )
            }

            return TFYCompositeIndex(columns: normalizedColumns, unique: index.unique, name: index.name)
        }
    }

    private static func validateIdentifier<Model>(_ value: String, kind: String, modelType: Model.Type) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw TFYSwiftDBError.invalidModel(
                "\(String(describing: modelType)) declares an empty or invalid \(kind) identifier."
            )
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
