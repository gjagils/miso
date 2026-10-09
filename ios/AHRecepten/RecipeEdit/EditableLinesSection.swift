import SwiftUI

/// Lijst met tekstregels om te bewerken, toe te voegen, te verwijderen en te verslepen.
struct EditableLinesSection: View {
    let title: String
    let placeholder: String
    let addTitle: String
    /// VoiceOver-naam per regel, bijv. "Stap 2".
    let lineLabel: (Int) -> String
    @Binding var lines: [EditableLine]
    var multiline = false
    @FocusState private var focused: UUID?

    var body: some View {
        Section {
            ForEach($lines) { $line in
                let number = (lines.firstIndex { $0.id == line.id } ?? 0) + 1
                TextField(placeholder, text: $line.text, axis: multiline ? .vertical : .horizontal)
                    .focused($focused, equals: line.id)
                    .frame(minHeight: 44)
                    .accessibilityLabel(lineLabel(number))
            }
            .onDelete(perform: delete)
            .onMove(perform: move)
            Button(addTitle, systemImage: "plus.circle.fill", action: add)
                .font(.misoButton)
                .foregroundStyle(Color.misoBlue)
                .frame(minHeight: 44)
        } header: {
            Text(title).misoSectionHeader()
        }
        .misoRow()
    }

    private func add() {
        let line = EditableLine("")
        withAnimation { lines.append(line) }
        focused = line.id
    }

    private func delete(_ offsets: IndexSet) {
        lines.remove(atOffsets: offsets)
    }

    private func move(_ source: IndexSet, _ destination: Int) {
        lines.move(fromOffsets: source, toOffset: destination)
    }
}
