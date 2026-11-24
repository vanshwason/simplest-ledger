import Foundation

/// A refund or reversal SMS lowers the purchase it belongs to instead of counting as new money in.
public enum Refund {
    public static let question = "Which purchase was this refund for?"
    static let words = ["refund", "reversed", "reversal"]
    /// Words every bank text shares, so they can't tell purchases apart.
    static let common: Set<String> = ["refund", "refunded", "reversed", "reversal", "credited", "debited", "your", "with",
        "from", "been", "have", "this", "that", "for", "the", "account", "bank", "card", "credit", "debit", "transaction",
        "txn", "upi", "vpa", "failed", "amount", "available", "balance", "bal", "towards", "against", "dear", "customer",
        "info", "ref", "hdfc", "icici", "axis", "kotak", "yes", "idfc", "federal", "canara", "union", "baroda", "india",
        "state", "first", "paytm", "payments", "call", "not", "you", "done", "days", "will", "within", "sms", "block"]

    public static func isRefund(_ e: Entry) -> Bool {
        e.kind == .income && e.amount != nil && words.contains { e.raw.lowercased().contains($0) }
    }

    /// Shop names and long reference numbers: what ties a refund to its purchase.
    static func marks(_ text: String) -> Set<String> {
        Set(text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter {
            ($0.allSatisfy(\.isLetter) && $0.count >= 4 && !common.contains($0)) || ($0.allSatisfy(\.isNumber) && $0.count >= 8)
        })
    }

    /// Expenses from the 60 days before that are at least the refund, newest first.
    public static func candidates(for refund: Entry, in entries: [Entry]) -> [Entry] {
        guard let amount = refund.amount else { return [] }
        let start = refund.date.addingTimeInterval(-60 * 86_400)
        return entries.filter { $0.kind == .expense && $0.id != refund.id && ($0.amount ?? 0) >= amount
            && $0.date >= start && $0.date <= refund.date }
            .sorted { $0.date > $1.date }
    }

    /// The purchase, when it's clear: the only one sharing a shop name or reference, else the only one with the same amount.
    public static func match(for refund: Entry, in entries: [Entry]) -> Entry? {
        let all = candidates(for: refund, in: entries), mine = marks(refund.raw)
        let named = all.filter { !mine.isDisjoint(with: marks($0.raw + " " + $0.note)) }
        let pool = named.isEmpty ? all : named
        if named.count == 1 { return named[0] }
        let same = pool.filter { $0.amount == refund.amount }
        return same.count == 1 ? same[0] : nil
    }

    /// The purchase with the refund taken off and the refund message kept under it.
    public static func apply(_ refund: Entry, to purchase: Entry) -> Entry {
        var p = purchase
        p.amount = max(0, (p.amount ?? 0) - (refund.amount ?? 0))
        p.raw += "\n\nRefund: " + refund.raw
        return p
    }
}
