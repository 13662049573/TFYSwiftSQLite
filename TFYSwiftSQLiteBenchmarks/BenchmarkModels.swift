import Foundation
import TFYSwiftSQLiteKit

struct BenchmarkPayload: Codable, Equatable {
    var city: String = ""
    var zipCode: String = ""
}

struct BenchmarkEvent: TFYSwiftDBModel {
    @TFYPrimaryKey(autoIncrement: true)
    var id: Int = 0

    @TFYIndex
    var userID: Int = 0

    var message: String = ""

    @TFYColumn(storageStrategy: .json)
    var payload: BenchmarkPayload = BenchmarkPayload()

    static var tableName: String { "benchmark_event" }
    static var databaseName: String { "benchmark" }

    static let userIDField = field("userID", as: Int.self)
}

struct BenchmarkScenario {
    let name: String
    let batchSize: Int
    let iterations: Int
    let journalMode: String
    let synchronous: String
    let walAutoCheckpoint: Int
}
