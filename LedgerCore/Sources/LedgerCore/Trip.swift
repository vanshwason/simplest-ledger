import Foundation

/// "going on goa trip", "started manali trip", "trip over", "back from trip".
/// Lines with a number are money entries ("goa trip hotel 5000"), never commands.
public enum TripCommand: Equatable, Sendable {
    case start(String)
    case end

    static let startWords: Set<String> = ["start", "started", "starting", "begin", "going", "shuru", "new"]
    static let endWords: Set<String> = ["end", "ended", "over", "finished", "khatam", "done", "back", "stop"]
    static let skip: Set<String> = startWords.union(["trip", "a", "the", "my", "to", "on", "for", "ho", "gaya", "gayi", "hai",
                                                     "kar", "do", "ki", "ka", "i", "am", "we", "are", "is", "our"])

    public static func parse(_ text: String) -> TripCommand? {
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard words.contains("trip"), !words.contains(where: { $0.first?.isNumber == true }) else { return nil }
        if words.contains(where: endWords.contains) { return .end }
        guard words.contains(where: startWords.contains) else { return nil }
        let name = words.filter { !skip.contains($0) }.map(\.capitalized).joined(separator: " ")
        return .start(name.isEmpty ? "Trip" : name)
    }
}

public extension Collection where Element == Entry {
    /// What you spent on a trip (your shares only; money lent to friends isn't your cost).
    func spent(onTrip trip: String) -> Decimal {
        filter { $0.trip == trip && $0.kind == .expense }.compactMap(\.amount).reduce(0, +)
    }
}
