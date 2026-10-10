import SwiftUI

/// Ronde initiaal in de kleur van het gezinslid.
struct MemberAvatar: View {
    let member: Member
    var size: CGFloat = 44

    var body: some View {
        Text(member.initial)
            .font(.system(size: size * 0.45, weight: .heavy, design: .rounded))
            .foregroundStyle(Color(hex: member.color).prefersDarkText ? Color.misoInk : .white)
            .frame(width: size, height: size)
            .background(Color(hex: member.color), in: Circle())
            .accessibilityHidden(true)
    }
}

/// Kleine avatar in de knoppenbalk: tik om te wisselen van gezinslid.
struct MemberAvatarButton: View {
    @Environment(FamilyModel.self) private var family
    @State private var showPicker = false

    var body: some View {
        if !family.unsupported {
            Button {
                showPicker = true
            } label: {
                Group {
                    if let me = family.current {
                        MemberAvatar(member: me, size: 32)
                    } else {
                        Image(systemName: "person.crop.circle").font(.title2)
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
            }
            .accessibilityLabel(family.current.map { "Jij bent \($0.name). Wissel van gezinslid" } ?? "Wie ben jij?")
            .sheet(isPresented: $showPicker) {
                WhoView(asSheet: true)
            }
        }
    }
}
