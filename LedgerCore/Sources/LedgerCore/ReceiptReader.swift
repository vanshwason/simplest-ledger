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

    /// 1. Paid in cash: cash given minus change is exactly the final bill (rounding included).
    /// 2. A "total" line (or the line right after it, as OCR often splits them), preferring grand/rounded/net totals.
    /// 3. The largest amount that clearly is money (₹ or paise).
    static func total(in lines: [String]) -> Decimal? {
        let lower = lines.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func near(_ i: Int, zeroOK: Bool = false) -> Decimal? {
            if let a = amounts(in: lines[i], strict: false, zeroOK: zeroOK).last { return a }
            return i + 1 < lines.count ? amounts(in: lines[i + 1], strict: false, zeroOK: zeroOK).first : nil
        }
        func isCash(_ l: String) -> Bool {
            l.hasPrefix("cash") && !l.hasPrefix("cashier") && !l.contains("cash bill") && !l.contains("cash sales")
        }
        if let c = lower.lastIndex(where: { $0.hasPrefix("change") }), let change = near(c, zeroOK: true),
           let cash = (0..<c).reversed().lazy.filter({ isCash(lower[$0]) }).compactMap({ near($0) }).first,
           cash - change > 0 {
            return cash - change
        }
        let skip = ["sub", "excl", "qty", "gst", "tax", "discount", "saving"]
        let totalLines = lower.indices.filter { i in
            totalWords.contains { lower[i].contains($0) } && !skip.contains { lower[i].contains($0) }
        }
        let preferred = totalLines.filter { i in ["round", "grand", "net", "payable", "inclusive", "paid"].contains { lower[i].contains($0) } }
        if let i = preferred.last(where: { near($0) != nil }) { return near(i) }
        if let best = totalLines.compactMap({ near($0) }).max() { return best }
        return lines.flatMap { amounts(in: $0, strict: true) }.max()
    }

    static func amounts(in line: String, strict: Bool, zeroOK: Bool = false) -> [Decimal] {
        line.matches(of: money).compactMap { m -> Decimal? in
            guard let digits = m.output[2].substring.map(String.init) else { return nil }
            let plain = digits.replacingOccurrences(of: ",", with: "")
            let hasSymbol = m.output[1].substring != nil, hasPaise = plain.contains(".")
            if !hasSymbol && !hasPaise && (plain.count >= 7 || strict) { return nil } // IDs, phones; strict wants clear money
            guard let value = Decimal(string: plain), value > 0 || (zeroOK && value == 0), value < 10_000_000 else { return nil }
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
        // A line that names a business beats the first line (receipts sometimes print the customer's name on top).
        let business = ["sdn", "enterprise", "trading", "pvt", "ltd", "limited", "store", "mart", "restaurant", "cafe",
                        "hotel", "foods", "traders", "pharmacy", "medical", "petroleum", "fuel"]
        if let named = lines.prefix(6).first(where: { l in business.contains { l.lowercased().contains($0) } }) {
            return named.trimmingCharacters(in: .whitespaces)
        }
        return lines.first { l in
            let letters = l.filter(\.isLetter).count
            let lower = l.lowercased()
            return letters >= 3 && letters * 2 >= l.count && !skipLines.contains { lower.contains($0) }
        }?.trimmingCharacters(in: .whitespaces)
    }
}
