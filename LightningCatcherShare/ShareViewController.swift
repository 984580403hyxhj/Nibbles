import UIKit
import Social
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    private let confirmLabel = UILabel()
    private let iconLabel = UILabel()
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        extractAndSaveURL()
    }

    // MARK: - UI

    private func setupUI() {
        view.backgroundColor = UIColor.systemBackground

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        iconLabel.text = "⚡"
        iconLabel.font = .systemFont(ofSize: 48)
        stack.addArrangedSubview(iconLabel)

        confirmLabel.text = "正在添加到阅栈..."
        confirmLabel.font = .systemFont(ofSize: 17, weight: .medium)
        confirmLabel.textColor = .label
        stack.addArrangedSubview(confirmLabel)

        statusLabel.text = ""
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textColor = .secondaryLabel
        stack.addArrangedSubview(statusLabel)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    // MARK: - Extract URL

    private func extractAndSaveURL() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            showError("无法获取分享内容")
            return
        }

        for item in extensionItems {
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                // Try URL first
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, error in
                        DispatchQueue.main.async {
                            if let url = item as? URL {
                                self?.saveURL(url.absoluteString)
                            } else if let urlData = item as? Data, let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                                self?.saveURL(url.absoluteString)
                            } else {
                                self?.showError("无法解析链接")
                            }
                        }
                    }
                    return
                }

                // Fallback: try plain text (might be a URL string)
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] item, error in
                        DispatchQueue.main.async {
                            if let text = item as? String, text.hasPrefix("http") {
                                self?.saveURL(text)
                            } else {
                                self?.showError("分享内容不是有效链接")
                            }
                        }
                    }
                    return
                }
            }
        }

        showError("未找到可分享的链接")
    }

    // MARK: - Save & Dismiss

    private func saveURL(_ urlString: String) {
        SharedStorage.enqueueURL(urlString)

        confirmLabel.text = "已添加到阅栈 ✓"
        statusLabel.text = "打开 App 即可查看"
        iconLabel.text = "✅"

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func showError(_ message: String) {
        confirmLabel.text = "添加失败"
        statusLabel.text = message
        iconLabel.text = "❌"

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.extensionContext?.cancelRequest(withError: NSError(domain: "LightningCatcherShare", code: 0))
        }
    }
}
