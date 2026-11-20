import Foundation

/// "all entries were test entries, please delete", "delete today's snacks", "remove the 1500 entry".
/// Only selects entries; the app always asks before deleting.
public struct DeleteRequest: Equatable, Sendable {
    public var all: Bool
    public var hint: [String]
    public var amount: Decimal?
    /// 0 = today, -1 = yesterday.
    public var dayOffset: Int?
}

public enum DeleteCommand {
    // Not "clear" ("cleared card bill") or "nikalo" ("ATM se 2000 nikale"): those are money entries.
    static let triggers: Set<String> = ["delete", "remove", "erase", "hata", "hatao", "mita", "mitao"]
    static let allWords: Set<String> = ["all", "everything", "sab", "sabhi", "saari", "sari", "saare", "sare"]
    static let filler: Set<String> = Split.filler.union(["entries", "entry", "were", "are", "please", "test", "tests", "testing",
                                                         "dummy", "fake", "sample", "demo", "these", "those", "them", "last",
                                                         "latest", "previous", "one", "today", "todays", "yesterday", "aaj",
                                                         "kal", "wali", "wale", "can", "you", "and", "all", "everything"])

    public static func parse(_ text: String) -> DeleteRequest? {
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard words.contains(where: triggers.contains) else { return nil }
        let day: Int? = words.contains { ["today", "todays", "aaj"].contains($0) } ? 0
            : words.contains { ["yesterday", "yesterdays", "kal"].contains($0) } ? -1 : nil
        let hint = words.filter { w in
            w.count >= 3 && w.first?.isLetter == true && !triggers.contains(w) && !allWords.contains(w) && !filler.contains(w)
        }
        return DeleteRequest(all: words.contains(where: allWords.contains), hint: hint,
                             amount: RuleParser.amount(in: text), dayOffset: day)
    }

    /// Entries the request points at. Nothing specific ("delete that") means the latest entry.
    public static func matches(_ r: DeleteRequest, in entries: [Entry], now: Date = Date(), calendar: Calendar = .current) -> [UUID] {
        let picked = entries.filter { e in
            if let d = r.dayOffset, let day = calendar.date(byAdding: .day, value: d, to: now),
               !calendar.isDate(e.date, inSameDayAs: day) { return false }
            if let a = r.amount, e.amount != a, e.splitTotal != a { return false }
            if !r.hint.isEmpty {
                let words = (e.raw + " " + e.note + " " + e.category + " " + e.person).lowercased()
                    .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                return r.hint.contains { h in words.contains { $0.hasPrefix(h) } }
            }
            return true
        }
        let specific = r.all || r.dayOffset != nil || r.amount != nil || !r.hint.isEmpty
        if specific { return picked.map(\.id) }
        return entries.max { $0.date < $1.date }.map { [$0.id] } ?? []
    }
}
