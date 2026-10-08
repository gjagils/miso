import SwiftUI
import UIKit

/// Grote letters, scherm blijft aan; tik op een stap of ingrediënt om af te vinken.
struct CookView: View {
    @Environment(\.dismiss) private var dismiss
    let recipe: RecipeDetail
    @State private var checked: Set<Int> = []
    @State private var done: Set<Int> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        MascotView(pose: "chef", size: 72)
                        Text("Veel kookplezier! Tik om af te vinken.").font(.misoHeadline).foregroundStyle(Color.misoBlue)
                    }
                    .listRowBackground(Color.clear)
                }
                if recipe.gfMode != "none" {
                    Section {
                        GlutenFreeChip()
                        if !recipe.gfNote.isEmpty { Text(recipe.gfNote) }
                    }
                }
                Section {
                    ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { index, ingredient in
                        Button {
                            toggle(&checked, index)
                        } label: {
                            HStack(alignment: .top) {
                                Image(systemName: checked.contains(index) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(checked.contains(index) ? Color.misoOrange : Color.secondary)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading) {
                                    Text(ingredient.text)
                                    if ingredient.gluten && recipe.gfMode != "none" && !ingredient.gfSearch.isEmpty {
                                        Text(recipe.gfMode == "replace" ? "i.p.v. gluten: \(ingredient.gfSearch)" : "extra voor 1: \(ingredient.gfSearch)")
                                            .font(.callout).foregroundStyle(Color.misoBlue)
                                    }
                                }
                            }
                            .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                    }
                } header: { Text("Ingrediënten").misoSectionHeader() }
                .misoRow()
                Section {
                    ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { index, step in
                        Button {
                            toggle(&done, index)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)").font(.system(.title3, design: .rounded).weight(.heavy)).foregroundStyle(Color.misoOrange)
                                Text(step)
                            }
                            .font(.title3)
                            .opacity(done.contains(index) ? 0.35 : 1)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 6)
                    }
                } header: { Text("Bereiding").misoSectionHeader() }
                .misoRow()
            }
            .misoScreen()
            .navigationTitle(recipe.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() }.font(.misoButton) }
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func toggle(_ set: inout Set<Int>, _ value: Int) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }
}
