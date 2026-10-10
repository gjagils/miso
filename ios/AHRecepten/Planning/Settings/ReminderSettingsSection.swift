import SwiftUI
import UserNotifications

/// "Herinner me voor de besteldag": lokale melding de avond ervoor om 19:00 (standaard uit).
/// Vraagt pas toestemming als je hem aanzet, na een uitleg in het Nederlands.
struct ReminderSettingsSection: View {
    @Environment(Session.self) private var session
    @Environment(\.openURL) private var openURL
    @AppStorage(OrderReminderScheduler.enabledKey) private var enabled = false
    @AppStorage(WishDayReminder.enabledKey) private var wishDay = true
    @State private var explaining = false
    @State private var denied = false

    var body: some View {
        Section {
            Toggle("Boodschappendag om 12:00: wensen doorgeven", isOn: $wishDay)
                .tint(Color.misoOrange)
                .foregroundStyle(Color.misoBlue)
                .frame(minHeight: 44)
                .onChange(of: wishDay) { _, _ in
                    Task {
                        if !wishDay { WishDayReminder.cancel() } else { await WishDayReminder.askOnce(); await refresh() }
                    }
                }
            Toggle("Herinner me voor de besteldag", isOn: $enabled)
                .tint(Color.misoOrange)
                .foregroundStyle(Color.misoBlue)
                .frame(minHeight: 44)
                .onChange(of: enabled) { _, isOn in
                    Task { await toggled(isOn) }
                }
            if denied {
                Text("Meldingen voor Miso staan uit. Zet ze aan in de iOS-instellingen en probeer het opnieuw.")
                    .font(.callout)
                Button("Open iOS-instellingen", action: openSettings)
                    .font(.misoButton)
                    .foregroundStyle(Color.misoBlue)
                    .frame(minHeight: 44)
            }
        } header: {
            Text("Herinnering").misoSectionHeader()
        } footer: {
            Text("Op de besteldag om 12:00 vraagt Miso iedereen om wensen door te geven (ouders: bekijk ze en bestel). De avond vóór de besteldag om 19:00 krijg je een melding als het weekmenu voor volgende week nog niet compleet is. Alleen op dit toestel.")
        }
        .misoRow()
        .alert("Herinnering voor de besteldag", isPresented: $explaining) {
            Button("Ga verder", action: requestPermission)
            Button("Niet nu", role: .cancel, action: turnOff)
        } message: {
            Text("Miso stuurt je de avond vóór de besteldag om 19:00 een melding als het weekmenu voor volgende week nog niet compleet is. Daarvoor vraagt iOS zo om toestemming voor meldingen. Verder stuurt Miso alleen de melding op de besteldag om 12:00 (wensen doorgeven).")
        }
    }

    // MARK: Acties

    private func toggled(_ isOn: Bool) async {
        guard isOn else {
            OrderReminderScheduler.cancel()
            return
        }
        switch await OrderReminderScheduler.authorizationStatus() {
        case .notDetermined:
            explaining = true
        case .denied:
            enabled = false
            denied = true
        default:
            denied = false
            await refresh()
        }
    }

    private func requestPermission() {
        Task {
            if await OrderReminderScheduler.requestPermission() {
                denied = false
                await refresh()
            } else {
                enabled = false
                denied = true
            }
        }
    }

    private func turnOff() {
        enabled = false
    }

    private func refresh() async {
        guard let api = session.api else { return }
        await OrderReminderScheduler.refresh(api: api)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
    }
}
