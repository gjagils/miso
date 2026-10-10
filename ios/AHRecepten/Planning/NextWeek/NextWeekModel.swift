import Foundation
import Observation

/// Banner "Volgende week" op Vandaag: hoe ver ma-vr gepland is en hoe lang tot de besteldag.
/// Plannen zelf gebeurt in het Plannen-tabblad.
@MainActor
@Observable
final class NextWeekModel {
    private(set) var status: NextWeekStatus?

    /// Groot tonen: vanaf 2 dagen voor de besteldag, zolang de week niet klaar is.
    var isProminent: Bool { (status?.prominent ?? false) && !(status?.isComplete ?? true) }

    /// Status ophalen en daarmee de lokale herinnering bijwerken. Een oudere server zonder dit endpoint: geen banner.
    func load(api: API) async {
        guard let result = try? await api.nextWeekStatus() else { return }
        status = result
        await OrderReminderScheduler.apply(result)
    }
}
