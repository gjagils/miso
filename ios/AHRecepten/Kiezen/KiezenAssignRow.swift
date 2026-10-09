import SwiftUI

/// Gekozen recept in stap 2: dag, personen en "Kook dubbel…".
struct KiezenAssignRow: View {
    let assignment: Assignment
    let dates: [String]
    @Binding var day: String
    let onPersons: (Int) -> Void
    let onMore: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RecipeImage(path: assignment.imageUrl, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(assignment.name)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.misoBlue)
                    .lineLimit(2)
                if let already = assignment.already, assignment.day.isEmpty {
                    Text("staat al op \(KiezenDates.label(already).lowercased())").font(.caption).foregroundStyle(.secondary)
                }
                Picker("Dag voor \(assignment.name)", selection: $day) {
                    ForEach(dates, id: \.self) { d in Text(KiezenDates.label(d)).tag(d) }
                    Text("Niet inplannen").tag("")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(Color.misoOrange)
                .fixedSize()
                .accessibilityLabel("Dag voor \(assignment.name)")
                if !assignment.day.isEmpty {
                    HStack(spacing: 8) {
                        Text("Voor").font(.caption).foregroundStyle(.secondary)
                        PersonsStepper(value: assignment.persons, label: "Personen voor \(assignment.name)",
                                       onChange: onPersons)
                        Button("Kook dubbel…", action: onMore)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Color.misoBlue)
                            .buttonStyle(.borderless)
                            .frame(minHeight: 44)
                    }
                    if let cookDouble = assignment.cookDouble {
                        Text(cookDouble.summary).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
