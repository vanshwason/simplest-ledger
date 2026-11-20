import Foundation

/// "split the outing with 3 people", "3 logo ne contribute kar diya outing ka",
/// "split 1200 dinner with Rahul, Amit and Neha".
public struct SplitRequest: Equatable, Sendable {
    /// Words that point at the expense to split, e.g. ["outing"].
    public var hint: [String]
    /// The bill amount, if the text names it.
    public var amount: Decimal?
    public var names: [String]
    /// People besides you.
    public var others: Int
    /// They already gave you their share, so nobody owes you.
    public var alreadyPaid: Bool
    /// What the others actually paid ("he paid 700"). When set, your share is the bill minus this.
    public var contributed: Decimal?

    public init(hint: [String] = [], amount: Decimal? = nil, names: [String] = [], others: Int = 1, alreadyPaid: Bool = false,
                contributed: Decimal? = nil) {
        self.hint = hint; self.amount = amount; self.names = names; self.others = others; self.alreadyPaid = alreadyPaid
        self.contributed = contributed
    }
}

public enum Split {
    // "share"/"shared" left out on purpose: "200 shared auto" is a normal expense.
    static let triggers: Set<String> = ["split", "splitted", "divide", "divided", "contributed", "contribute", "contribution",
                                        "baant", "baanta", "baanto"]
    static let paid: Set<String> = ["contributed", "contribute", "contribution", "paid", "gave", "diye", "diya", "settled", "already",
                                    "sent", "transferred"]
    static let half: Set<String> = ["half", "aadha", "aadhe", "adha", "adhe"]
    /// Pronouns end a name list: "between roommate, he paid" is one person, not "Roommate" and "He".
    static let pronouns: Set<String> = ["he", "she", "him", "her", "they", "them", "usne", "unhone", "woh", "wo", "vo"]
    /// "paid 700", "gave me ₹700", "700 de diye": the amount someone else put in.
    static let contributionRegex = try! Regex(
        #"(?:paid|gave|contributed|sent|transferred|diye|diya)\s+(?:me\s+|mujhe\s+|back\s+)?(?:₹|rs\.?\s*|inr\s*)?(\d[\d,]*(?:\.\d+)?)|(\d[\d,]*(?:\.\d+)?)\s*(?:₹|rs\.?|rupees|inr)?\s*(?:paid|gave|contributed|sent|transferred|de diye|de diya|diye|diya)\b"#
    ).ignoresCase()
    static let people: Set<String> = ["people", "persons", "person", "friends", "friend", "others", "guys", "log", "logo", "logon", "dost"]
    static let filler: Set<String> = ["the", "a", "an", "of", "with", "between", "among", "and", "me", "my", "us", "it", "that",
                                      "this", "expense", "kharcha", "bill", "wala", "wali", "wale", "ka", "ki", "ke", "ko",
                                      "ne", "kar", "karo", "do", "de", "hai", "ho", "gaya", "they", "who", "have", "has", "is",
                                      "was", "their", "equally", "ways", "way", "rs", "rupees", "inr", "total", "edit", "update",
                                      "change", "please", "mera", "mere", "hum", "sab", "in", "on", "for", "to", "from"]
    static let countRegex = try! Regex(#"(\d+)\s*(people|persons|person|friends|friend|others|guys|log|logo|logon|dost|ways|way|of us)\b"#).ignoresCase()

    /// nil when the text isn't a split request (then it's a normal entry).
    public static func parse(_ text: String) -> SplitRequest? {
        let lower = text.lowercased()
        let words = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        // "roommate ne wifi ka aadha de diya" has no "split" but is one.
        let halfPaid = words.contains(where: half.contains) && words.contains(where: paid.contains)
        guard words.contains(where: triggers.contains) || halfPaid else { return nil }

        var others = 0, rest = lower
        var contributed: Decimal?
        if let m = lower.firstMatch(of: contributionRegex),
           let digits = m.output[1].substring ?? m.output[2].substring {
            contributed = Decimal(string: digits.replacingOccurrences(of: ",", with: ""))
            rest = rest.replacingOccurrences(of: String(m.output[0].substring ?? ""), with: " ")
        }
        for m in lower.matches(of: countRegex) {
            let n = Int(m.output[1].substring ?? "") ?? 0
            let unit = (m.output[2].substring ?? "").lowercased()
            others = max(others, unit.hasPrefix("way") || unit == "of us" ? n - 1 : n)
            rest = rest.replacingOccurrences(of: String(m.output[0].substring ?? ""), with: " ")
        }

        // Names follow "with" / "between" / "among" and stop at the first non-name word.
        var names: [String] = []
        if let i = words.firstIndex(where: { ["with", "between", "among"].contains($0) }) {
            for w in words[(i + 1)...] {
                if ["and", "aur"].contains(w) { continue }
                if w.first?.isNumber == true || people.contains(w) || triggers.contains(w) || paid.contains(w) || filler.contains(w)
                    || pronouns.contains(w) || half.contains(w) { break }
                names.append(w.capitalized)
            }
        }

        let nameSet = Set(names.map { $0.lowercased() })
        let hint = words.filter { w in
            w.count >= 3 && w.first?.isLetter == true && !triggers.contains(w) && !paid.contains(w) && !people.contains(w)
                && !filler.contains(w) && !nameSet.contains(w) && !pronouns.contains(w) && !half.contains(w)
        }
        return SplitRequest(hint: hint, amount: RuleParser.amount(in: rest), names: names,
                            others: max(others, names.count, 1),
                            alreadyPaid: contributed != nil || words.contains(where: paid.contains), contributed: contributed)
    }

    /// The expense the request points at: same amount, else a word match, else the latest expense.
    /// nil when an amount is named but no expense has it: then the text is a new bill to add and split.
    public static func target(for request: SplitRequest, in entries: [Entry]) -> Entry? {
        let expenses = entries.filter { $0.kind == .expense }.sorted { $0.date > $1.date }
        if let a = request.amount { return expenses.first { ($0.splitTotal ?? $0.amount) == a } }
        if let e = expenses.first(where: { e in
            let words = (e.raw + " " + e.note + " " + e.category).lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            return request.hint.contains { h in words.contains { $0.hasPrefix(h) } }
        }) { return e }
        return expenses.first
    }

    /// Your share replaces the expense amount; each other person gets a "Lent" entry unless they already paid.
    public static func apply(_ request: SplitRequest, to target: Entry) -> (updated: Entry, owed: [Entry]) {
        let total = target.splitTotal ?? target.amount ?? 0
        if let paid = request.contributed { // they paid an exact amount; you keep the rest
            var updated = target
            updated.splitTotal = total
            updated.amount = max(total - paid, 0)
            updated.note = "Your share of \(rupees(total)), others paid \(rupees(paid))"
            updated.question = updated.missingInfo()
            return (updated, [])
        }
        let ways = request.others + 1
        var raw = total / Decimal(ways), per = Decimal()
        NSDecimalRound(&per, &raw, 2, .plain)
        var updated = target
        updated.splitTotal = total
        updated.amount = total - per * Decimal(request.others) // you absorb the rounding paisa
        updated.note = "Your share of \(rupees(total)), split \(ways) ways" + (request.alreadyPaid ? ", others paid" : "")
        updated.question = updated.missingInfo()
        guard !request.alreadyPaid else { return (updated, []) }
        let owed = (0..<request.others).map { i -> Entry in
            var e = Entry(date: target.date, raw: "Share of: \(target.raw)", amount: per, kind: .lent, category: "Split",
                          method: target.method, person: i < request.names.count ? request.names[i] : "")
            e.splitOf = target.id
            e.question = e.person.isEmpty ? "Who owes you this share?" : ""
            return e
        }
        return (updated, owed)
    }
}
