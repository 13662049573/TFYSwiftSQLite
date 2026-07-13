import Foundation

public struct TFYColumnAnnotation {
    public var nameOverride: String?
    public var isPrimaryKey = false
    public var isAutoIncrement = false
    public var isIndexed = false
    public var isUnique = false
    public var defaultSQL: String?
    public var isIgnored = false
    public var storageStrategy: TFYStorageStrategy = .scalar
}

public protocol TFYAnyColumnWrapper {
    var tfyWrappedValueAny: Any { get }
    var tfyWrappedType: Any.Type { get }
    func tfyApplyMetadata(to metadata: inout TFYColumnAnnotation)
}

public protocol TFYSingleValueCodableWrapper {
    associatedtype Wrapped: Codable
    var wrappedValue: Wrapped { get set }
    init(wrappedValue: Wrapped)
}

public extension TFYSingleValueCodableWrapper {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(wrappedValue: try container.decode(Wrapped.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

@propertyWrapper
public struct TFYColumn<Wrapped> {
    public var wrappedValue: Wrapped
    public let name: String?
    public let primaryKey: Bool
    public let autoIncrement: Bool
    public let indexed: Bool
    public let unique: Bool
    public let defaultValueSQL: String?
    public let ignored: Bool
    public let storageStrategy: TFYStorageStrategy

    public init(
        wrappedValue: Wrapped,
        name: String? = nil,
        primaryKey: Bool = false,
        autoIncrement: Bool = false,
        indexed: Bool = false,
        unique: Bool = false,
        defaultValueSQL: String? = nil,
        ignored: Bool = false,
        storageStrategy: TFYStorageStrategy = .scalar
    ) {
        self.wrappedValue = wrappedValue
        self.name = name
        self.primaryKey = primaryKey
        self.autoIncrement = autoIncrement
        self.indexed = indexed
        self.unique = unique
        self.defaultValueSQL = defaultValueSQL
        self.ignored = ignored
        self.storageStrategy = storageStrategy
    }

    public init(wrappedValue: Wrapped) {
        self.init(
            wrappedValue: wrappedValue,
            name: nil,
            primaryKey: false,
            autoIncrement: false,
            indexed: false,
            unique: false,
            defaultValueSQL: nil,
            ignored: false,
            storageStrategy: .scalar
        )
    }
}

extension TFYColumn: TFYAnyColumnWrapper {
    public var tfyWrappedValueAny: Any { wrappedValue }
    public var tfyWrappedType: Any.Type { Wrapped.self }

    public func tfyApplyMetadata(to metadata: inout TFYColumnAnnotation) {
        metadata.nameOverride = name ?? metadata.nameOverride
        metadata.isPrimaryKey = metadata.isPrimaryKey || primaryKey
        metadata.isAutoIncrement = metadata.isAutoIncrement || autoIncrement
        metadata.isIndexed = metadata.isIndexed || indexed
        metadata.isUnique = metadata.isUnique || unique
        metadata.defaultSQL = defaultValueSQL ?? metadata.defaultSQL
        metadata.isIgnored = metadata.isIgnored || ignored
        metadata.storageStrategy = storageStrategy == .json ? .json : metadata.storageStrategy
    }
}

extension TFYColumn: TFYSingleValueCodableWrapper where Wrapped: Codable {}
extension TFYColumn: Codable where Wrapped: Codable {}
extension TFYColumn: Equatable where Wrapped: Equatable {}

@propertyWrapper
public struct TFYPrimaryKey<Wrapped> {
    public var wrappedValue: Wrapped
    public let autoIncrement: Bool

    public init(wrappedValue: Wrapped, autoIncrement: Bool = false) {
        self.wrappedValue = wrappedValue
        self.autoIncrement = autoIncrement
    }

    public init(wrappedValue: Wrapped) {
        self.init(wrappedValue: wrappedValue, autoIncrement: false)
    }
}

extension TFYPrimaryKey: TFYAnyColumnWrapper {
    public var tfyWrappedValueAny: Any { wrappedValue }
    public var tfyWrappedType: Any.Type { Wrapped.self }

    public func tfyApplyMetadata(to metadata: inout TFYColumnAnnotation) {
        metadata.isPrimaryKey = true
        metadata.isAutoIncrement = metadata.isAutoIncrement || autoIncrement
    }
}

extension TFYPrimaryKey: TFYSingleValueCodableWrapper where Wrapped: Codable {}
extension TFYPrimaryKey: Codable where Wrapped: Codable {}
extension TFYPrimaryKey: Equatable where Wrapped: Equatable {}

@propertyWrapper
public struct TFYIndex<Wrapped> {
    public var wrappedValue: Wrapped

    public init(wrappedValue: Wrapped) {
        self.wrappedValue = wrappedValue
    }
}

extension TFYIndex: TFYAnyColumnWrapper {
    public var tfyWrappedValueAny: Any { wrappedValue }
    public var tfyWrappedType: Any.Type { Wrapped.self }

    public func tfyApplyMetadata(to metadata: inout TFYColumnAnnotation) {
        metadata.isIndexed = true
    }
}

extension TFYIndex: TFYSingleValueCodableWrapper where Wrapped: Codable {}
extension TFYIndex: Codable where Wrapped: Codable {}
extension TFYIndex: Equatable where Wrapped: Equatable {}

@propertyWrapper
public struct TFYUnique<Wrapped> {
    public var wrappedValue: Wrapped

    public init(wrappedValue: Wrapped) {
        self.wrappedValue = wrappedValue
    }
}

extension TFYUnique: TFYAnyColumnWrapper {
    public var tfyWrappedValueAny: Any { wrappedValue }
    public var tfyWrappedType: Any.Type { Wrapped.self }

    public func tfyApplyMetadata(to metadata: inout TFYColumnAnnotation) {
        metadata.isUnique = true
    }
}

extension TFYUnique: TFYSingleValueCodableWrapper where Wrapped: Codable {}
extension TFYUnique: Codable where Wrapped: Codable {}
extension TFYUnique: Equatable where Wrapped: Equatable {}

@propertyWrapper
public struct TFYDefault<Wrapped> {
    public var wrappedValue: Wrapped
    public let defaultValueSQL: String?

    public init(wrappedValue: Wrapped) {
        self.wrappedValue = wrappedValue
        self.defaultValueSQL = nil
    }

    public init(wrappedValue: Wrapped, _ defaultValue: Wrapped) {
        self.wrappedValue = wrappedValue
        self.defaultValueSQL = TFYSwiftTypeMapper.defaultSQL(for: defaultValue)
    }
}

extension TFYDefault: TFYAnyColumnWrapper {
    public var tfyWrappedValueAny: Any { wrappedValue }
    public var tfyWrappedType: Any.Type { Wrapped.self }

    public func tfyApplyMetadata(to metadata: inout TFYColumnAnnotation) {
        metadata.defaultSQL = defaultValueSQL ?? metadata.defaultSQL
    }
}

extension TFYDefault: TFYSingleValueCodableWrapper where Wrapped: Codable {}
extension TFYDefault: Codable where Wrapped: Codable {}
extension TFYDefault: Equatable where Wrapped: Equatable {}

@propertyWrapper
public struct TFYIgnore<Wrapped> {
    public var wrappedValue: Wrapped

    public init(wrappedValue: Wrapped) {
        self.wrappedValue = wrappedValue
    }
}

extension TFYIgnore: TFYAnyColumnWrapper {
    public var tfyWrappedValueAny: Any { wrappedValue }
    public var tfyWrappedType: Any.Type { Wrapped.self }

    public func tfyApplyMetadata(to metadata: inout TFYColumnAnnotation) {
        metadata.isIgnored = true
    }
}

extension TFYIgnore: TFYSingleValueCodableWrapper where Wrapped: Codable {}
extension TFYIgnore: Codable where Wrapped: Codable {}
extension TFYIgnore: Equatable where Wrapped: Equatable {}
