import Foundation
import Observation

/// Stemronde van de week: kandidaten, stemmen, sluiten (de uitslag vult lege dagen). Bestelt niets.
@MainActor
@Observable
final class VoteModel {
    private(set) var poll: VotePoll?
    private(set) var busy = false
    var errorText: String?
    var message: String?

    func load(week: String, api: API) async {
        do {
            let result: VotePoll = try await api.get("api/vote-poll", query: [URLQueryItem(name: "week", value: week)])
            poll = result
            errorText = nil
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            errorText = error.localizedDescription
        }
    }

    func start(week: String, api: API) async {
        await run("Starten mislukt.") {
            let result: VotePoll = try await api.post("api/vote-poll", json: VoteStartBody(week: week))
            self.accept(result)
        }
    }

    func cast(_ candidate: VoteCandidate, week: String, api: API) async {
        await run("Stemmen mislukt.") {
            let result: VotePoll = try await api.post("api/votes", json: VoteCastBody(week: week, recipeId: candidate.recipeId,
                                                                                     on: !candidate.mine))
            self.accept(result)
        }
    }

    /// Sluit de ronde en vul de lege dagen. Geeft true bij succes (het weekmenu moet dan verversen).
    func close(week: String, api: API) async -> Bool {
        var done = false
        await run("Sluiten mislukt.") {
            let result: VoteCloseResponse = try await api.post("api/vote-poll/close", json: VoteStartBody(week: week))
            guard result.ok else {
                self.errorText = result.error ?? "Sluiten mislukt."
                return
            }
            self.message = result.summary
            self.errorText = nil
            done = true
        }
        if done { await load(week: week, api: api) }
        return done
    }

    func cancel(week: String, api: API) async {
        await run("Stoppen mislukt.") {
            let _: OKResponse = try await api.delete("api/vote-poll?week=\(week)")
            self.message = nil
        }
        await load(week: week, api: api)
    }

    private func accept(_ result: VotePoll) {
        if result.ok {
            poll = result
            errorText = nil
            message = nil
        } else {
            errorText = result.error ?? "Dat lukte niet."
        }
    }

    private func run(_ failure: String, _ work: @escaping () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do { try await work() } catch { errorText = "\(failure) \(error.localizedDescription)" }
    }
}
