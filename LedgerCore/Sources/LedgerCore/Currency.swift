import Foundation

/// The one currency a ledger is kept in. The app picks it from the phone's region and lets you change it.
/// No conversion: an amount in another currency ("USD 12.99 spent") is left empty so Needs input asks.
public struct Currency {
    public let code: String
    public let symbol: String
    /// "Rs 500", "₹500", "INR 500": an amount in this currency. Balances and limits are skipped by the parser.
    let amountRegex: Regex<AnyRegexOutput>
    /// An amount marked with a different currency.
    let foreignRegex: Regex<AnyRegexOutput>

    /// How amounts are marked in texts and SMS. Other ISO codes work too, via their code and symbol.
    static let marks: [String: (symbol: String, pattern: String)] = [
        "INR": ("₹", #"₹|\brs\.?|\binr"#),
        "USD": ("$", #"\busd|\$"#),
        "EUR": ("€", #"\beur|€"#),
        "GBP": ("£", #"\bgbp|£"#),
    ]

    /// Offered in the app's Currency menu.
    public static let common = ["INR", "USD", "EUR", "GBP", "AED", "AUD", "CAD", "SGD", "JPY"]

    /// Set by the app at launch. INR here keeps the package's tests independent of the machine's region.
    nonisolated(unsafe) public static var current = Currency(code: "INR")

    public init(code: String) {
        let code = code.uppercased()
        self.code = code
        let symbol = Self.marks[code]?.symbol
            ?? Locale(identifier: "en_US@currency=\(code)").currencySymbol ?? code // "A$", "CA$", "¥", "AED"
        self.symbol = symbol
        var own = Self.marks[code]?.pattern
            ?? #"\b"# + code.lowercased() + "|" + NSRegularExpression.escapedPattern(for: symbol.lowercased())
        if symbol.contains("$") { own += #"|\$"# } // Australian, Canadian… banks write a plain "$"
        // Other currencies, except ones sharing our symbol (a plain "$" is ours when we're AUD).
        let others = Self.marks.filter { $0.key != code && !symbol.contains($0.value.symbol) }.map(\.value.pattern)
        amountRegex = try! Regex(#"(?:"# + own + #")\s*(\d[\d,]*(?:\.\d+)?)\s*(k|thousand|lakhs?|lacs?)?\b"#).ignoresCase()
        foreignRegex = try! Regex(#"(?:"# + (others.isEmpty ? "(?!)" : others.joined(separator: "|")) + #")\s*\d"#).ignoresCase()
    }
}

/// 150000 -> "₹1,50,000" (Indian grouping for rupees), "$150,000" otherwise; 1500.5 -> "₹1,500.50".
public func money(_ value: Decimal) -> String {
    let currency = Currency.current
    var v = value, r = Decimal()
    NSDecimalRound(&r, &v, 2, .plain)
    let negative = r < 0
    let parts = NSDecimalNumber(decimal: negative ? -r : r).stringValue.split(separator: ".", maxSplits: 1)
    var int = String(parts[0]), grouped = ""
    let group = currency.code == "INR" ? 2 : 3
    if int.count > 3 {
        grouped = "," + int.suffix(3); int = String(int.dropLast(3))
        while int.count > group { grouped = "," + int.suffix(group) + grouped; int = String(int.dropLast(group)) }
    }
    var frac = parts.count > 1 ? String(parts[1]) : ""
    if frac.count == 1 { frac += "0" }
    let symbol = currency.symbol.last?.isLetter == true ? currency.symbol + " " : currency.symbol // "AED 500"
    return (negative ? "-" : "") + symbol + int + grouped + (frac.isEmpty ? "" : "." + frac)
}
