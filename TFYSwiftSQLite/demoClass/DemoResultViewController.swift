import UIKit

@MainActor
final class DemoResultViewController: UIViewController {
    private let textView = UITextView()
    private let activity = UIActivityIndicatorView(style: .large)
    private let item: DemoItem

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
        view.backgroundColor = .systemBackground
        configureUI()
        runDemo()
    }

    private func configureUI() {
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.alwaysBounceVertical = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.text = "Running…"
        textView.accessibilityIdentifier = "demo.result.text"

        activity.translatesAutoresizingMaskIntoConstraints = false
        activity.hidesWhenStopped = true

        view.addSubview(textView)
        view.addSubview(activity)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            activity.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activity.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(runDemo)
        )
    }

    @objc private func runDemo() {
        activity.startAnimating()
        textView.text = "Running \(item.title)…"
        // Yield one runloop turn so the spinner can appear before sync SQLite work.
        DispatchQueue.main.async { [weak self] in
            self?.executeDemo()
        }
    }

    private func executeDemo() {
        let started = CFAbsoluteTimeGetCurrent()
        let output: String
        do {
            let body = try item.run()
            let elapsed = CFAbsoluteTimeGetCurrent() - started
            output = "\(item.subtitle)\n⏱ \(String(format: "%.3f", elapsed))s\n\n\(body)"
        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - started
            output = "\(item.subtitle)\n⏱ \(String(format: "%.3f", elapsed))s\n\nFAIL\n\(error)"
        }
        textView.text = output
        activity.stopAnimating()
        print("==== DEMO RESULT: \(item.title) ====\n\(output)\n==== END ====")
    }
}
