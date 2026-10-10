import SwiftUI

/// Avatar van het gezinslid (foto achter de pincode), anders een ronde initiaal in de eigen kleur.
struct MemberAvatar: View {
    @Environment(Session.self) private var session
    let member: Member
    var size: CGFloat = 44
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: size, height: size).clipShape(Circle())
            } else {
                initial
            }
        }
        .accessibilityHidden(true)
        .task(id: member.avatarUrl) { await load() }
    }

    private func load() async {
        guard !member.avatarUrl.isEmpty, let api = session.api else { image = nil; return }
        if let cached = AvatarCache.shared.image(member.avatarUrl) { image = cached; return }
        if let data = try? await api.protectedData(member.avatarUrl), let ui = UIImage(data: data) {
            AvatarCache.shared.store(ui, for: member.avatarUrl)
            image = ui
        }
    }

    private var initial: some View {
        Text(member.initial)
            .font(.system(size: size * 0.45, weight: .heavy, design: .rounded))
            .foregroundStyle(Color(hex: member.color).prefersDarkText ? Color.misoInk : .white)
            .frame(width: size, height: size)
            .background(Color(hex: member.color), in: Circle())
    }
}

/// Avatars één keer per app-sessie ophalen.
@MainActor
final class AvatarCache {
    static let shared = AvatarCache()
    private var images: [String: UIImage] = [:]
    func image(_ key: String) -> UIImage? { images[key] }
    func store(_ image: UIImage, for key: String) { images[key] = image }
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
