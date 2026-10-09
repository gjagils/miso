import PhotosUI
import SwiftUI

/// Nieuw recept uit een link, geplakte tekst of foto's.
struct ImportView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var text = ""
    @State private var photos: [PhotosPickerItem] = []
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        MascotView(pose: "snap-it", size: 80)
                        Text("Deel een link, tekst of foto, dan zet Miso het om in een recept.")
                            .font(.misoBody).foregroundStyle(Color.misoBlue)
                    }
                    .listRowBackground(Color.clear)
                }
                Section {
                    TextField("https://...", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: 44)
                } header: { Text("Link naar een recept").misoSectionHeader() }
                .misoRow()
                Section {
                    TextEditor(text: $text).frame(minHeight: 100).scrollContentBackground(.hidden)
                } header: { Text("of plak de tekst").misoSectionHeader() }
                .misoRow()
                Section {
                    PhotosPicker(selection: $photos, maxSelectionCount: 6, matching: .images) {
                        Label(photos.isEmpty ? "Foto's kiezen" : "\(plural(photos.count, "foto", "foto's")) gekozen", systemImage: "photo.on.rectangle")
                            .foregroundStyle(Color.misoBlue).font(.misoButton)
                            .frame(minHeight: 44)
                    }
                } header: { Text("of kies foto's (bijv. voor- en achterkant)").misoSectionHeader() }
                .misoRow()
                if let errorText {
                    Section { Label(errorText, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.red) }
                        .misoRow()
                }
                Section {
                    Button(action: startImport) {
                        if busy {
                            HStack { ProgressView(); Text("Bezig met omzetten...") }
                        } else {
                            Text("Recept omzetten")
                        }
                    }
                    .buttonStyle(.misoPrimary)
                    .disabled(busy || (url.isEmpty && text.isEmpty && photos.isEmpty))
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .misoScreen()
            .navigationTitle("Nieuw recept")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer", action: cancel) }
            }
        }
    }

    private func cancel() {
        dismiss()
    }

    private func startImport() {
        Task { await runImport() }
    }

    private func runImport() async {
        guard let api = session.api else { return }
        busy = true
        errorText = nil
        defer { busy = false }
        let (images, failed) = await Self.jpegs(from: photos)
        if failed > 0 {
            errorText = failed == photos.count
                ? (failed == 1 ? "De foto kon niet worden gelezen." : "De \(failed) foto's konden niet worden gelezen.")
                : "\(failed) van de \(photos.count) foto's \(failed == 1 ? "kon" : "konden") niet worden gelezen."
            errorText? += " Kies de foto's opnieuw."
            return
        }
        do {
            let result = try await api.importRecipe(url: url, text: text, images: images)
            if result.ok { dismiss() } else { errorText = result.error ?? "Importeren mislukt" }
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// Foto's laden en als JPEG klaarzetten, buiten de main actor (decoderen en comprimeren is zwaar).
    /// Geeft ook terug hoeveel foto's niet gelezen konden worden.
    private nonisolated static func jpegs(from items: [PhotosPickerItem]) async -> (images: [Data], failed: Int) {
        var images: [Data] = []
        var failed = 0
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.85) {
                images.append(jpeg)
            } else {
                failed += 1
            }
        }
        return (images, failed)
    }
}
