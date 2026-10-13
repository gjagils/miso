import SwiftUI

/// "Is op": zet het product van dit ingrediënt op het AH-lijstje (tijdens het koken). Bestelt niets.
/// Alleen voor ouders; de server weigert het ook voor kinderen.
struct OutButton: View {
    @Environment(Session.self) private var session
    let productID: Int
    let name: String
    @State private var state: State = .idle

    enum State: Equatable { case idle, busy, done, failed(String) }

    var body: some View {
        Button(action: press) {
            switch state {
            case .idle: Text("Is op")
            case .busy: ProgressView()
            case .done: Label("Op lijstje", systemImage: "checkmark")
            case .failed: Text("Mislukt")
            }
        }
        .font(.system(.subheadline, design: .rounded).weight(.semibold))
        .foregroundStyle(Color.misoBlue)
        .padding(.horizontal, 10)
        .frame(minWidth: 44, minHeight: 44)
        .background(Color.misoLilac.opacity(0.5), in: Capsule())
        .disabled(state == .busy || state == .done)
        .accessibilityLabel("\(name) is op")
        .accessibilityHint("Zet het op je AH-lijstje")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        switch state {
        case .done: "staat op het lijstje"
        case .failed(let message): message
        default: ""
        }
    }

    private func press() {
        guard let api = session.api else { return }
        state = .busy
        Task {
            do {
                let result = try await api.markOut(productID: productID, name: name)
                state = result.ok ? .done : .failed(result.error ?? "Op het lijstje zetten is niet gelukt.")
            } catch {
                state = .failed(error.localizedDescription)
            }
            if case .failed = state {
                try? await Task.sleep(for: .seconds(3))
                state = .idle
            }
        }
    }
}
