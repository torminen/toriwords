import SwiftUI
import ToriShared
import UIKit
import UniformTypeIdentifiers

/// Principal class: reads the shared items, then hosts the SwiftUI capture sheet (doc 36 §5.3).
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        Task { @MainActor in
            let payload = await Self.payload(from: items)
            let model = ShareModel(payload: payload, group: AppGroup.shared) { [weak self] saved in
                if saved { self?.extensionContext?.completeRequest(returningItems: nil) }
                else { self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled)) }
            }
            let host = UIHostingController(rootView: ShareSheetView(model: model))
            addChild(host)
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(host.view)
            host.didMove(toParent: self)
        }
    }

    /// Safari preprocessing result (property list), then URL and plain-text items in order.
    private static func payload(from items: [NSExtensionItem]) async -> SharePayload {
        var javaScript: [String: String]?
        var texts: [String] = []
        var urls: [String] = []
        for item in items {
            if let text = item.attributedContentText?.string { texts.append(text) }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier) {
                    javaScript = await loadJavaScriptResult(provider) ?? javaScript
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = await loadString(provider, type: UTType.url) { urls.append(url) }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = await loadString(provider, type: UTType.plainText) { texts.append(text) }
                }
            }
        }
        return SharePayload(javaScript: javaScript, texts: texts, urls: urls)
    }

    /// Values are converted to Sendable strings inside the callback.
    private static func loadString(_ provider: NSItemProvider, type: UTType) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier) { item, _ in
                let value: String? = switch item {
                case let url as URL: url.absoluteString
                case let string as String: string
                case let data as Data: String(data: data, encoding: .utf8)
                default: nil
                }
                continuation.resume(returning: value)
            }
        }
    }

    private static func loadJavaScriptResult(_ provider: NSItemProvider) async -> [String: String]? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.propertyList.identifier) { item, _ in
                let results = (item as? NSDictionary)?[NSExtensionJavaScriptPreprocessingResultsKey] as? NSDictionary
                var out: [String: String]?
                if let results {
                    out = [:]
                    for (key, value) in results { if let k = key as? String, let v = value as? String { out?[k] = v } }
                }
                continuation.resume(returning: out)
            }
        }
    }
}
