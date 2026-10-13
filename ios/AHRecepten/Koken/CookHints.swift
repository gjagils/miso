import Foundation

/// Eerlijke kooktijd en "zet eerst de oven aan", uit de bereiding (zoals `cook_hints` in
/// backend/app/planning.py): "bak 30 min. in de oven op 200 °C" bij een recept van "20 min" → ± 50 min.
struct CookHints: Equatable, Sendable {
    /// Geschatte totale tijd (nil = onbekend).
    let minutes: Int?
    let ovenMinutes: Int?
    /// "200"
    let ovenTemperature: String?
    /// Duurt merkbaar langer dan het recept zegt.
    let longer: Bool

    private static let temp = try! NSRegularExpression(pattern: #"(\d{3})\s*(?:°|graden)"#)
    private static let sentenceBreak = try! NSRegularExpression(pattern: #"(?<=[.!?])\s+(?=[A-Z])"#)
    private static let mins = try! NSRegularExpression(pattern: #"(\d{1,3})\s*(?:-\s*\d+\s*)?min"#)
    private static let hours = try! NSRegularExpression(pattern: #"(\d+(?:[.,]\d+)?)\s*uur"#)

    /// "45 min" -> 45, "2 uur" -> 120, "1,5 uur" -> 90; geen getal -> 0 (zoals `cooktime.minutes` op de server).
    static func listedMinutes(_ total: String) -> Int {
        let lower = total.lowercased()
        guard let range = lower.range(of: #"\d+(?:[.,]\d+)?"#, options: .regularExpression) else { return 0 }
        let number = lower[range].replacingOccurrences(of: ",", with: ".")
        guard let value = Double(number) else { return 0 }
        if lower.contains("uur") && value < 5 { return Int((value * 60).rounded()) }
        return Int(value)
    }

    init(minutes: Int?, ovenMinutes: Int?, ovenTemperature: String?, longer: Bool) {
        self.minutes = minutes
        self.ovenMinutes = ovenMinutes
        self.ovenTemperature = ovenTemperature
        self.longer = longer
    }

    init(instructions: [String], totalTime: String) {
        let raw = instructions.joined(separator: " ")
        let lower = raw.lowercased()
        let lns = lower as NSString
        let temperature = Self.temp.firstMatch(in: lower, range: NSRange(location: 0, length: lns.length))
            .map { lns.substring(with: $0.range(at: 1)) }
        var oven = 0
        for sentence in Self.sentences(raw) {
            let s = sentence.lowercased()
            // "oven", "ovenschaal"; niet "stoven" of "bovenop"
            guard s.range(of: #"\boven"#, options: .regularExpression) != nil else { continue }
            let sns = s as NSString
            for m in Self.mins.matches(in: s, range: NSRange(location: 0, length: sns.length)) {
                oven = max(oven, Int(sns.substring(with: m.range(at: 1))) ?? 0)
            }
            for m in Self.hours.matches(in: s, range: NSRange(location: 0, length: sns.length)) {
                let hours = Double(sns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: ".")) ?? 0
                oven = max(oven, Int((hours * 60).rounded()))
            }
        }
        let listed = Self.listedMinutes(totalTime)
        var estimate = listed
        if oven > 0 && listed < oven + 10 { estimate = listed + oven } // opgegeven tijd is vaak alleen het snijwerk
        minutes = estimate > 0 ? estimate : nil
        ovenMinutes = oven > 0 ? oven : nil
        ovenTemperature = temperature
        longer = estimate > 0 && listed > 0 && estimate > listed + 5
    }

    private static func sentences(_ raw: String) -> [String] {
        let ns = raw as NSString
        var out: [String] = []
        var start = 0
        for m in sentenceBreak.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
            out.append(ns.substring(with: NSRange(location: start, length: m.range.location - start)))
            start = m.range.location + m.range.length
        }
        out.append(ns.substring(from: start))
        return out
    }

    /// "± 50 min (oven 30 min)"; nil als er niets bekend is.
    var timeText: String? {
        guard let minutes else { return nil }
        return "± \(minutes) min" + (ovenMinutes.map { " (oven \($0) min)" } ?? "")
    }

    /// "Klaar rond 18:40 als je nu begint" (nil als de tijd onbekend is).
    func readyText(startingAt start: Date, calendar: Calendar = .current) -> String? {
        guard let minutes, let end = calendar.date(byAdding: .minute, value: minutes, to: start) else { return nil }
        let parts = calendar.dateComponents([.hour, .minute], from: end)
        return String(format: "Klaar rond %d:%02d als je nu begint", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// "Zet eerst de oven op 200 °C"
    var ovenText: String? {
        ovenTemperature.map { "Zet eerst de oven op \($0) °C" }
    }
}
