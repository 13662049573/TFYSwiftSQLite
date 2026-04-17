import Foundation

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
}
