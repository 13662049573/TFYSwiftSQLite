import Foundation
import TFYSwiftSQLiteKit

private struct BenchmarkCLIOptions {
    let sampleRuns: Int
    let warmupRuns: Int
    let markdownOutputPath: String?
    let csvOutputPath: String?

    static func parse(arguments: [String]) throws -> BenchmarkCLIOptions {
        var sampleRuns = 5
        var warmupRuns = 1
        var markdownOutputPath: String?
        var csvOutputPath: String?
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--samples":
                index += 1
                sampleRuns = try parsePositiveInt(arguments, index: index, flag: argument)
            case "--warmup-runs":
                index += 1
                warmupRuns = try parseNonNegativeInt(arguments, index: index, flag: argument)
            case "--markdown-output":
                index += 1
                markdownOutputPath = try parseString(arguments, index: index, flag: argument)
            case "--csv-output":
                index += 1
                csvOutputPath = try parseString(arguments, index: index, flag: argument)
            case "--help":
                printUsage()
                exit(0)
            default:
                throw BenchmarkCLIError.invalidArgument("Unknown argument '\(argument)'.")
            }
            index += 1
        }

        return BenchmarkCLIOptions(
            sampleRuns: sampleRuns,
            warmupRuns: warmupRuns,
            markdownOutputPath: markdownOutputPath,
            csvOutputPath: csvOutputPath
        )
    }

    private static func parsePositiveInt(_ arguments: [String], index: Int, flag: String) throws -> Int {
        let value = try parseNonNegativeInt(arguments, index: index, flag: flag)
        guard value > 0 else {
            throw BenchmarkCLIError.invalidArgument("\(flag) must be greater than zero.")
        }
        return value
    }

    private static func parseNonNegativeInt(_ arguments: [String], index: Int, flag: String) throws -> Int {
        let rawValue = try parseString(arguments, index: index, flag: flag)
        guard let value = Int(rawValue) else {
            throw BenchmarkCLIError.invalidArgument("\(flag) expects an integer, got '\(rawValue)'.")
        }
        guard value >= 0 else {
            throw BenchmarkCLIError.invalidArgument("\(flag) must be greater than or equal to zero.")
        }
        return value
    }

    private static func parseString(_ arguments: [String], index: Int, flag: String) throws -> String {
        guard arguments.indices.contains(index) else {
            throw BenchmarkCLIError.invalidArgument("Missing value for \(flag).")
        }
        return arguments[index]
    }
}

private struct BenchmarkSampleStats {
    let samples: [Double]

    init(samples: [Double]) {
        self.samples = samples.sorted()
    }

    var count: Int { samples.count }

    var min: Double { samples.first ?? 0 }

    var max: Double { samples.last ?? 0 }

    var mean: Double {
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0, +) / Double(samples.count)
    }

    var median: Double {
        guard !samples.isEmpty else { return 0 }
        let middle = samples.count / 2
        if samples.count.isMultiple(of: 2) {
            return (samples[middle - 1] + samples[middle]) / 2
        }
        return samples[middle]
    }

    var standardDeviation: Double {
        guard samples.count > 1 else { return 0 }
        let average = mean
        let variance = samples
            .map { pow($0 - average, 2) }
            .reduce(0, +) / Double(samples.count - 1)
        return sqrt(variance)
    }
}

private struct BenchmarkScenarioSummary {
    let scenario: BenchmarkScenario
    let writeStats: BenchmarkSampleStats
    let readStats: BenchmarkSampleStats
}

private enum BenchmarkCLIError: Error, CustomStringConvertible {
    case invalidArgument(String)

    var description: String {
        switch self {
        case let .invalidArgument(message):
            return message
        }
    }
}

private func configureDatabase(for scenario: BenchmarkScenario) throws {
    let center = TFYSwiftDatabaseCenter.shared
    center.close(named: BenchmarkEvent.databaseName)
    try center.removeDatabase(named: BenchmarkEvent.databaseName)
    let connection = try center.open(named: BenchmarkEvent.databaseName)
    try connection.execute("PRAGMA journal_mode = \(scenario.journalMode);")
    try connection.execute("PRAGMA synchronous = \(scenario.synchronous);")
    try connection.execute("PRAGMA wal_autocheckpoint = \(scenario.walAutoCheckpoint);")
    _ = try BenchmarkEvent.createTable()
}

private func makeScenarioReport(_ scenario: BenchmarkScenario) throws -> (write: TFYSwiftBenchmarkReport, read: TFYSwiftBenchmarkReport) {
    try configureDatabase(for: scenario)

    let writeReport = try TFYSwiftBenchmark.write(
        BenchmarkEvent.self,
        name: "\(scenario.name)-write",
        iterations: scenario.iterations,
        batchSize: scenario.batchSize
    ) { index in
        BenchmarkEvent(
            id: 0,
            userID: index % 97,
            message: "event_\(index)",
            payload: BenchmarkPayload(city: "City\(index % 11)", zipCode: String(format: "%06d", index))
        )
    }

    let readReport = try TFYSwiftBenchmark.read(
        BenchmarkEvent.self,
        name: "\(scenario.name)-read",
        iterations: 20,
        query: BenchmarkEvent.query()
            .where(BenchmarkEvent.userIDField >= 0)
            .orderBy(BenchmarkEvent.userIDField.descending())
            .limit(200)
    )

    return (writeReport, readReport)
}

private func sampleScenario(_ scenario: BenchmarkScenario, options: BenchmarkCLIOptions) throws -> BenchmarkScenarioSummary {
    for _ in 0..<options.warmupRuns {
        _ = try makeScenarioReport(scenario)
    }

    var writeSamples: [Double] = []
    var readSamples: [Double] = []
    for _ in 0..<options.sampleRuns {
        let report = try makeScenarioReport(scenario)
        writeSamples.append(report.write.operationsPerSecond)
        readSamples.append(report.read.operationsPerSecond)
    }

    return BenchmarkScenarioSummary(
        scenario: scenario,
        writeStats: BenchmarkSampleStats(samples: writeSamples),
        readStats: BenchmarkSampleStats(samples: readSamples)
    )
}

private func renderMarkdown(summaries: [BenchmarkScenarioSummary], options: BenchmarkCLIOptions) -> String {
    var lines: [String] = []
    lines.append("# TFYSwiftSQLite Benchmarks")
    lines.append("")
    lines.append("- Generated: \(ISO8601DateFormatter().string(from: Date()))")
    lines.append("- Warmup runs: \(options.warmupRuns)")
    lines.append("- Sample runs: \(options.sampleRuns)")
    lines.append("")
    lines.append("| Scenario | Journal | Sync | WAL Auto Checkpoint | Batch | Samples | Write Mean | Write Median | Write Min | Write Max | Write StdDev | Read Mean | Read Median | Read Min | Read Max | Read StdDev |")
    lines.append("| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")

    for summary in summaries {
        let scenario = summary.scenario
        lines.append(
            "| \(scenario.name) | \(scenario.journalMode) | \(scenario.synchronous) | \(scenario.walAutoCheckpoint) | \(scenario.batchSize) | \(summary.writeStats.count) | \(format(summary.writeStats.mean)) | \(format(summary.writeStats.median)) | \(format(summary.writeStats.min)) | \(format(summary.writeStats.max)) | \(format(summary.writeStats.standardDeviation)) | \(format(summary.readStats.mean)) | \(format(summary.readStats.median)) | \(format(summary.readStats.min)) | \(format(summary.readStats.max)) | \(format(summary.readStats.standardDeviation)) |"
        )
    }

    return lines.joined(separator: "\n")
}

private func renderCSV(summaries: [BenchmarkScenarioSummary]) -> String {
    let header = [
        "scenario",
        "journal_mode",
        "synchronous",
        "wal_auto_checkpoint",
        "batch_size",
        "samples",
        "write_mean_ops_per_sec",
        "write_median_ops_per_sec",
        "write_min_ops_per_sec",
        "write_max_ops_per_sec",
        "write_stddev_ops_per_sec",
        "read_mean_ops_per_sec",
        "read_median_ops_per_sec",
        "read_min_ops_per_sec",
        "read_max_ops_per_sec",
        "read_stddev_ops_per_sec"
    ]

    let rows = summaries.map { summary in
        [
            summary.scenario.name,
            summary.scenario.journalMode,
            summary.scenario.synchronous,
            String(summary.scenario.walAutoCheckpoint),
            String(summary.scenario.batchSize),
            String(summary.writeStats.count),
            format(summary.writeStats.mean),
            format(summary.writeStats.median),
            format(summary.writeStats.min),
            format(summary.writeStats.max),
            format(summary.writeStats.standardDeviation),
            format(summary.readStats.mean),
            format(summary.readStats.median),
            format(summary.readStats.min),
            format(summary.readStats.max),
            format(summary.readStats.standardDeviation)
        ]
    }

    return ([header] + rows)
        .map { $0.map(csvEscape).joined(separator: ",") }
        .joined(separator: "\n")
}

private func format(_ value: Double) -> String {
    String(format: "%.2f", value)
}

private func csvEscape(_ value: String) -> String {
    if value.contains(",") || value.contains("\"") || value.contains("\n") {
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    return value
}

private func writeOutput(_ content: String, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try content.write(to: url, atomically: true, encoding: .utf8)
}

private func printUsage() {
    print(
        """
        Usage: TFYSwiftSQLiteBenchmarks [--samples N] [--warmup-runs N] [--markdown-output PATH] [--csv-output PATH]

        --samples          Number of measured runs per scenario (default: 5)
        --warmup-runs      Number of warmup runs per scenario before sampling (default: 1)
        --markdown-output  Write the Markdown summary to PATH
        --csv-output       Write the CSV summary to PATH
        """
    )
}

let scenarios: [BenchmarkScenario] = [
    BenchmarkScenario(name: "wal-normal-b1", batchSize: 1, iterations: 300, journalMode: "WAL", synchronous: "NORMAL", walAutoCheckpoint: 1000),
    BenchmarkScenario(name: "wal-normal-b25", batchSize: 25, iterations: 80, journalMode: "WAL", synchronous: "NORMAL", walAutoCheckpoint: 1000),
    BenchmarkScenario(name: "wal-full-b25", batchSize: 25, iterations: 80, journalMode: "WAL", synchronous: "FULL", walAutoCheckpoint: 1000),
    BenchmarkScenario(name: "wal-normal-b25-c100", batchSize: 25, iterations: 80, journalMode: "WAL", synchronous: "NORMAL", walAutoCheckpoint: 100),
    BenchmarkScenario(name: "delete-full-b25", batchSize: 25, iterations: 80, journalMode: "DELETE", synchronous: "FULL", walAutoCheckpoint: 1000)
]

do {
    let options = try BenchmarkCLIOptions.parse(arguments: Array(CommandLine.arguments.dropFirst()))
    let summaries = try scenarios.map { try sampleScenario($0, options: options) }
    let markdown = renderMarkdown(summaries: summaries, options: options)
    let csv = renderCSV(summaries: summaries)

    print(markdown)

    if let markdownOutputPath = options.markdownOutputPath {
        try writeOutput(markdown + "\n", to: markdownOutputPath)
        print("\nMarkdown report saved to \(markdownOutputPath)")
    }
    if let csvOutputPath = options.csvOutputPath {
        try writeOutput(csv + "\n", to: csvOutputPath)
        print("CSV report saved to \(csvOutputPath)")
    }
} catch {
    fputs("Benchmark failed: \(error)\n", stderr)
    exit(1)
}
