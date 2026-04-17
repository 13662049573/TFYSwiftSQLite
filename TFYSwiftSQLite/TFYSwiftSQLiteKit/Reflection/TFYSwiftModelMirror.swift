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

        return TFYSwiftModelSchema(
            modelName: String(describing: modelType),
            tableName: modelType.tableName,
            databaseName: modelType.databaseName,
            migrationPolicy: modelType.migrationPolicy,
            columns: columns,
            compositeIndexes: modelType.compositeIndexes
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
}
