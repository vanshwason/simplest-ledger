import Foundation

/// Turns the text lines read off a receipt or payment screenshot into a sentence the normal parser
/// understands, e.g. "540 DOMINO'S PIZZA (scanned receipt)". The sentence goes in the text box for
/// you to check before adding.
public enum ReceiptReader {
    static let totalWords = ["grand total", "net total", "total", "net amount", "amount paid", "net payable",
                             "bill amount", "to pay", "payable", "amount due"]
    static let skipLines = ["tax invoice", "invoice", "receipt", "bill", "welcome", "gst", "gstin", "fssai", "thank",
                            "order", "table", "date", "time", "phone", "ph ", "tel", "cashier", "transaction"]
    /// Money looks like "1,250.00", "₹500" or "Rs. 99". Bare long digit runs (phones, IDs) and years are ignored.
    static let money = try! Regex(#"(₹|rs\.?|inr)?\s*(\d{1,3}(?:,\d{2,3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)"#).ignoresCase()

    public static func sentence(from lines: [String]) -> String? {
        guard let total = total(in: lines) else { return nil }
        let amount = NSDecimalNumber(decimal: total).stringValue
        return [amount, merchant(in: lines), "(scanned receipt)"].compactMap { $0 }.joined(separator: " ")
    }

    /// Largest amount on a "total" line; otherwise the largest amount that clearly is money (₹ or paise).
    static func total(in lines: [String]) -> Decimal? {
        let totals = lines.filter { l in totalWords.contains { l.lowercased().contains($0) } }.flatMap { amounts(in: $0, strict: false) }
        return totals.max() ?? lines.flatMap { amounts(in: $0, strict: true) }.max()
    }

    static func amounts(in line: String, strict: Bool) -> [Decimal] {
        line.matches(of: money).compactMap { m -> Decimal? in
            guard let digits = m.output[2].substring.map(String.init) else { return nil }
            let plain = digits.replacingOccurrences(of: ",", with: "")
            let hasSymbol = m.output[1].substring != nil, hasPaise = plain.contains(".")
            if !hasSymbol && !hasPaise && (plain.count >= 7 || strict) { return nil } // IDs, phones; strict wants clear money
            guard let value = Decimal(string: plain), value > 0, value < 10_000_000 else { return nil }
            if !hasSymbol && !hasPaise, (2000...2099).contains(value) { return nil } // a year in a date
            return value
        }
    }

    /// "Paid to Rahul Sharma" on payment screenshots, else the first wordy line at the top (the shop name).
    static func merchant(in lines: [String]) -> String? {
        for l in lines {
            if let r = l.range(of: "paid to ", options: .caseInsensitive) {
                return String(l[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return lines.first { l in
            let letters = l.filter(\.isLetter).count
            let lower = l.lowercased()
            return letters >= 3 && letters * 2 >= l.count && !skipLines.contains { lower.contains($0) }
        }?.trimmingCharacters(in: .whitespaces)
    }
}
