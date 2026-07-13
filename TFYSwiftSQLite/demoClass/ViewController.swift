//
//  ViewController.swift
//  TFYSwiftSQLite
//
//  Created by admin on 4/17/26.
//

import UIKit
import TFYSwiftSQLiteKit

@MainActor
final class ViewController: UIViewController {
    private let textView = UITextView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "TFYSwiftSQLite Demo"
        view.backgroundColor = .systemBackground
        configureTextView()

        Task { [weak self] in
            let output = await Self.runDemo()
            await MainActor.run {
                self?.textView.text = output
            }
        }
    }

    private func configureTextView() {
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.alwaysBounceVertical = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.addSubview(textView)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])
    }

    private static func runDemo() async -> String {
        var lines: [String] = []
        var sqlTrace: [String] = []
        let center = TFYSwiftDatabaseCenter.shared

        do {
            TFYSwiftDBRuntime.setSQLLogger { event in
                let sql = event.sql.replacingOccurrences(of: "\n", with: " ")
                let summary = "[\(event.databaseName)] \(event.succeeded ? "OK" : "ERR") \(String(format: "%.3f", event.duration))s \(sql)"
                if sqlTrace.count < 12 {
                    sqlTrace.append(summary)
                }
            }
            center.closeAll()
            try center.removeDatabase(named: "demo_main")
            try center.removeDatabase(named: "channel")
            try center.removeDatabase(named: "audit")

            let defaultPath = try center.path(named: "demo_main")
            let channelPath = try center.path(named: "channel")
            let auditPath = try center.path(named: "audit")

            lines.append("TFYSwiftSQLiteKit Demo")
            lines.append("====================")
            lines.append("default db: \(defaultPath)")
            lines.append("channel db: \(channelPath)")
            lines.append("audit db: \(auditPath)")
            lines.append("")

            lines.append("1) Legacy schema bootstrap")
            let legacyReport = try LegacyUser.createTable()
            lines.append(contentsOf: legacyReport.formattedLines())
            lines.append("")

            let legacy = LegacyUser(id: 0, username: "legacy_user")
            try legacy.insert()
            lines.append("Inserted legacy row")
            lines.append("")

            lines.append("2) Upgrade to User model")
            let upgradeReport = try User.createTable()
            lines.append(contentsOf: upgradeReport.formattedLines())
            lines.append("")

            lines.append("3) Re-run migration for idempotency")
            let secondReport = try User.createTable()
            lines.append(contentsOf: secondReport.formattedLines())
            lines.append("")

            lines.append("4) CRUD + JSON storage")
            let alice = User(
                id: 0,
                username: "alice",
                email: "alice@example.com",
                nickname: "guest",
                age: 28,
                cacheOnlyField: "not persisted",
                address: DemoAddress(city: "Shanghai", zipCode: "200000")
            )
            try User.insert([
                alice,
                User(
                    id: 0,
                    username: "bruce",
                    email: "bruce@example.com",
                    nickname: "vip",
                    age: 35,
                    cacheOnlyField: "transient",
                    address: DemoAddress(city: "Shenzhen", zipCode: "518000")
                )
            ])

            guard var fetchedAlice = try User.fetchAll(where: "username = ?", bindings: [.text("alice")]).first else {
                throw TFYSwiftDBError.notFound("Expected to fetch inserted user.")
            }
            lines.append("Fetched user: \(fetchedAlice)")

            fetchedAlice.nickname = "vip"
            fetchedAlice.age = 29
            try fetchedAlice.update()
            let updated = try User.fetchAll(where: "email = ?", bindings: [.text("alice@example.com")])
            lines.append("Updated rows: \(updated)")
            lines.append("User count: \(try User.count(where: "\"email\" IS NOT NULL"))")
            lines.append("First page: \(try User.fetchPage(orderBy: "\"id\" ASC", limit: 1))")
            let typedQuery = User.query()
                .where((User.ageField >= 20) && User.usernameField.starts(with: "a"))
                .orderBy(User.ageField.descending())
                .limit(10)
            lines.append("Typed query: \(try User.fetchAll(typedQuery))")
            let generatedFieldQuery = User.query()
                .where((User.fields.age >= 20) && User.fields.username.starts(with: "b"))
                .orderBy(User.fields.age.descending())
            lines.append("Generated field query: \(try User.fetchAll(generatedFieldQuery))")
            lines.append("")

            lines.append("5) Unique index verification")
            do {
                let duplicate = User(
                    id: 0,
                    username: "alice_2",
                    email: "alice@example.com",
                    nickname: "dup",
                    age: 18,
                    cacheOnlyField: "dup",
                    address: DemoAddress(city: "Beijing", zipCode: "100000")
                )
                try duplicate.insert()
                lines.append("Unexpected: duplicate insert succeeded")
            } catch {
                lines.append("Duplicate insert blocked as expected: \(error)")
            }
            lines.append("")

            lines.append("6) Composite unique index + multi database")
            let orderReport = try Order.createTable()
            lines.append(contentsOf: orderReport.formattedLines())
            try Order.transaction {
                try Order.insert([
                    Order(id: 0, userID: 1, orderNo: "ORD-001", amount: 19.9),
                    Order(id: 0, userID: 1, orderNo: "ORD-002", amount: 8.8)
                ])
            }
            let orders = try Order.fetchAll()
            lines.append("Orders: \(orders)")
            do {
                let duplicateOrder = Order(id: 0, userID: 1, orderNo: "ORD-001", amount: 20.0)
                try duplicateOrder.insert()
                lines.append("Unexpected: duplicate order insert succeeded")
            } catch {
                lines.append("Composite unique blocked as expected: \(error)")
            }
            lines.append("")

            lines.append("7) Delete by primary key")
            if let aliceRecord = updated.first {
                try aliceRecord.delete()
            }
            lines.append("Users after delete: \(try User.fetchAll(where: "\"email\" IS NOT NULL"))")

            lines.append("")
            lines.append("8) Rebuild table migration")
            let legacyAuditReport = try LegacyAuditEvent.createTable()
            lines.append(contentsOf: legacyAuditReport.formattedLines())
            try LegacyAuditEvent(id: 0, city: "Wuhan", legacyFlag: 1).insert()
            let rebuildReport = try AuditEvent.createTable()
            lines.append(contentsOf: rebuildReport.formattedLines())
            lines.append("Audit rows after rebuild: \(try AuditEvent.fetchAll(AuditEvent.query().where(AuditEvent.messageField == "migrated")))")

            let mainConnection = try center.open(named: "demo_main")
            let journal = try mainConnection.query(
                "SELECT table_name, schema_signature FROM \(TFYSwiftSQL.escapeIdentifier(TFYSwiftSchemaMigrator.journalTableName)) ORDER BY table_name;"
            )
            lines.append("")
            lines.append("9) Migration journal")
            lines.append("Journal rows: \(journal)")
            lines.append("")
            lines.append("10) Benchmark")
            let benchmark = try TFYSwiftBenchmark.write(
                User.self,
                name: "bulk_user_insert",
                iterations: 4,
                batchSize: 25
            ) { index in
                User(
                    id: 0,
                    username: "bench_\(index)",
                    email: "bench_\(index)@example.com",
                    nickname: "load",
                    age: 18 + (index % 10),
                    cacheOnlyField: "",
                    address: DemoAddress(city: "Benchmark", zipCode: "999999")
                )
            }
            lines.append("Benchmark \(benchmark.name): \(benchmark.iterations * benchmark.batchSize) ops in \(String(format: "%.3f", benchmark.elapsed))s, \(Int(benchmark.operationsPerSecond)) ops/s")
            lines.append("")
            lines.append("11) SQL trace sample")
            lines.append(contentsOf: sqlTrace)
        } catch {
            lines.append("Demo failed: \(error)")
        }

        TFYSwiftDBRuntime.setSQLLogger(nil)

        let output = lines.joined(separator: "\n")
        print(output)
        return output
    }
}
