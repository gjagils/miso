import Foundation

// Soepel decoderen: oudere (of nieuwere) servers kunnen velden weglaten of een ander type sturen.
// Een ontbrekend of onleesbaar veld geeft nil in plaats van een fout voor de hele response.
extension KeyedDecodingContainer {
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }

    /// Getal dat ook als tekst ("6") mag binnenkomen.
    func lenientInt(_ key: Key) -> Int? {
        if let i = lenient(Int.self, key) { return i }
        if let s = lenient(String.self, key) { return Int(s) }
        if let d = lenient(Double.self, key) { return Int(d) }
        return nil
    }
}
