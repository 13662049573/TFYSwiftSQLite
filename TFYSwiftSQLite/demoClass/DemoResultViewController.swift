import UIKit

private struct DemoExecution {
    let isSuccess: Bool
    let elapsed: TimeInterval
    let output: String
}

@MainActor
final class DemoResultViewController: UIViewController {
    private static let executionQueue = DispatchQueue(
        label: "com.tfy.swift-sqlite.demo",
        qos: .userInitiated
    )

    private let item: DemoItem
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let summaryCard = UIView()
    private let statusIconView = UIImageView()
    private let statusLabel = UILabel()
    private let sectionLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let durationLabel = UILabel()
    private let outputTitleLabel = UILabel()
    private let outputTextView = UITextView()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private lazy var rerunButton = UIBarButtonItem(
        image: UIImage(systemName: "arrow.clockwise"),
        style: .plain,
        target: self,
        action: #selector(runDemo)
    )
    private lazy var copyButton = UIBarButtonItem(
        image: UIImage(systemName: "doc.on.doc"),
        style: .plain,
        target: self,
        action: #selector(copyOutput)
    )

    init(item: DemoItem) {
        self.item = item
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = item.title
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        configureNavigation()
        configureUI()
        runDemo()
    }

    // MARK: - Configuration

    private func configureNavigation() {
        rerunButton.accessibilityLabel = "重新运行"
        copyButton.accessibilityLabel = "复制运行结果"
        navigationItem.rightBarButtonItems = [rerunButton, copyButton]
        copyButton.isEnabled = false
    }

    private func configureUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .onDrag

        contentView.translatesAutoresizingMaskIntoConstraints = false

        summaryCard.translatesAutoresizingMaskIntoConstraints = false
        summaryCard.backgroundColor = .secondarySystemGroupedBackground
        summaryCard.layer.cornerRadius = 18
        summaryCard.layer.cornerCurve = .continuous

        statusIconView.translatesAutoresizingMaskIntoConstraints = false
        statusIconView.contentMode = .scaleAspectFit
        statusIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true

        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.numberOfLines = 0

        sectionLabel.font = .preferredFont(forTextStyle: .caption1)
        sectionLabel.adjustsFontForContentSizeCategory = true
        sectionLabel.textColor = .systemIndigo
        sectionLabel.text = item.section.numberedTitle

        descriptionLabel.font = .preferredFont(forTextStyle: .body)
        descriptionLabel.adjustsFontForContentSizeCategory = true
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.numberOfLines = 0
        descriptionLabel.text = item.subtitle

        durationLabel.font = .preferredFont(forTextStyle: .caption1)
        durationLabel.adjustsFontForContentSizeCategory = true
        durationLabel.textColor = .tertiaryLabel
        durationLabel.numberOfLines = 0

        outputTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        outputTitleLabel.font = .preferredFont(forTextStyle: .headline)
        outputTitleLabel.adjustsFontForContentSizeCategory = true
        outputTitleLabel.text = "运行输出"

        outputTextView.translatesAutoresizingMaskIntoConstraints = false
        outputTextView.isEditable = false
        outputTextView.isScrollEnabled = false
        outputTextView.backgroundColor = .secondarySystemGroupedBackground
        outputTextView.layer.cornerRadius = 16
        outputTextView.layer.cornerCurve = .continuous
        outputTextView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        outputTextView.adjustsFontForContentSizeCategory = true
        outputTextView.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .monospacedSystemFont(ofSize: 13, weight: .regular)
        )
        outputTextView.textColor = .label
        outputTextView.accessibilityIdentifier = "demo.result.text"

        let textStack = UIStackView(arrangedSubviews: [
            statusLabel,
            sectionLabel,
            descriptionLabel,
            durationLabel
        ])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 5

        summaryCard.addSubview(statusIconView)
        summaryCard.addSubview(activityIndicator)
        summaryCard.addSubview(textStack)
        contentView.addSubview(summaryCard)
        contentView.addSubview(outputTitleLabel)
        contentView.addSubview(outputTextView)
        scrollView.addSubview(contentView)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            summaryCard.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            summaryCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            summaryCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            statusIconView.leadingAnchor.constraint(equalTo: summaryCard.leadingAnchor, constant: 18),
            statusIconView.topAnchor.constraint(equalTo: summaryCard.topAnchor, constant: 20),
            statusIconView.widthAnchor.constraint(equalToConstant: 34),
            statusIconView.heightAnchor.constraint(equalToConstant: 34),

            activityIndicator.centerXAnchor.constraint(equalTo: statusIconView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: statusIconView.centerYAnchor),

            textStack.topAnchor.constraint(equalTo: summaryCard.topAnchor, constant: 16),
            textStack.leadingAnchor.constraint(equalTo: statusIconView.trailingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(equalTo: summaryCard.trailingAnchor, constant: -18),
            textStack.bottomAnchor.constraint(equalTo: summaryCard.bottomAnchor, constant: -16),

            outputTitleLabel.topAnchor.constraint(equalTo: summaryCard.bottomAnchor, constant: 24),
            outputTitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            outputTitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            outputTextView.topAnchor.constraint(equalTo: outputTitleLabel.bottomAnchor, constant: 10),
            outputTextView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            outputTextView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            outputTextView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24),
            outputTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 220)
        ])
    }

    // MARK: - Execution

    @objc private func runDemo() {
        setRunningState()
        let item = item

        Self.executionQueue.async { [weak self] in
            let started = CFAbsoluteTimeGetCurrent()
            let execution: DemoExecution
            do {
                let output = try item.run()
                execution = DemoExecution(
                    isSuccess: true,
                    elapsed: CFAbsoluteTimeGetCurrent() - started,
                    output: output
                )
            } catch {
                execution = DemoExecution(
                    isSuccess: false,
                    elapsed: CFAbsoluteTimeGetCurrent() - started,
                    output: String(describing: error)
                )
            }

            DispatchQueue.main.async {
                self?.show(execution)
            }
        }
    }

    private func setRunningState() {
        rerunButton.isEnabled = false
        copyButton.isEnabled = false
        statusIconView.image = nil
        activityIndicator.startAnimating()
        statusLabel.text = "正在运行"
        statusLabel.textColor = .label
        durationLabel.text = "正在执行真实 SQLite 操作…"
        outputTextView.text = "请稍候。"
        outputTextView.textColor = .secondaryLabel
        view.accessibilityValue = "正在运行"
    }

    private func show(_ execution: DemoExecution) {
        activityIndicator.stopAnimating()
        rerunButton.isEnabled = true
        copyButton.isEnabled = true

        let symbolName = execution.isSuccess ? "checkmark.circle.fill" : "xmark.octagon.fill"
        let color: UIColor = execution.isSuccess ? .systemGreen : .systemRed
        statusIconView.image = UIImage(systemName: symbolName)
        statusIconView.tintColor = color
        statusLabel.text = execution.isSuccess ? "运行成功" : "运行失败"
        statusLabel.textColor = color
        durationLabel.text = "耗时 \(String(format: "%.3f", execution.elapsed)) 秒"
        outputTextView.text = execution.output
        outputTextView.textColor = .label

        let announcement = "\(statusLabel.text ?? "")，\(durationLabel.text ?? "")"
        UIAccessibility.post(notification: .announcement, argument: announcement)
        print("[Demo] \(item.title): \(announcement)\n\(execution.output)")
    }

    // MARK: - Actions

    @objc private func copyOutput() {
        UIPasteboard.general.string = [
            item.title,
            item.subtitle,
            durationLabel.text ?? "",
            outputTextView.text ?? ""
        ].joined(separator: "\n")

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        navigationItem.prompt = "结果已复制"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.navigationItem.prompt = nil
        }
    }
}
