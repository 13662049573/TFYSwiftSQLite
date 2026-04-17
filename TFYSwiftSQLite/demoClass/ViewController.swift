//
//  ViewController.swift
//  TFYSwiftSQLite
//
//  Created by admin on 4/17/26.
//

import UIKit

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
        let center = TFYSwiftDatabaseCenter.shared

        do {
            center.closeAll()
            try center.removeDatabase(named: "demo_main")
            try center.removeDatabase(named: "channel")

            let defaultPath = try center.path(named: "demo_main")
            let channelPath = try center.path(named: "channel")

            lines.append("TFYSwiftSQLiteKit Demo")
            lines.append("====================")
            lines.append("default db: \(defaultPath)")
            lines.append("channel db: \(channelPath)")
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
            try alice.insert()

            guard var fetchedAlice = try User.fetchAll(where: "username = ?", bindings: [.text("alice")]).first else {
                throw TFYSwiftDBError.notFound("Expected to fetch inserted user.")
            }
            lines.append("Fetched user: \(fetchedAlice)")

            fetchedAlice.nickname = "vip"
            fetchedAlice.age = 29
            try fetchedAlice.update()
            let updated = try User.fetchAll(where: "email = ?", bindings: [.text("alice@example.com")])
            lines.append("Updated rows: \(updated)")
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
            let order = Order(id: 0, userID: 1, orderNo: "ORD-001", amount: 19.9)
            try order.insert()
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
        } catch {
            lines.append("Demo failed: \(error)")
        }

        let output = lines.joined(separator: "\n")
        print(output)
        return output
    }
}
