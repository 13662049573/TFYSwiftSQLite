import Foundation
import TFYSwiftSQLiteKit

struct DemoAddress: Codable, Equatable {
    var city: String = ""
    var zipCode: String = ""
}

struct LegacyUser: TFYSwiftDBModel {
    @TFYPrimaryKey(autoIncrement: true)
    var id: Int = 0

    var username: String = ""

    static var tableName: String { "user" }
    static var databaseName: String { "demo_main" }
}

struct User: TFYSwiftDBModel {
    @TFYPrimaryKey(autoIncrement: true)
    var id: Int = 0

    @TFYIndex
    var username: String = ""

    @TFYUnique
    var email: String = ""

    @TFYDefault("guest")
    var nickname: String = ""

    var age: Int = 0

    @TFYIgnore
    var cacheOnlyField: String = ""

    @TFYColumn(storageStrategy: .json)
    var address: DemoAddress = DemoAddress()

    static var tableName: String { "user" }
    static var databaseName: String { "demo_main" }

    static let usernameField = field("username", as: String.self)
    static let ageField = field("age", as: Int.self)
    static let emailField = field("email", as: String.self)
}

struct Order: TFYSwiftDBModel {
    @TFYPrimaryKey(autoIncrement: true)
    var id: Int = 0

    @TFYIndex
    var userID: Int = 0

    var orderNo: String = ""
    var amount: Double = 0

    static var databaseName: String { "channel" }

    static var compositeIndexes: [TFYCompositeIndex] {
        [
            TFYCompositeIndex(columns: ["userID", "orderNo"], unique: true)
        ]
    }

    static let userIDField = field("userID", as: Int.self)
    static let amountField = field("amount", as: Double.self)
}

struct LegacyAuditEvent: TFYSwiftDBModel {
    @TFYPrimaryKey(autoIncrement: true)
    var id: Int = 0

    var city: String = ""
    var legacyFlag: Int = 0

    static var tableName: String { "audit_event" }
    static var databaseName: String { "audit" }
}

struct AuditEvent: TFYSwiftDBModel {
    @TFYPrimaryKey(autoIncrement: true)
    var id: Int = 0

    @TFYDefault("migrated")
    var message: String = ""

    @TFYColumn(storageStrategy: .json)
    var payload: DemoAddress = DemoAddress()

    static var tableName: String { "audit_event" }
    static var databaseName: String { "audit" }
    static var migrationPolicy: TFYMigrationPolicy { .rebuildTable }

    static func renamedColumns(for schema: TFYSwiftModelSchema, existingColumns: [TFYSQLiteTableColumnInfo]) throws -> [String: String] {
        ["message": "city"]
    }

    static func rebuildExpressions(for schema: TFYSwiftModelSchema, existingColumns: [TFYSQLiteTableColumnInfo]) throws -> [String: String] {
        [
            "payload": """
            json_object('city', COALESCE("city", ''), 'zipCode', '000000')
            """,
            "message": TFYSwiftSQL.escapeStringLiteral("migrated")
        ]
    }

    static func validateRebuiltTable(using connection: TFYSwiftDBConnection, schema: TFYSwiftModelSchema, plan: TFYSwiftRebuildPlan) throws {
        let rows = try connection.query(
            "SELECT COUNT(*) AS count FROM \(TFYSwiftSQL.escapeIdentifier(plan.temporaryTableName)) WHERE \"message\" IS NULL OR \"payload\" IS NULL;"
        )
        let count = rows.first?["count"].map(TFYSwiftTypeMapper.numericValue(from:)) ?? 0
        if count > 0 {
            throw TFYSwiftDBError.migrationConflict("AuditEvent rebuild validation failed with \(count) invalid rows.")
        }
    }

    static let messageField = field("message", as: String.self)
}
