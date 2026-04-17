import Foundation

public protocol TFYAnyOptional {
    var wrappedAny: Any? { get }
}

extension Optional: TFYAnyOptional {
    public var wrappedAny: Any? { self }
}

public struct TFYAnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    public init(_ value: any Encodable) {
        encodeClosure = value.encode(to:)
    }

    public func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}

public enum TFYSwiftSQL {
    public nonisolated static func escapeIdentifier(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    public nonisolated static func escapeStringLiteral(_ string: String) -> String {
        "'\(string.replacingOccurrences(of: "'", with: "''"))'"
    }
}

public enum TFYSwiftTypeMapper {
    public nonisolated static func isOptionalType(_ type: Any.Type) -> Bool {
        String(reflecting: type).hasPrefix("Swift.Optional<")
    }

    public nonisolated static func normalizedTypeName(from type: Any.Type) -> String {
        let reflected = String(reflecting: type)
        return unwrapOptionalTypeName(reflected)
            .replacingOccurrences(of: "Swift.", with: "")
    }

    public nonisolated static func sqliteType(for swiftType: Any.Type, storageStrategy: TFYStorageStrategy) throws -> String {
        if storageStrategy == .json {
            return "TEXT"
        }

        let typeName = unwrapOptionalTypeName(String(reflecting: swiftType))
        switch typeName {
        case "Swift.Int", "Swift.Int8", "Swift.Int16", "Swift.Int32", "Swift.Int64",
             "Swift.UInt", "Swift.UInt8", "Swift.UInt16", "Swift.UInt32", "Swift.UInt64",
             "Swift.Bool":
            return "INTEGER"
        case "Swift.Double", "Swift.Float":
            return "REAL"
        case "Swift.String":
            return "TEXT"
        case "FoundationEssentials.Data", "Foundation.Data":
            return "BLOB"
        case "FoundationEssentials.Date", "Foundation.Date":
            return "REAL"
        default:
            throw TFYSwiftDBError.unsupportedType("Unsupported SQLite mapping for Swift type \(typeName). Use storageStrategy: .json for Codable objects.")
        }
    }

    public nonisolated static func defaultSQL(for value: Any) -> String? {
        if let optional = value as? any TFYAnyOptional {
            guard let wrapped = optional.wrappedAny else { return "NULL" }
            return defaultSQL(for: wrapped)
        }

        switch value {
        case let string as String:
            return TFYSwiftSQL.escapeStringLiteral(string)
        case let bool as Bool:
            return bool ? "1" : "0"
        case let int as Int:
            return "\(int)"
        case let int as Int8:
            return "\(int)"
        case let int as Int16:
            return "\(int)"
        case let int as Int32:
            return "\(int)"
        case let int as Int64:
            return "\(int)"
        case let uint as UInt:
            return "\(uint)"
        case let uint as UInt8:
            return "\(uint)"
        case let uint as UInt16:
            return "\(uint)"
        case let uint as UInt32:
            return "\(uint)"
        case let uint as UInt64:
            return "\(uint)"
        case let double as Double:
            return "\(double)"
        case let float as Float:
            return "\(float)"
        default:
            return nil
        }
    }

    public nonisolated static func bindValue(for rawValue: Any, column: TFYSwiftColumn) throws -> TFYSQLiteBindValue {
        if let optional = rawValue as? any TFYAnyOptional {
            guard let wrapped = optional.wrappedAny else { return .null }
            return try bindValue(for: wrapped, column: column)
        }

        if column.storageStrategy == .json {
            guard let encodable = rawValue as? any Encodable else {
                throw TFYSwiftDBError.encoding("Column \(column.name) requires an Encodable value for JSON storage.")
            }
            let data = try JSONEncoder().encode(TFYAnyEncodable(encodable))
            guard let json = String(data: data, encoding: .utf8) else {
                throw TFYSwiftDBError.encoding("Failed to turn JSON data into UTF-8 string for column \(column.name).")
            }
            return .text(json)
        }

        switch rawValue {
        case let bool as Bool:
            return .integer(bool ? 1 : 0)
        case let int as Int:
            return .integer(Int64(int))
        case let int as Int8:
            return .integer(Int64(int))
        case let int as Int16:
            return .integer(Int64(int))
        case let int as Int32:
            return .integer(Int64(int))
        case let int as Int64:
            return .integer(int)
        case let uint as UInt:
            return .integer(Int64(uint))
        case let uint as UInt8:
            return .integer(Int64(uint))
        case let uint as UInt16:
            return .integer(Int64(uint))
        case let uint as UInt32:
            return .integer(Int64(uint))
        case let uint as UInt64:
            return .integer(Int64(uint))
        case let double as Double:
            return .double(double)
        case let float as Float:
            return .double(Double(float))
        case let string as String:
            return .text(string)
        case let data as Data:
            return .blob(data)
        case let date as Date:
            return .double(date.timeIntervalSinceReferenceDate)
        default:
            throw TFYSwiftDBError.unsupportedType("Column \(column.name) does not support value type \(type(of: rawValue)).")
        }
    }

    public nonisolated static func userBindValue(for rawValue: Any) throws -> TFYSQLiteBindValue {
        if let optional = rawValue as? any TFYAnyOptional {
            guard let wrapped = optional.wrappedAny else { return .null }
            return try userBindValue(for: wrapped)
        }

        switch rawValue {
        case let value as TFYSQLiteBindValue:
            return value
        case let bool as Bool:
            return .integer(bool ? 1 : 0)
        case let int as Int:
            return .integer(Int64(int))
        case let int as Int64:
            return .integer(int)
        case let double as Double:
            return .double(double)
        case let string as String:
            return .text(string)
        case let data as Data:
            return .blob(data)
        case let date as Date:
            return .double(date.timeIntervalSinceReferenceDate)
        default:
            throw TFYSwiftDBError.unsupportedType("Unsupported binding value \(type(of: rawValue)).")
        }
    }

    public static func jsonObject<Model: TFYSwiftDBModel>(from row: [String: TFYSQLiteValue], schema: TFYSwiftModelSchema, modelType: Model.Type) throws -> [String: Any] {
        let encoder = JSONEncoder()
        let defaultData = try encoder.encode(Model.init())
        guard let base = try JSONSerialization.jsonObject(with: defaultData) as? [String: Any] else {
            throw TFYSwiftDBError.decoding("Unable to create base JSON dictionary for \(schema.modelName).")
        }

        var object = base
        for column in schema.persistedColumns {
            guard let sqliteValue = row[column.name] else { continue }
            object[column.propertyName] = try jsonCompatibleValue(from: sqliteValue, column: column)
        }
        return object
    }

    public nonisolated static func jsonCompatibleValue(from sqliteValue: TFYSQLiteValue, column: TFYSwiftColumn) throws -> Any {
        if case .null = sqliteValue {
            return NSNull()
        }

        if column.storageStrategy == .json {
            let text: String
            switch sqliteValue {
            case let .text(value):
                text = value
            case .null:
                return NSNull()
            default:
                throw TFYSwiftDBError.decoding("JSON column \(column.name) expected TEXT storage.")
            }
            let data = Data(text.utf8)
            return try JSONSerialization.jsonObject(with: data)
        }

        let typeName = column.swiftType
        switch typeName {
        case "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64":
            return numericValue(from: sqliteValue)
        case "Bool":
            return numericValue(from: sqliteValue) != 0
        case "Double", "Float":
            return doubleValue(from: sqliteValue)
        case "String":
            return stringValue(from: sqliteValue)
        case "Data":
            return dataValue(from: sqliteValue).base64EncodedString()
        case "Date":
            return doubleValue(from: sqliteValue)
        default:
            throw TFYSwiftDBError.decoding("Unsupported decode type \(typeName) for column \(column.name).")
        }
    }

    public nonisolated static func unwrapAnyOptional(_ value: Any) -> Any? {
        if let optional = value as? any TFYAnyOptional {
            return optional.wrappedAny
        }
        return value
    }

    public nonisolated static func numericValue(from sqliteValue: TFYSQLiteValue) -> Int64 {
        switch sqliteValue {
        case let .integer(value):
            return value
        case let .double(value):
            return Int64(value)
        case let .text(value):
            return Int64(value) ?? 0
        case .blob, .null:
            return 0
        }
    }

    public nonisolated static func doubleValue(from sqliteValue: TFYSQLiteValue) -> Double {
        switch sqliteValue {
        case let .integer(value):
            return Double(value)
        case let .double(value):
            return value
        case let .text(value):
            return Double(value) ?? 0
        case .blob, .null:
            return 0
        }
    }

    public nonisolated static func stringValue(from sqliteValue: TFYSQLiteValue) -> String {
        switch sqliteValue {
        case let .text(value):
            return value
        case let .integer(value):
            return String(value)
        case let .double(value):
            return String(value)
        case let .blob(value):
            return String(decoding: value, as: UTF8.self)
        case .null:
            return ""
        }
    }

    public nonisolated static func dataValue(from sqliteValue: TFYSQLiteValue) -> Data {
        switch sqliteValue {
        case let .blob(data):
            return data
        case let .text(text):
            return Data(base64Encoded: text) ?? Data(text.utf8)
        case let .integer(value):
            return Data(String(value).utf8)
        case let .double(value):
            return Data(String(value).utf8)
        case .null:
            return Data()
        }
    }

    private nonisolated static func unwrapOptionalTypeName(_ name: String) -> String {
        guard name.hasPrefix("Swift.Optional<"), name.hasSuffix(">") else {
            return name
        }
        let start = name.index(name.startIndex, offsetBy: "Swift.Optional<".count)
        let end = name.index(before: name.endIndex)
        return String(name[start..<end])
    }
}
