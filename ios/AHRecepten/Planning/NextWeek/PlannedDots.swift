import SwiftUI

/// Zeven stippen: hoeveel dagen van volgende week gepland zijn.
struct PlannedDots: View {
    let planned: Int
    var total = 7

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Circle()
                    .fill(index < planned ? Color.misoOrange : Color.misoBlue.opacity(0.15))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(planned) van \(total) dagen gepland")
    }
}
