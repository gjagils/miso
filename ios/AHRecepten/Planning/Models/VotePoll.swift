import Foundation

/// Eén kandidaat in de stemronde van de week.
struct VoteCandidate: Decodable, Identifiable, Hashable, Sendable {
    let recipeId: Int
    let name: String
    let imageUrl: String
    let totalTime: String
    let votes: Int
    /// Initialen van wie erop stemde.
    let voters: [String]
    /// Mijn stem staat erop.
    let mine: Bool

    var id: Int { recipeId }

    enum CodingKeys: String, CodingKey { case recipeId, name, imageUrl, totalTime, votes, voters, mine }

    init(recipeId: Int, name: String, imageUrl: String = "", totalTime: String = "", votes: Int = 0,
         voters: [String] = [], mine: Bool = false) {
        self.recipeId = recipeId
        self.name = name
        self.imageUrl = imageUrl
        self.totalTime = totalTime
        self.votes = votes
        self.voters = voters
        self.mine = mine
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.lenientInt(.recipeId) else {
            throw DecodingError.dataCorruptedError(forKey: .recipeId, in: c, debugDescription: "kandidaat zonder recept")
        }
        self.init(recipeId: id, name: c.lenient(String.self, .name) ?? "", imageUrl: c.lenient(String.self, .imageUrl) ?? "",
                  totalTime: c.lenient(String.self, .totalTime) ?? "", votes: c.lenientInt(.votes) ?? 0,
                  voters: c.lenient([String].self, .voters) ?? [], mine: c.lenient(Bool.self, .mine) ?? false)
    }

    /// "30 min · 2 stemmen (G N)"
    var detail: String {
        let count = "\(votes) \(votes == 1 ? "stem" : "stemmen")"
        let who = voters.isEmpty ? "" : " (\(voters.joined(separator: " ")))"
        return [totalTime, count + who].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// `GET /api/vote-poll`, en het antwoord van starten en stemmen.
struct VotePoll: Decodable, Equatable, Sendable {
    let ok: Bool
    let error: String?
    let week: String
    let open: Bool
    let maxVotes: Int
    let candidates: [VoteCandidate]
    let myVotes: Int
    let votedCount: Int
    let membersTotal: Int

    enum CodingKeys: String, CodingKey {
        case ok, error, week, open, maxVotes, candidates, myVotes, votedCount, membersTotal
    }

    init(ok: Bool = true, error: String? = nil, week: String = "", open: Bool = false, maxVotes: Int = 3,
         candidates: [VoteCandidate] = [], myVotes: Int = 0, votedCount: Int = 0, membersTotal: Int = 0) {
        self.ok = ok
        self.error = error
        self.week = week
        self.open = open
        self.maxVotes = maxVotes
        self.candidates = candidates
        self.myVotes = myVotes
        self.votedCount = votedCount
        self.membersTotal = membersTotal
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(ok: c.lenient(Bool.self, .ok) ?? false, error: c.lenient(String.self, .error),
                  week: c.lenient(String.self, .week) ?? "", open: c.lenient(Bool.self, .open) ?? false,
                  maxVotes: c.lenientInt(.maxVotes) ?? 3, candidates: c.lenient([VoteCandidate].self, .candidates) ?? [],
                  myVotes: c.lenientInt(.myVotes) ?? 0, votedCount: c.lenientInt(.votedCount) ?? 0,
                  membersTotal: c.lenientInt(.membersTotal) ?? 0)
    }

    /// "Stem op maximaal 3 recepten ... 2 van 4 hebben gestemd; jij gaf 1 van 3 stemmen."
    var intro: String {
        open
            ? "Stem op maximaal \(maxVotes) recepten die je graag wilt eten. \(votedCount) van \(membersTotal) hebben gestemd; jij gaf \(myVotes) van \(maxVotes) stemmen."
            : "Laat het gezin kiezen: Miso zet een paar recepten klaar, iedereen stemt, en de uitslag vult de lege dagen."
    }
}

/// `POST /api/vote-poll/close`.
struct VoteCloseResponse: Decodable, Sendable {
    let ok: Bool
    let error: String?
    let placed: Int
    let noRoom: Int
    let noVotes: Int

    enum CodingKeys: String, CodingKey { case ok, error, placed, noRoom, noVotes }

    init(ok: Bool = true, error: String? = nil, placed: Int, noRoom: Int = 0, noVotes: Int = 0) {
        self.ok = ok
        self.error = error
        self.placed = placed
        self.noRoom = noRoom
        self.noVotes = noVotes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(ok: c.lenient(Bool.self, .ok) ?? false, error: c.lenient(String.self, .error),
                  placed: c.lenientInt(.placed) ?? 0, noRoom: c.lenientInt(.noRoom) ?? 0,
                  noVotes: c.lenientInt(.noVotes) ?? 0)
    }

    /// "1 dag gevuld, 1 recept zonder stem overgeslagen."
    var summary: String {
        func plural(_ n: Int, _ one: String, _ more: String) -> String { "\(n) \(n == 1 ? one : more)" }
        var bits = ["\(plural(placed, "dag", "dagen")) gevuld"]
        if noRoom > 0 { bits.append("\(plural(noRoom, "recept", "recepten")) kon er niet meer bij") }
        if noVotes > 0 { bits.append("\(plural(noVotes, "recept", "recepten")) zonder stem overgeslagen") }
        return bits.joined(separator: ", ") + "."
    }
}

struct VoteStartBody: Encodable { let week: String }
struct VoteCastBody: Encodable {
    let week: String
    let recipeId: Int
    let on: Bool

    enum CodingKeys: String, CodingKey { case week, recipeId = "recipe_id", on }
}
