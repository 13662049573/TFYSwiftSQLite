import Foundation

public struct TFYSwiftBenchmarkReport {
    public let name: String
    public let iterations: Int
    public let batchSize: Int
    public let elapsed: TimeInterval
    public let operationsPerSecond: Double

    public init(
        name: String,
        iterations: Int,
        batchSize: Int,
        elapsed: TimeInterval
    ) {
        self.name = name
        self.iterations = iterations
        self.batchSize = batchSize
        self.elapsed = elapsed
        let operations = Double(iterations * max(batchSize, 1))
        self.operationsPerSecond = elapsed > 0 ? operations / elapsed : operations
    }
}

public enum TFYSwiftBenchmark {
    public static func measure(
        name: String,
        iterations: Int,
        batchSize: Int = 1,
        block: (Int) throws -> Void
    ) rethrows -> TFYSwiftBenchmarkReport {
        let start = CFAbsoluteTimeGetCurrent()
        for index in 0..<iterations {
            try block(index)
        }
        return TFYSwiftBenchmarkReport(
            name: name,
            iterations: iterations,
            batchSize: batchSize,
            elapsed: CFAbsoluteTimeGetCurrent() - start
        )
    }

    public static func write<Model: TFYSwiftDBModel>(
        _ modelType: Model.Type,
        name: String = "write",
        iterations: Int,
        batchSize: Int,
        makeModel: (Int) -> Model
    ) throws -> TFYSwiftBenchmarkReport {
        guard iterations > 0 else {
            throw TFYSwiftDBError.invalidQuery("Benchmark iterations must be greater than zero.")
        }
        guard batchSize > 0 else {
            throw TFYSwiftDBError.invalidQuery("Benchmark batchSize must be greater than zero.")
        }

        return try measure(name: name, iterations: iterations, batchSize: batchSize) { iteration in
            let startIndex = iteration * batchSize
            let models = (0..<batchSize).map { makeModel(startIndex + $0) }
            try modelType.insert(models)
        }
    }

    public static func read<Model: TFYSwiftDBModel>(
        _ modelType: Model.Type,
        name: String = "read",
        iterations: Int,
        query: TFYQuery<Model> = TFYQuery()
    ) throws -> TFYSwiftBenchmarkReport {
        guard iterations > 0 else {
            throw TFYSwiftDBError.invalidQuery("Benchmark iterations must be greater than zero.")
        }

        return try measure(name: name, iterations: iterations) { _ in
            _ = try modelType.fetchAll(query)
        }
    }
}
