import UIKit
import TFYSwiftSQLiteKit

@MainActor
final class ViewController: UITableViewController {
    private let sections = DemoSection.allCases

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "TFYSwiftSQLite Demo"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 56
        tableView.accessibilityIdentifier = "demo.catalog.table"

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Run All",
            style: .done,
            target: self,
            action: #selector(runAllTapped)
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Reset DBs",
            style: .plain,
            target: self,
            action: #selector(resetTapped)
        )

        if ProcessInfo.processInfo.environment["DEMO_VERIFY"] == "1" {
            DispatchQueue.main.async {
                Self.runVerification()
            }
        }
    }

    private static func runVerification() {
        let started = CFAbsoluteTimeGetCurrent()
        let output: String
        do {
            output = try DemoCatalog.runAll(excludingTitles: ["Run All Demos"])
        } catch {
            output = "VERIFY FAIL\n\(error)"
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        let report = "⏱ \(String(format: "%.3f", elapsed))s\n\(output)"
        print("==== DEMO VERIFY ====\n\(report)\n==== END VERIFY ====")
        if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("demo_verify.txt") {
            try? report.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        DemoCatalog.items(in: sections[section]).count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let items = DemoCatalog.items(in: sections[section])
        return "\(sections[section].title) (\(items.count))"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let item = DemoCatalog.items(in: sections[indexPath.section])[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = item.title
        config.secondaryText = item.subtitle
        config.secondaryTextProperties.color = .secondaryLabel
        config.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "demo.item.\(indexPath.section).\(indexPath.row)"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = DemoCatalog.items(in: sections[indexPath.section])[indexPath.row]
        navigationController?.pushViewController(DemoResultViewController(item: item), animated: true)
    }

    @objc private func runAllTapped() {
        guard let runAll = DemoCatalog.items.first(where: { $0.title == "Run All Demos" }) else { return }
        navigationController?.pushViewController(DemoResultViewController(item: runAll), animated: true)
    }

    @objc private func resetTapped() {
        do {
            TFYSwiftDBRuntime.setSQLLogger(nil)
            TFYSwiftModelMirror.clearSchemaCache()
            let center = TFYSwiftDatabaseCenter.shared
            center.closeAll()
            for name in DemoCatalog.databaseNames {
                try? center.removeDatabase(named: name)
            }
            presentAlert(title: "Reset", message: "All demo databases removed.")
        }
    }

    private func presentAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
