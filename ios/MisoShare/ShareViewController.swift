import SwiftUI
import UIKit

/// Ingang van de deel-extensie "Deel naar Miso". Host de SwiftUI-weergave.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(named: "MisoCream")

        model.finish = { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        model.cancel = { [weak self] in
            self?.extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        }

        let host = UIHostingController(rootView: ShareView(model: model))
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        model.start(context: extensionContext, webHost: view)
    }
}

@MainActor
@Observable
final class ShareModel {
    enum Phase {
        case reading
        case ready(PageContent)
        case saving(PageContent)
        case saved(String)
        case failed(String, PageContent?)
        case notLoggedIn
    }

    var phase: Phase = .reading
    var finish: () -> Void = {}
    var cancel: () -> Void = {}

    private let session = Session()

    func start(context: NSExtensionContext?, webHost: UIView) {
        guard session.isConnected else {
            phase = .notLoggedIn
            return
        }
        Task {
            do {
                phase = .ready(try await PageCollector.collect(from: context, webHost: webHost))
            } catch {
                phase = .failed(error.localizedDescription, nil)
            }
        }
    }

    func save(_ page: PageContent) {
        guard let api = session.api else {
            phase = .notLoggedIn
            return
        }
        phase = .saving(page)
        Task {
            do {
                // Geen url meesturen: dan zou de server de site zelf ophalen (en geblokkeerd worden).
                // De link staat wel in de tekst ("Bron: ...").
                let result = try await api.importRecipe(url: "", text: page.importText, images: [])
                guard result.ok else {
                    phase = .failed(result.error ?? "Importeren mislukt.", page)
                    return
                }
                var name = page.displayTitle
                if let id = result.id, let detail = try? await api.recipe(id: id) { name = detail.name }
                phase = .saved(name)
            } catch {
                phase = .failed(error.localizedDescription, page)
            }
        }
    }
}

struct ShareView: View {
    let model: ShareModel

    var body: some View {
        VStack(spacing: 20) {
            Text("Deel naar Miso")
                .font(.misoTitle2)
                .foregroundStyle(Color.misoBlue)
                .padding(.top, 24)
            Spacer(minLength: 0)
            content
            Spacer(minLength: 0)
            buttons
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.misoCream)
        .tint(Color.misoOrange)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .reading:
            status(pose: "snap-it", title: "Pagina lezen...", message: nil, progress: true)
        case .ready(let page):
            status(pose: "snap-it", title: page.displayTitle, message: page.url.isEmpty ? nil : URL(string: page.url)?.host(), progress: false)
        case .saving(let page):
            status(pose: "snap-it", title: page.displayTitle, message: "Miso zet het recept om...", progress: true)
        case .saved(let name):
            status(pose: "celebrate", title: "Opgeslagen: \(name)", message: nil, progress: false)
        case .failed(let message, _):
            status(pose: "confused", title: "Dat lukte niet", message: message, progress: false)
        case .notLoggedIn:
            status(pose: "confused", title: "Open eerst Miso en log in.", message: nil, progress: false)
        }
    }

    private func status(pose: String, title: String, message: String?, progress: Bool) -> some View {
        VStack(spacing: 14) {
            MascotView(pose: pose, size: 140)
            Text(title)
                .font(.misoHeadline)
                .foregroundStyle(Color.misoBlue)
                .multilineTextAlignment(.center)
                .lineLimit(4)
            if let message {
                Text(message)
                    .font(.misoBody)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if progress { ProgressView() }
        }
        .frame(maxWidth: .infinity)
        .misoCard(padding: 20)
    }

    @ViewBuilder
    private var buttons: some View {
        VStack(spacing: 12) {
            switch model.phase {
            case .reading:
                Button("Annuleer") { model.cancel() }.buttonStyle(.misoSecondary)
            case .ready(let page):
                Button("Recept opslaan in Miso") { model.save(page) }.buttonStyle(.misoPrimary)
                Button("Annuleer") { model.cancel() }.buttonStyle(.misoSecondary)
            case .saving:
                Button("Recept opslaan in Miso") {}.buttonStyle(.misoPrimary).disabled(true)
                Button("Annuleer") { model.cancel() }.buttonStyle(.misoSecondary)
            case .saved:
                Button("Klaar") { model.finish() }.buttonStyle(.misoPrimary)
            case .failed(_, let page):
                if let page {
                    Button("Opnieuw proberen") { model.save(page) }.buttonStyle(.misoPrimary)
                }
                Button("Sluiten") { model.cancel() }.buttonStyle(.misoSecondary)
            case .notLoggedIn:
                Button("Sluiten") { model.cancel() }.buttonStyle(.misoSecondary)
            }
        }
    }
}
