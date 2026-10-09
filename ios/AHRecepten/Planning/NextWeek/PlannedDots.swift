import SwiftUI

/// Zeven stippen: hoeveel dagen van volgende week gepland zijn.
struct PlannedDots: View {
    let planned: Int
    var total = 7

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                // Lege dagen als randje: een licht vlakje verdwijnt in dark mode tegen de kaart.
                Circle()
                    .fill(index < planned ? Color.misoOrange : Color.clear)
                    .strokeBorder(index < planned ? Color.misoOrange : Color.misoBlue.opacity(0.55), lineWidth: 1.5)
                    .frame(width: 9, height: 9)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(planned) van \(total) dagen gepland")
    }
}
