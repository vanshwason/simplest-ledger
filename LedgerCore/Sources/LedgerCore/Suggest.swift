import Foundation

/// Tap-to-fill suggestions for the text box, built from the app's own commands and your latest entry.
public enum Suggest {
    /// Commands in the order a prefix should resolve them ("go" → going on a trip).
    static let commands = ["split", "delete", "remove", "going", "trip", "lent", "borrowed", "got"]
    static let skipWords: Set<String> = ["spent", "spend", "paid", "pay", "for", "the", "via", "rupees", "upi", "cash",
                                         "card", "credit", "debit", "and", "with", "from", "bought", "on"]

    /// A word that points at an entry, e.g. "wifi" from "Paid 1500 for wifi bill".
    public static func keyword(of entry: Entry) -> String? {
        entry.raw.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            .first { $0.count >= 3 && $0.first?.isLetter == true && !skipWords.contains($0) }
    }

    /// What to show above the text box. Empty input gets examples; a first word that is (or is close to)
    /// a command gets that command's templates. Anything else gets nothing, so normal typing stays quiet.
    public static func forInput(_ text: String, entries: [Entry], activeTrip: String?) -> (didYouMean: String?, chips: [String]) {
        let latest = entries.filter { $0.kind == .expense }.max { $0.date < $1.date }.flatMap(keyword)
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard let first = words.first else {
            return (nil, ["1500 snacks via UPI", "lent 2000 to Rahul",
                          latest.map { "split the \($0) with 2 people" } ?? "split 1200 dinner with Rahul",
                          activeTrip == nil ? "going on goa trip" : "trip over"])
        }
        if words.count == 1, first.count >= 2, let command = commands.first(where: { $0.hasPrefix(first) }) {
            return (nil, templates(command, latest: latest))
        }
        if let command = typo(first) { return ("Did you mean \(command)?", templates(command, latest: latest)) }
        return (nil, [])
    }

    /// Ways to retry when a command found nothing.
    public static func fixes(forFailed text: String, entries: [Entry]) -> [String] {
        let latest = entries.filter { $0.kind == .expense }.max { $0.date < $1.date }.flatMap(keyword)
        if DeleteCommand.parse(text) != nil {
            return ["delete the latest entry", "delete today's entries"] + (latest.map { ["delete the \($0) entry"] } ?? [])
        }
        return ["1200 dinner split with Rahul"] + (latest.map { ["split the \($0) with 2 people"] } ?? [])
    }

    static func templates(_ command: String, latest: String?) -> [String] {
        let k = latest ?? "dinner"
        switch command {
        case "split": return ["split the \(k) with 2 people", "split the \(k), he paid 500", "split 1200 dinner with Rahul and Amit"]
        case "delete", "remove": return ["delete the latest entry", "delete today's entries", "delete the \(k) entry",
                                         "all entries were test entries, please delete"]
        case "going", "trip": return ["going on goa trip", "trip over"]
        case "lent": return ["lent 2000 to Rahul", "lent 500 to Amit via UPI"]
        case "borrowed": return ["borrowed 1000 from Rahul"]
        default: return ["got 2000 back from Rahul", "got salary 50000"]
        }
    }

    /// "splt" → "split", "delte" → "delete". Money words ("rent", "food") are never treated as typos.
    static func typo(_ word: String) -> String? {
        guard word.count >= 3, word.first?.isLetter == true, !commands.contains(word),
              !RuleParser.categories.contains(where: { $0.words.contains { word.hasPrefix($0) } }) else { return nil }
        return commands.filter { $0.count >= 4 }.first { distance(word, $0) <= ($0.count >= 6 ? 2 : 1) }
    }

    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var row = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var prev = row[0]; row[0] = i
            for j in 1...max(b.count, 1) where !b.isEmpty {
                let old = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, prev + (a[i - 1] == b[j - 1] ? 0 : 1))
                prev = old
            }
        }
        return row[b.count]
    }
}
