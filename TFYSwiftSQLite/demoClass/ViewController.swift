import UIKit

@MainActor
final class ViewController: UITableViewController {
    private let searchController = UISearchController(searchResultsController: nil)
    private var searchText = ""

    private var visibleSections: [DemoSection] {
        DemoSection.allCases.filter { !visibleItems(in: $0).isEmpty }
    }

    init() {
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigation()
        configureTableView()
        configureSearch()

        if ProcessInfo.processInfo.environment["DEMO_VERIFY"] == "1" {
            DispatchQueue.main.async {
                Self.runVerification()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        resizeTableHeaderIfNeeded()
    }

    // MARK: - Configuration

    private func configureNavigation() {
        title = "SQLiteKit 示例"
        navigationController?.navigationBar.prefersLargeTitles = true

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "全部运行",
            style: .done,
            target: self,
            action: #selector(runAllTapped)
        )

        let resetButton = UIBarButtonItem(
            image: UIImage(systemName: "trash"),
            style: .plain,
            target: self,
            action: #selector(resetTapped)
        )
        resetButton.accessibilityLabel = "重置演示数据库"
        navigationItem.leftBarButtonItem = resetButton
    }

    private func configureTableView() {
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "demo.cell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.keyboardDismissMode = .onDrag
        tableView.accessibilityIdentifier = "demo.catalog.table"
        tableView.tableHeaderView = DemoSummaryHeaderView(
            sectionCount: DemoSection.allCases.count,
            itemCount: DemoCatalog.runnableItemCount
        )
    }

    private func configureSearch() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "搜索功能、API 或示例"
        searchController.searchBar.accessibilityIdentifier = "demo.catalog.search"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    private func resizeTableHeaderIfNeeded() {
        guard let header = tableView.tableHeaderView else { return }
        let targetSize = CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height)
        let height = header.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        guard abs(header.frame.height - height) > 0.5 else { return }
        header.frame.size.height = height
        tableView.tableHeaderView = header
    }

    // MARK: - Data

    private func visibleItems(in section: DemoSection) -> [DemoItem] {
        let items = DemoCatalog.items(in: section)
        guard !searchText.isEmpty else { return items }
        return items.filter { item in
            [item.title, item.subtitle, item.section.title, item.section.summary]
                .contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private static func runVerification() {
        let started = CFAbsoluteTimeGetCurrent()
        let output: String
        do {
            output = try DemoCatalog.runAll()
        } catch {
            output = "VERIFY FAIL\n\(error)"
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - started
        let report = "耗时 \(String(format: "%.3f", elapsed)) 秒\n\(output)"
        print("==== DEMO VERIFY ====\n\(report)\n==== END VERIFY ====")

        guard let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else { return }
        do {
            try report.write(
                to: documentsURL.appendingPathComponent("demo_verify.txt"),
                atomically: true,
                encoding: .utf8
            )
        } catch {
            print("Unable to persist demo verification report: \(error)")
        }
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        visibleSections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visibleItems(in: visibleSections[section]).count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let demoSection = visibleSections[section]
        return "\(demoSection.numberedTitle)  ·  \(visibleItems(in: demoSection).count) 项"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        visibleSections[section].summary
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "demo.cell", for: indexPath)
        let section = visibleSections[indexPath.section]
        let item = visibleItems(in: section)[indexPath.row]

        var configuration = UIListContentConfiguration.subtitleCell()
        configuration.text = item.title
        configuration.textProperties.font = .preferredFont(forTextStyle: .body)
        configuration.textProperties.numberOfLines = 0
        configuration.secondaryText = item.subtitle
        configuration.secondaryTextProperties.color = .secondaryLabel
        configuration.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
        configuration.secondaryTextProperties.numberOfLines = 0
        configuration.image = UIImage(systemName: section.symbolName)
        configuration.imageProperties.tintColor = .systemIndigo
        configuration.imageProperties.maximumSize = CGSize(width: 28, height: 28)
        configuration.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 12,
            leading: 12,
            bottom: 12,
            trailing: 8
        )

        cell.contentConfiguration = configuration
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "demo.item.\(item.identifier)"
        cell.accessibilityHint = "打开并运行此示例"
        return cell
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let section = visibleSections[indexPath.section]
        showResult(for: visibleItems(in: section)[indexPath.row])
    }

    // MARK: - Actions

    @objc private func runAllTapped() {
        guard let runAllItem = DemoCatalog.items.first(where: \.isAggregate) else { return }
        showResult(for: runAllItem)
    }

    @objc private func resetTapped() {
        let alert = UIAlertController(
            title: "重置演示数据？",
            message: "将关闭连接并删除 Demo 创建的所有本地数据库。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "重置", style: .destructive) { [weak self] _ in
            self?.performReset()
        })
        present(alert, animated: true)
    }

    private func performReset() {
        do {
            try DemoCatalog.resetDatabases()
            presentAlert(title: "重置完成", message: "所有演示数据库均已删除。")
        } catch {
            presentAlert(title: "重置失败", message: error.localizedDescription)
        }
    }

    private func showResult(for item: DemoItem) {
        navigationController?.pushViewController(
            DemoResultViewController(item: item),
            animated: true
        )
    }

    private func presentAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

extension ViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchText = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        tableView.reloadData()
    }
}

@MainActor
private final class DemoSummaryHeaderView: UIView {
    private let cardView = UIView()
    private let iconView = UIImageView(image: UIImage(systemName: "cylinder.fill"))
    private let titleLabel = UILabel()
    private let versionLabel = UILabel()
    private let bodyLabel = UILabel()

    init(sectionCount: Int, itemCount: Int) {
        super.init(frame: .zero)
        configure(sectionCount: sectionCount, itemCount: itemCount)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure(sectionCount: Int, itemCount: Int) {
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16)

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = .secondarySystemGroupedBackground
        cardView.layer.cornerRadius = 18
        cardView.layer.cornerCurve = .continuous

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = .systemIndigo
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.text = "完整能力演示"
        titleLabel.numberOfLines = 0

        versionLabel.font = .preferredFont(forTextStyle: .caption1)
        versionLabel.adjustsFontForContentSizeCategory = true
        versionLabel.textColor = .systemIndigo
        versionLabel.text = "TFYSwiftSQLiteKit 1.0.6"

        bodyLabel.font = .preferredFont(forTextStyle: .subheadline)
        bodyLabel.adjustsFontForContentSizeCategory = true
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 0
        bodyLabel.text = "\(sectionCount) 个主题 · \(itemCount) 个可运行示例\n点击示例查看真实执行结果，也可搜索 API 或一次运行全部自检。"

        let textStack = UIStackView(arrangedSubviews: [titleLabel, versionLabel, bodyLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 4

        cardView.addSubview(iconView)
        cardView.addSubview(textStack)
        addSubview(cardView)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),

            iconView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 18),
            iconView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 20),
            iconView.widthAnchor.constraint(equalToConstant: 36),

            textStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),
            textStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16)
        ])

        isAccessibilityElement = true
        accessibilityLabel = "TFYSwiftSQLiteKit 1.0.6，\(sectionCount) 个主题，\(itemCount) 个示例"
    }
}
