import Foundation

public enum TFYSwiftModelMirror {
    public static func schema<Model: TFYSwiftDBModel>(for modelType: Model.Type) throws -> TFYSwiftModelSchema {
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
        if primaryKeys.count > 1 {
            throw TFYSwiftDBError.invalidModel("\(String(describing: modelType)) declares more than one primary key. v1 supports a single primary key.")
        }

        let normalizedCompositeIndexes = try normalizeCompositeIndexes(
            modelType.compositeIndexes,
            columns: columns,
            modelType: modelType
        )

        return TFYSwiftModelSchema(
            modelName: String(describing: modelType),
            tableName: modelType.tableName,
            databaseName: modelType.databaseName,
            migrationPolicy: modelType.migrationPolicy,
            columns: columns,
            compositeIndexes: normalizedCompositeIndexes
        )
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
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
