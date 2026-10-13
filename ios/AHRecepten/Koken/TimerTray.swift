import AudioToolbox
import SwiftUI

/// Knoppen met de tijden uit een bereidingsstap ("⏲ 20 min").
struct StepTimerButtons: View {
    let timers: [StepTimer]
    let onStart: (StepTimer) -> Void

    var body: some View {
        if !timers.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(timers) { timer in
                    Button { onStart(timer) } label: {
                        Label(timer.label, systemImage: "timer")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(Color.misoInk)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(Color.misoMint, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Start timer van \(timer.label)")
                }
            }
        }
    }
}

/// Lopende timers onderin de kookmodus, met aftellen; bij nul geluid, trilling en "Klaar!".
struct TimerTray: View {
    let timers: CookTimers

    var body: some View {
        if !timers.running.isEmpty {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 8) {
                    ForEach(timers.running) { timer in
                        let done = timer.isDone(at: context.date)
                        HStack(spacing: 12) {
                            Image(systemName: done ? "bell.fill" : "timer").foregroundStyle(Color.misoOrange).accessibilityHidden(true)
                            Text(timer.label).font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(Color.misoBlue)
                            Spacer()
                            Text(done ? "Klaar!" : TimerFormat.clock(timer.remaining(at: context.date)))
                                .font(.system(.title3, design: .rounded).weight(.heavy).monospacedDigit())
                                .foregroundStyle(done ? Color.misoOrange : Color.misoBlue)
                            Button(done ? "Oké" : "Stop") { timers.stop(timer.id) }
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                                .foregroundStyle(Color.misoBlue)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(timer.label): \(done ? "klaar" : TimerFormat.clock(timer.remaining(at: context.date)) + " te gaan")")
                    }
                }
                .padding(12)
                .background(Color.misoCard, in: .rect(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).stroke(Color.misoOrange, lineWidth: 2) }
                .shadow(color: Color.misoInk.opacity(0.15), radius: 8, y: 3)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .onChange(of: context.date) { _, now in announce(now) }
            }
        }
    }

    private func announce(_ now: Date) {
        guard !timers.newlyDone(at: now).isEmpty else { return }
        AudioServicesPlaySystemSound(1005)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
