import Foundation

/// Shop names inside bank texts ("SWIGGY", "netflix"), so a fix you make once carries over and repeat payments show up.
public enum Shop {
    /// Bank-text words that aren't shops, on top of the refund list.
    static let boilerplate: Set<String> = ["sent", "paid", "spent", "using", "made", "purchase", "merchant", "limit", "avbl",
        "dated", "date", "time", "rupees", "alert", "alerts", "report", "fraud", "netbanking", "mobile", "help", "helpline",
        "care", "dial", "reply", "message", "ending", "linked", "value", "mandate", "autopay", "onwards", "immediately",
        "unauthorised", "unauthorized", "contact", "visit", "issue", "issued", "number", "total", "thank", "thanks", "team",
        "regards", "debit", "withdrawn", "withdrawal", "deducted", "charged", "transferred", "payment", "received", "update",
        "hsbc", "citi", "indusind", "sbicard", "rbl", "bandhan", "amex", "visa", "mastercard", "rupay", "wallet", "sbiinb"]

    /// Letter-only words that can name a shop. Reference numbers are left out: they never repeat.
    public static func words(_ text: String) -> Set<String> {
        Refund.marks(text).filter { $0.allSatisfy(\.isLetter) && !boilerplate.contains($0) }
    }

    /// Words seen on entries of 3 or more categories are part of the bank's wording, not a shop.
    static func generic(in entries: [Entry]) -> Set<String> {
        var cats: [String: Set<String>] = [:]
        for e in entries { for w in words(e.raw) { cats[w, default: []].insert(e.category) } }
        return Set(cats.filter { $0.value.count >= 3 }.keys)
    }

    /// The category you last gave this kind of entry from the same shop, if any.
    public static func lastCategory(for entry: Entry, in entries: [Entry]) -> String? {
        let mine = words(entry.raw).subtracting(generic(in: entries))
        guard !mine.isEmpty else { return nil }
        return entries.filter { $0.id != entry.id && $0.kind == entry.kind && !$0.category.isEmpty && $0.category != "Other"
                                && !mine.isDisjoint(with: words($0.raw)) }
            .max { $0.date < $1.date }?.category
    }
}

/// Payments that come back every month: subscriptions, rent, SIPs, EMIs.
public enum Recurring {
    public struct Item: Identifiable, Equatable, Sendable {
        public let name: String, amount: Decimal, next: Date
        public var id: String { name }
    }

    /// The same shop at least 3 times, 25–35 days apart, each amount within 10% of the latest. Newest amount, next date guessed.
    public static func find(in entries: [Entry]) -> [Item] {
        let spends = entries.filter { $0.kind == .expense && ($0.amount ?? 0) > 0 }
        var byWord: [String: [Entry]] = [:]
        for e in spends { for w in words(e) { byWord[w, default: []].append(e) } }
        var seen = Set<UUID>(), items: [Item] = []
        // The rarest word first, so "netflix" names the payment rather than the bank's name in the same text.
        for (word, list) in byWord.sorted(by: { ($0.value.count, $0.key) < ($1.value.count, $1.key) }) {
            let last = Array(list.sorted { $0.date < $1.date }.suffix(3))
            guard last.count == 3, let latest = last.last, let amount = latest.amount, !seen.contains(latest.id) else { continue }
            let gaps = zip(last, last.dropFirst()).map { $1.date.timeIntervalSince($0.date) / 86_400 }
            guard gaps.allSatisfy({ (25...35).contains($0) }),
                  last.allSatisfy({ abs(($0.amount ?? 0) - amount) <= amount / 10 }) else { continue }
            seen.insert(latest.id)
            let gap = gaps.reduce(0, +) / Double(gaps.count)
            items.append(Item(name: word.prefix(1).uppercased() + word.dropFirst(), amount: amount,
                              next: latest.date.addingTimeInterval(gap * 86_400)))
        }
        return items.sorted { $0.next < $1.next }
    }

    /// Typed entries ("netflix 649") have no bank wording, so their words count too.
    static func words(_ e: Entry) -> Set<String> { Shop.words(e.raw + " " + e.note) }
}
