import Foundation
import UIKit
import UniformTypeIdentifiers
import WebKit

/// Wat de extensie van de gedeelde pagina weet: titel, link, JSON-LD-blokken, zichtbare tekst en receptfoto.
struct PageContent {
    var title: String
    var url: String
    var jsonLD: [String]
    var text: String
    /// Foto van het recept (JSON-LD `image`, anders og:image/twitter:image, anders de grootste foto). Leeg = onbekend.
    var imageURL: String

    init(title: String, url: String, jsonLD: [String] = [], text: String, imageURL: String = "") {
        self.title = title
        self.url = url
        self.jsonLD = jsonLD
        self.text = text
        self.imageURL = imageURL
    }

    /// Uit het resultaat van GetPageContent.js (Safari-preprocessing of WKWebView).
    init?(script result: Any?) {
        guard let dict = result as? [String: Any] else { return nil }
        title = (dict["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        url = dict["url"] as? String ?? ""
        jsonLD = dict["jsonld"] as? [String] ?? []
        text = dict["text"] as? String ?? ""
        imageURL = dict["image"] as? String ?? ""
    }

    var recipeJSONLD: [String] { jsonLD.filter { $0.contains("Recipe") } }
    var hasRecipeData: Bool { !recipeJSONLD.isEmpty }

    var displayTitle: String {
        if !title.isEmpty { return title }
        if let host = URL(string: url)?.host() { return host }
        return String(text.prefix(80))
    }

    /// Tekst voor /api/import. Bevat alles wat de server nodig heeft, zodat hij de (vaak geblokkeerde) site niet zelf hoeft op te halen.
    var importText: String {
        var parts: [String] = []
        if !title.isEmpty { parts.append("Titel: \(title)") }
        if !url.isEmpty { parts.append("Bron: \(url)") }
        let recipe = recipeJSONLD
        let ld = recipe.isEmpty ? jsonLD : recipe
        if !ld.isEmpty {
            let joined = ld.joined(separator: "\n")
            parts.append("Gestructureerde receptgegevens van de pagina (JSON-LD):\n\(joined.prefix(recipe.isEmpty ? 10_000 : 40_000))")
        }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            parts.append("Tekst van de pagina:\n\(body.prefix(recipe.isEmpty ? 60_000 : 20_000))")
        }
        return parts.joined(separator: "\n\n")
    }
}

struct ShareError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum PageCollector {
    /// Inhoud van GetPageContent.js uit de extensiebundel.
    static let script: String = {
        guard let url = Bundle.main.url(forResource: "GetPageContent", withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return js
    }()

    /// Safari levert het preprocessing-resultaat; Chrome (en andere apps) alleen een URL en/of tekst.
    /// In dat laatste geval wordt de pagina op het toestel geladen in een onzichtbare WKWebView.
    @MainActor
    static func collect(from context: NSExtensionContext?, webHost: UIView) async throws -> PageContent {
        let items = context?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        var sharedURL: URL?
        var sharedText = ""

        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier),
                   let dict = try? await provider.loadItem(forTypeIdentifier: UTType.propertyList.identifier) as? NSDictionary,
                   let page = PageContent(script: dict[NSExtensionJavaScriptPreprocessingResultsKey]),
                   !page.text.isEmpty || !page.jsonLD.isEmpty {
                    return page
                }
                if sharedURL == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
                   !url.isFileURL {
                    sharedURL = url
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    sharedText += (sharedText.isEmpty ? "" : "\n") + text
                }
            }
            if let attributed = item.attributedContentText?.string, !attributed.isEmpty, !sharedText.contains(attributed) {
                sharedText += (sharedText.isEmpty ? "" : "\n") + attributed
            }
        }

        if sharedURL == nil { sharedURL = firstWebURL(in: sharedText) }
        if let url = sharedURL, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            return try await WebPageLoader(host: webHost).load(url)
        }
        let text = sharedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let firstLine = text.split(separator: "\n").first.map(String.init) ?? ""
            return PageContent(title: String(firstLine.prefix(120)), url: "", text: String(text.prefix(60_000)))
        }
        throw ShareError(message: "Miso vond geen link of tekst om te importeren.")
    }

    static func firstWebURL(in text: String) -> URL? {
        guard !text.isEmpty, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap(\.url)
            .first { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
    }
}

/// Laadt een pagina op het toestel (zoals de gebruiker hem in de browser ziet) en leest hem met GetPageContent.js.
@MainActor
final class WebPageLoader: NSObject, WKNavigationDelegate {
    static let timeout: TimeInterval = 20

    private let webView: WKWebView
    private var finishedAt: Date?
    private var failure: Error?

    init(host: UIView) {
        let config = WKWebViewConfiguration()
        // Zelfde herkenning als Mobile Safari; WKWebView laat "Version/... Safari/..." standaard weg.
        config.applicationNameForUserAgent = "Version/17.0 Mobile/15E148 Safari/604.1"
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.alpha = 0.01 // in de view-hiërarchie (anders pauzeert WebKit scripts), maar onzichtbaar
        webView.isUserInteractionEnabled = false
        host.insertSubview(webView, at: 0)
    }

    func load(_ url: URL) async throws -> PageContent {
        defer {
            webView.stopLoading()
            webView.removeFromSuperview()
        }
        webView.load(URLRequest(url: url))
        let deadline = Date().addingTimeInterval(Self.timeout)
        var best: PageContent?
        var previousLength = -1

        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(500))
            if let failure { throw ShareError(message: "De pagina kon niet geladen worden: \(failure.localizedDescription)") }
            // Na het laden even laten bijkomen (scripts, bot-check die doorstuurt naar het echte recept).
            guard let finishedAt, Date().timeIntervalSince(finishedAt) >= 1.5 else { continue }
            guard let page = try? await evaluate() else { continue }
            if page.hasRecipeData { return page }
            if page.text.count > (best?.text.count ?? 0) { best = page }
            if !webView.isLoading, page.text.count > 1000, page.text.count == previousLength { return page }
            previousLength = page.text.count
            try await Task.sleep(for: .milliseconds(500))
        }
        if let best, best.text.count > 1000 { return best }
        throw ShareError(message: "Miso kon de pagina niet binnen \(Int(Self.timeout)) seconden lezen. "
                         + "Probeer het nog eens, of open het recept in Safari en deel het daarvandaan.")
    }

    private func evaluate() async throws -> PageContent {
        let js = PageCollector.script + "\nMisoCollectPage();"
        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(js, in: nil, in: .defaultClient) { result in
                switch result {
                case .success(let value):
                    if let page = PageContent(script: value) {
                        continuation.resume(returning: page)
                    } else {
                        continuation.resume(throwing: ShareError(message: "Onverwacht scriptresultaat"))
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishedAt = Date()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        record(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        record(error)
    }

    private func record(_ error: Error) {
        // Afgebroken door een nieuwe navigatie (bijv. doorsturen na een bot-check) is geen fout.
        if (error as NSError).code == NSURLErrorCancelled { return }
        // Al iets geladen? Dan gewoon lezen wat er staat.
        if finishedAt == nil { failure = error }
    }
}
