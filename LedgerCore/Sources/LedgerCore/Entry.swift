import Foundation

public enum Kind: String, Codable, CaseIterable, Sendable {
    case expense, income, lent, borrowed
    case repaidToMe = "repaid_to_me"
    case repaidByMe = "repaid_by_me"

    public var label: String {
        switch self {
        case .expense: return "Spent"
        case .income: return "Received"
        case .lent: return "Lent"
        case .borrowed: return "Borrowed"
        case .repaidToMe: return "Got back"
        case .repaidByMe: return "Paid back"
        }
    }

    /// Money coming into your pocket.
    public var isIn: Bool { self == .income || self == .borrowed || self == .repaidToMe }

    /// Kinds that only make sense with another person.
    public var needsPerson: Bool { self == .lent || self == .borrowed || self == .repaidToMe || self == .repaidByMe }
}

public struct Entry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    /// Exactly what you typed.
    public var raw: String
    public var amount: Decimal?
    public var kind: Kind
    public var category: String
    public var method: String
    public var person: String
    public var note: String
    /// Non-empty while the entry needs more input from you.
    public var question: String
    /// Set on an expense you split: the full bill before your share was taken out.
    public var splitTotal: Decimal?
    /// Set on the "they owe you" entries a split creates, pointing at the split expense.
    public var splitOf: UUID?
    /// Trip the entry belongs to, e.g. "Goa". Optional so ledgers saved before trips still load.
    public var trip: String?
    /// Where it came from when not typed: "sms" for the bank SMS automation.
    public var source: String?

    public var needsInput: Bool { !question.isEmpty }

    /// What to show: your words, or the English version when you typed or dictated in another script (e.g. Hindi).
    public var displayText: String {
        let nonLatin = raw.unicodeScalars.contains { $0.properties.isAlphabetic && $0.value >= 0x250 }
        return nonLatin && !note.isEmpty ? note : raw
    }

    public init(id: UUID = UUID(), date: Date, raw: String, amount: Decimal?, kind: Kind = .expense,
                category: String = "Other", method: String = "", person: String = "", note: String = "",
                question: String = "") {
        self.id = id; self.date = date; self.raw = raw; self.amount = amount; self.kind = kind
        self.category = category; self.method = method; self.person = person; self.note = note
        self.question = question
    }

    /// What we still need to know, or "" when the entry is complete.
    /// `checkCategory` is off after you save by hand, so a deliberate "Other" stays.
    public func missingInfo(checkCategory: Bool = true) -> String {
        guard let amount, amount > 0 else { return "How much was it?" }
        if kind.needsPerson && person.isEmpty { return "Who was this with?" }
        if checkCategory && kind == .expense && category == "Other" { return "What was this spent on?" }
        return ""
    }
}

/// Indian-style rupees: 150000 -> "₹1,50,000", 1500.5 -> "₹1,500.50".
public func rupees(_ value: Decimal) -> String {
    var v = value, r = Decimal()
    NSDecimalRound(&r, &v, 2, .plain)
    let negative = r < 0
    let parts = NSDecimalNumber(decimal: negative ? -r : r).stringValue.split(separator: ".", maxSplits: 1)
    var int = String(parts[0]), grouped = ""
    if int.count > 3 {
        grouped = "," + int.suffix(3); int = String(int.dropLast(3))
        while int.count > 2 { grouped = "," + int.suffix(2) + grouped; int = String(int.dropLast(2)) }
    }
    var frac = parts.count > 1 ? String(parts[1]) : ""
    if frac.count == 1 { frac += "0" }
    return (negative ? "-" : "") + "₹" + int + grouped + (frac.isEmpty ? "" : "." + frac)
}
