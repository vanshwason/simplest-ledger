import Foundation

/// Offline keyword parser. Always runs; the on-device AI (in the app) refines its result.
public enum RuleParser {
    /// First match wins, so delivery apps come before dish names ("pizza from zomato" is delivery).
    public static let categories: [(name: String, emoji: String, words: [String])] = [
        ("Food Delivery", "🛵", ["swiggy", "zomato", "eatsure", "ordered", "delivery"]),
        ("Groceries", "🛒", ["grocer", "vegetable", "sabzi", "milk", "doodh", "blinkit", "zepto", "bigbasket", "instamart",
                            "dmart", "fruit", "ration", "atta"]),
        ("Dining Out", "🍽️", ["restaurant", "cafe", "dinner", "lunch", "breakfast", "dosa", "idli", "chai", "tea", "coffee",
                              "pizza", "burger", "biryani", "samosa", "snack", "juice", "food", "khana", "starbucks",
                              "mcdonald", "kfc", "dhaba", "momos", "maggi", "icecream", "sweets", "mithai"]),
        ("Utilities", "💡", ["electricity", "bijli", "wifi", "internet", "broadband", "water", "gas", "cylinder", "recharge",
                            "dth", "postpaid", "airtel", "jio", "bill"]),
        ("Rent", "🏠", ["rent", "kiraya", "maintenance"]),
        ("ATM Cash", "🏧", ["atm", "wdl", "withdrawal", "withdrawn"]),
        ("Transport", "🚕", ["uber", "ola", "rapido", "auto", "cab", "taxi", "metro", "bus", "petrol", "diesel", "fuel",
                            "parking", "toll", "fastag"]),
        ("Online Shopping", "📦", ["amazon", "flipkart", "myntra", "meesho", "ajio", "nykaa", "online"]),
        ("Shopping", "🛍️", ["clothes", "shoes", "shirt", "jeans", "shopping", "mall"]),
        ("Subscriptions", "📺", ["netflix", "spotify", "prime", "hotstar", "youtube", "icloud", "chatgpt", "subscription"]),
        ("Entertainment", "🎬", ["movie", "game", "party", "concert", "outing", "pvr", "bookmyshow"]),
        ("Health", "💊", ["medicine", "dawai", "doctor", "hospital", "pharmacy", "chemist", "apollo", "gym"]),
        ("Personal Care", "💇", ["salon", "haircut", "parlour", "spa", "grooming"]),
        ("Travel", "✈️", ["flight", "hotel", "train", "irctc", "trip", "travel", "makemytrip"]),
        ("Education", "📚", ["course", "book", "fees", "tuition", "school", "college"]),
        ("EMI & Insurance", "🏦", ["emi", "insurance", "premium"]),
        ("Salary", "💼", ["salary", "paycheck", "stipend"]),
        ("Gift", "🎁", ["gift"]),
    ]
    static let extraEmoji = ["Loan": "🤝", "Income": "💰", "Split": "👥", "Other": "🏷️",
                             "Food": "🍽️", "Bills": "🧾"] // last two: entries saved before categories were split up
    public static var categoryNames: [String] { categories.map(\.name) + ["Loan", "Income", "Split", "Other"] }

    public static func emoji(for category: String) -> String {
        categories.first { $0.name == category }?.emoji ?? extraEmoji[category] ?? "🏷️"
    }

    /// Credit and Debit Card are decided in `parse` (they need "card" too: SMS say "has a debit" or "credited").
    public static let methods: [(name: String, words: [String])] = [
        ("UPI", ["upi", "vpa", "gpay", "googlepay", "phonepe", "paytm", "bhim"]),
        ("Cash", ["cash"]),
        ("Bank Transfer", ["neft", "imps", "rtgs"]), // plain "bank" is in every bank SMS; "bank transfer" is handled in parse
        ("Card", ["card"]),
    ]

    static let stopWords: Set<String> = ["me", "my", "the", "a", "an", "via", "through", "using", "by", "on", "for",
                                         "of", "some", "rs", "rupees", "inr", "card", "credit", "debit", "upi", "cash",
                                         "bank", "back", "him", "her", "them", "his", "account", "today", "yesterday"]

    static let amountRegex = try! Regex(#"(\d[\d,]*(?:\.\d+)?)\s*(k|thousand|lakhs?|lacs?)?\b"#).ignoresCase()

    public static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> Entry {
        let lower = text.lowercased()
        let words = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        func has(_ list: [String]) -> Bool { words.contains { list.contains($0) } }
        // Bank SMS shorthand ("A/c XX12 Dr Rs 500", "Cr Rs 1,000") only counts in bank-style text.
        let bankText = lower.contains("a/c") || lower.contains("acct") || lower.contains("account")

        var kind: Kind
        if has(["returned", "repaid", "wapas", "back"]) {
            kind = has(["from", "got", "received"]) ? .repaidToMe : has(["to"]) ? .repaidByMe : .repaidToMe
        } else if has(["lent", "lend", "loaned"]) {
            kind = .lent
        } else if has(["borrowed", "borrow"]) {
            kind = .borrowed
        } else if has(["debited", "spent", "deducted", "withdrawn"]) || (bankText && has(["dr"])) {
            kind = .expense // bank SMS often says "debited from you … credited to them"
        } else if has(["received", "got", "salary", "income", "credited", "earned", "refund", "refunded", "cashback",
                       "reversed", "reversal"]) || (bankText && has(["cr"])) {
            kind = .income
        } else {
            kind = .expense
        }

        var category = categories.first { c in words.contains { w in c.words.contains { w.hasPrefix($0) } } }?.name ?? "Other"
        if kind.needsPerson { category = "Loan" }
        if kind == .income && category == "Other" { category = "Income" }

        let method = has(["cc"]) || (has(["credit"]) && has(["card"])) ? "Credit Card"
            : has(["debit"]) && has(["card"]) ? "Debit Card"
            : has(["bank"]) && has(["transfer"]) ? "Bank Transfer"
            : methods.first { m in has(m.words) }?.name
            ?? (lower.contains(#/@[a-z]{2,}(?![a-z.])/#) ? "UPI" : "") // a UPI handle like test@ybl, not an email

        var person = ""
        if kind.needsPerson, let i = words.firstIndex(where: { ["to", "from", "with"].contains($0) }) {
            person = words[(i + 1)...].first { !stopWords.contains($0) && !($0.first?.isNumber ?? true) }?.capitalized ?? ""
        }

        let date = has(["yesterday"]) ? calendar.date(byAdding: .day, value: -1, to: now) ?? now : now
        var entry = Entry(date: date, raw: text, amount: amount(in: text), kind: kind,
                          category: category, method: method, person: person)
        entry.question = entry.missingInfo()
        return entry
    }

    static var currencyRegex: Regex<AnyRegexOutput> { Currency.current.amountRegex }

    /// The amount in the text. An amount marked with the ledger's currency (₹/Rs/INR for rupees) wins, skipping balances and limits, so a bank SMS like
    /// "Rs 500 debited from A/c XX1234 … Avl Bal Rs 25,340" gives 500. Otherwise the largest number, so
    /// "2 samosa 40" gives 40. Understands 5k, 1.5 lakh, 1,500.
    public static func amount(in text: String) -> Decimal? {
        let lower = text.lowercased()
        let marked = lower.matches(of: currencyRegex).filter { m in
            let before = lower[..<m.range.lowerBound].suffix(14)
            return !before.contains("bal") && !before.contains("limit") && !before.contains("lmt")
        }.compactMap { value(m: $0.output[1].substring, unit: $0.output[2].substring) }
        if let first = marked.first { return first }
        // "USD 12.99 spent…" in a rupee ledger: not our currency; leave it empty so Needs input asks.
        if lower.contains(foreignRegex) { return nil }
        return lower.matches(of: amountRegex).compactMap { m -> Decimal? in
            let digits = m.output[1].substring ?? ""
            // Skip account masks (XX1234, *4821) and long IDs, phone and reference numbers.
            if let prev = lower[..<m.range.lowerBound].last, prev.isLetter || prev == "*" { return nil }
            if !digits.contains("."), digits.filter(\.isNumber).count >= 7 { return nil }
            return value(m: digits, unit: m.output[2].substring)
        }.max()
    }

    public static var foreignRegex: Regex<AnyRegexOutput> { Currency.current.foreignRegex }

    static func value(m digits: Substring?, unit: Substring?) -> Decimal? {
        // "12,50" is a decimal comma (euro style): no thousands grouping ends in two digits.
        let euro = digits?.wholeMatch(of: #/\d{1,3},\d{2}/#) != nil
        guard let digits, let value = Decimal(string: euro ? digits.replacingOccurrences(of: ",", with: ".")
                                                          : digits.replacingOccurrences(of: ",", with: "")) else { return nil }
        switch unit?.lowercased() {
        case "k"?, "thousand"?: return value * 1000
        case let s? where s.hasPrefix("lakh") || s.hasPrefix("lac"): return value * 100_000
        default: return value
        }
    }
}
