import Foundation

@dynamicMemberLookup
public struct TFYFields<Model: TFYSwiftDBModel> {
    public init() {}

    public subscript(dynamicMember member: String) -> TFYAnyField<Model> {
        switch Model.resolveFieldReference(member) {
        case let .success(columnName):
            return TFYAnyField(name: columnName)
        case let .failure(error):
            return TFYAnyField(name: member, validationError: error)
        }
    }
}

public struct TFYAnyField<Model> {
    public let name: String
    fileprivate let validationError: TFYSwiftDBError?

    public init(name: String, validationError: TFYSwiftDBError? = nil) {
        self.name = name
        self.validationError = validationError
    }

    fileprivate var escapedName: String {
        TFYSwiftSQL.escapeIdentifier(name)
    }
}

public struct TFYField<Model, Value> {
    public let name: String
    fileprivate let validationError: TFYSwiftDBError?

    public init(name: String, validationError: TFYSwiftDBError? = nil) {
        self.name = name
        self.validationError = validationError
    }

    fileprivate var escapedName: String {
        TFYSwiftSQL.escapeIdentifier(name)
    }
}

public struct TFYSort<Model> {
    fileprivate let sql: String
    fileprivate let validationError: TFYSwiftDBError?
}

public struct TFYPredicate<Model> {
    fileprivate let sql: String
    fileprivate let bindings: [TFYSQLiteBindValue?]
    fileprivate let validationError: TFYSwiftDBError?

    public init(sql: String, bindings: [TFYSQLiteBindValue?] = []) {
        self.init(sql: sql, bindings: bindings, validationError: nil)
    }

    fileprivate init(sql: String, bindings: [TFYSQLiteBindValue?] = [], validationError: TFYSwiftDBError?) {
        self.sql = sql
        self.bindings = bindings
        self.validationError = validationError
    }

    public func and(_ other: TFYPredicate<Model>) -> TFYPredicate<Model> {
        TFYPredicate<Model>(
            sql: "(\(sql)) AND (\(other.sql))",
            bindings: bindings + other.bindings,
            validationError: combineValidationErrors(validationError, other.validationError)
        )
    }

    public func or(_ other: TFYPredicate<Model>) -> TFYPredicate<Model> {
        TFYPredicate<Model>(
            sql: "(\(sql)) OR (\(other.sql))",
            bindings: bindings + other.bindings,
            validationError: combineValidationErrors(validationError, other.validationError)
        )
    }

    public func not() -> TFYPredicate<Model> {
        TFYPredicate<Model>(sql: "NOT (\(sql))", bindings: bindings, validationError: validationError)
    }
}

public struct TFYQuery<Model: TFYSwiftDBModel> {
    fileprivate var predicate: TFYPredicate<Model>?
    fileprivate var sorts: [TFYSort<Model>] = []
    fileprivate var limitValue: Int?
    fileprivate var offsetValue: Int?

    public init() {}

    public func `where`(_ predicate: TFYPredicate<Model>) -> TFYQuery<Model> {
        var copy = self
        copy.predicate = predicate
        return copy
    }

    public func orderBy(_ sort: TFYSort<Model>, _ remaining: TFYSort<Model>...) -> TFYQuery<Model> {
        var copy = self
        copy.sorts = [sort] + remaining
        return copy
    }

    public func limit(_ value: Int, offset: Int? = nil) -> TFYQuery<Model> {
        var copy = self
        copy.limitValue = value
        if let offset {
            copy.offsetValue = offset
        }
        return copy
    }

    func render() throws -> (clause: String?, bindings: [TFYSQLiteBindValue?]) {
        if let limitValue, limitValue <= 0 {
            throw TFYSwiftDBError.invalidQuery("Query limit must be greater than zero.")
        }
        if let offsetValue, offsetValue < 0 {
            throw TFYSwiftDBError.invalidQuery("Query offset must be greater than or equal to zero.")
        }
        if let validationError = predicate?.validationError {
            throw validationError
        }
        if let validationError = sorts.compactMap(\.validationError).first {
            throw validationError
        }

        var parts: [String] = []
        var allBindings: [TFYSQLiteBindValue?] = []

        if let predicate {
            parts.append("WHERE \(predicate.sql)")
            allBindings.append(contentsOf: predicate.bindings)
        }
        if !sorts.isEmpty {
            parts.append("ORDER BY \(sorts.map(\.sql).joined(separator: ", "))")
        }
        if let limitValue {
            parts.append("LIMIT \(limitValue)")
            if let offsetValue {
                parts.append("OFFSET \(offsetValue)")
            }
        }

        guard !parts.isEmpty else { return (nil, allBindings) }
        return (parts.joined(separator: " "), allBindings)
    }
}

public extension TFYField {
    func ascending() -> TFYSort<Model> {
        TFYSort(sql: "\(escapedName) ASC", validationError: validationError)
    }

    func descending() -> TFYSort<Model> {
        TFYSort(sql: "\(escapedName) DESC", validationError: validationError)
    }

    func isNull() -> TFYPredicate<Model> {
        TFYPredicate(sql: "\(escapedName) IS NULL", validationError: validationError)
    }

    func isNotNull() -> TFYPredicate<Model> {
        TFYPredicate(sql: "\(escapedName) IS NOT NULL", validationError: validationError)
    }

    func `in`(_ values: [Value]) throws -> TFYPredicate<Model> {
        if let validationError {
            throw validationError
        }
        guard !values.isEmpty else {
            throw TFYSwiftDBError.invalidQuery("IN predicate requires at least one value.")
        }
        let placeholders = Array(repeating: "?", count: values.count).joined(separator: ", ")
        return TFYPredicate(
            sql: "\(escapedName) IN (\(placeholders))",
            bindings: try values.map(TFYSwiftTypeMapper.userBindValue(for:))
        )
    }
}

public extension TFYAnyField {
    func ascending() -> TFYSort<Model> {
        TFYSort(sql: "\(escapedName) ASC", validationError: validationError)
    }

    func descending() -> TFYSort<Model> {
        TFYSort(sql: "\(escapedName) DESC", validationError: validationError)
    }

    func isNull() -> TFYPredicate<Model> {
        TFYPredicate(sql: "\(escapedName) IS NULL", validationError: validationError)
    }

    func isNotNull() -> TFYPredicate<Model> {
        TFYPredicate(sql: "\(escapedName) IS NOT NULL", validationError: validationError)
    }

    func `in`(_ values: [Any]) throws -> TFYPredicate<Model> {
        if let validationError {
            throw validationError
        }
        guard !values.isEmpty else {
            throw TFYSwiftDBError.invalidQuery("IN predicate requires at least one value.")
        }
        let placeholders = Array(repeating: "?", count: values.count).joined(separator: ", ")
        return TFYPredicate(
            sql: "\(escapedName) IN (\(placeholders))",
            bindings: try values.map(TFYSwiftTypeMapper.userBindValue(for:))
        )
    }

    func like(_ pattern: String) -> TFYPredicate<Model> {
        TFYPredicate(sql: "\(escapedName) LIKE ?", bindings: [.text(pattern)], validationError: validationError)
    }

    func contains(_ value: String) -> TFYPredicate<Model> {
        like("%\(value)%")
    }

    func starts(with value: String) -> TFYPredicate<Model> {
        like("\(value)%")
    }
}

public extension TFYField where Value == String {
    func like(_ pattern: String) -> TFYPredicate<Model> {
        TFYPredicate(sql: "\(escapedName) LIKE ?", bindings: [.text(pattern)], validationError: validationError)
    }

    func contains(_ value: String) -> TFYPredicate<Model> {
        like("%\(value)%")
    }

    func starts(with value: String) -> TFYPredicate<Model> {
        like("\(value)%")
    }
}

public func == <Model, Value>(lhs: TFYField<Model, Value>, rhs: Value) -> TFYPredicate<Model> {
    comparisonPredicate(lhs, "=", rhs)
}

public func == <Model>(lhs: TFYAnyField<Model>, rhs: Any) -> TFYPredicate<Model> {
    anyComparisonPredicate(lhs, "=", rhs)
}

public func != <Model, Value>(lhs: TFYField<Model, Value>, rhs: Value) -> TFYPredicate<Model> {
    comparisonPredicate(lhs, "!=", rhs)
}

public func != <Model>(lhs: TFYAnyField<Model>, rhs: Any) -> TFYPredicate<Model> {
    anyComparisonPredicate(lhs, "!=", rhs)
}

public func > <Model, Value>(lhs: TFYField<Model, Value>, rhs: Value) -> TFYPredicate<Model> {
    comparisonPredicate(lhs, ">", rhs)
}

public func > <Model>(lhs: TFYAnyField<Model>, rhs: Any) -> TFYPredicate<Model> {
    anyComparisonPredicate(lhs, ">", rhs)
}

public func >= <Model, Value>(lhs: TFYField<Model, Value>, rhs: Value) -> TFYPredicate<Model> {
    comparisonPredicate(lhs, ">=", rhs)
}

public func >= <Model>(lhs: TFYAnyField<Model>, rhs: Any) -> TFYPredicate<Model> {
    anyComparisonPredicate(lhs, ">=", rhs)
}

public func < <Model, Value>(lhs: TFYField<Model, Value>, rhs: Value) -> TFYPredicate<Model> {
    comparisonPredicate(lhs, "<", rhs)
}

public func < <Model>(lhs: TFYAnyField<Model>, rhs: Any) -> TFYPredicate<Model> {
    anyComparisonPredicate(lhs, "<", rhs)
}

public func <= <Model, Value>(lhs: TFYField<Model, Value>, rhs: Value) -> TFYPredicate<Model> {
    comparisonPredicate(lhs, "<=", rhs)
}

public func <= <Model>(lhs: TFYAnyField<Model>, rhs: Any) -> TFYPredicate<Model> {
    anyComparisonPredicate(lhs, "<=", rhs)
}

public func && <Model>(lhs: TFYPredicate<Model>, rhs: TFYPredicate<Model>) -> TFYPredicate<Model> {
    lhs.and(rhs)
}

public func || <Model>(lhs: TFYPredicate<Model>, rhs: TFYPredicate<Model>) -> TFYPredicate<Model> {
    lhs.or(rhs)
}

prefix public func ! <Model>(predicate: TFYPredicate<Model>) -> TFYPredicate<Model> {
    predicate.not()
}

private func comparisonPredicate<Model, Value>(_ field: TFYField<Model, Value>, _ op: String, _ value: Value) -> TFYPredicate<Model> {
    if let validationError = field.validationError {
        return TFYPredicate(sql: "1 = 0", validationError: validationError)
    }
    do {
        return TFYPredicate(
            sql: "\(field.escapedName) \(op) ?",
            bindings: [try TFYSwiftTypeMapper.userBindValue(for: value)]
        )
    } catch let error as TFYSwiftDBError {
        return TFYPredicate(sql: "1 = 0", validationError: error)
    } catch {
        return TFYPredicate(
            sql: "1 = 0",
            validationError: TFYSwiftDBError.invalidQuery("Failed to bind value for field '\(field.name)': \(error)")
        )
    }
}

private func anyComparisonPredicate<Model>(_ field: TFYAnyField<Model>, _ op: String, _ value: Any) -> TFYPredicate<Model> {
    if let validationError = field.validationError {
        return TFYPredicate(sql: "1 = 0", validationError: validationError)
    }
    do {
        return TFYPredicate(
            sql: "\(field.escapedName) \(op) ?",
            bindings: [try TFYSwiftTypeMapper.userBindValue(for: value)]
        )
    } catch let error as TFYSwiftDBError {
        return TFYPredicate(sql: "1 = 0", validationError: error)
    } catch {
        return TFYPredicate(
            sql: "1 = 0",
            validationError: TFYSwiftDBError.invalidQuery("Failed to bind value for field '\(field.name)': \(error)")
        )
    }
}

private func combineValidationErrors(_ lhs: TFYSwiftDBError?, _ rhs: TFYSwiftDBError?) -> TFYSwiftDBError? {
    lhs ?? rhs
}
