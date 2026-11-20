import Foundation

/// Bank texts that mention money but aren't a transaction that happened: OTPs, failed or scheduled payments,
/// offers, statements, payment requests, card-bill receipts (counting those would double-count your spends).
public enum MessageFilter {
    static let otp = try! Regex(#"otp\s*(?:is|for|:)?\s*\d{4,8}|\d{4,8}\s+is\s+(?:the|your)\s+otp"#).ignoresCase()

    static let moneyVerbs: Set<String> = ["debited", "credited", "spent", "paid", "sent", "received", "withdrawn", "deducted",
                                          "debit", "credit", "dr", "cr", "refund", "reversed", "txn", "transaction", "purchase",
                                          "payment", "withdrawal", "withdraw", "charged", "transferred", "trf"]
    static let bankMarks = ["a/c", "acct", "account", "upi", "card", "vpa", "neft", "imps", "atm"]

    /// A bank or payment message: an amount, a money verb, and a currency or bank marker. Lets one broad
    /// automation ("message contains Rs") pass everything while chats like "see yours at 5" are dropped.
    public static func looksLikeTransaction(_ text: String) -> Bool {
        let t = text.lowercased()
        let words = Set(t.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let hasAmount = RuleParser.amount(in: text) != nil || t.contains(RuleParser.foreignRegex) // "USD 12.99 spent"
        guard hasAmount, !words.isDisjoint(with: moneyVerbs) else { return false }
        return t.contains(RuleParser.currencyRegex) || bankMarks.contains { t.contains($0) }
    }

    /// Why the message should be skipped, or nil if it's a real transaction.
    public static func ignoreReason(_ text: String) -> String? {
        let t = text.lowercased()
        func any(_ phrases: [String]) -> Bool { phrases.contains { t.contains($0) } }
        if !looksLikeTransaction(text) { return "a normal message, not a bank transaction" }
        if t.contains(otp) { return "an OTP" }
        if any(["has failed", "was declined", "insufficient"]) { return "a failed payment" }
        if any(["will be", "to be credited", "to be debited", "scheduled", "pre-debit", "e-mandate", "if debited"]) {
            return "a payment that hasn't happened yet"
        }
        if any(["requested money", "has requested", "collect request"]) { return "a payment request" }
        if any(["eligible", "pre-approved", "apply now", "offer", "congratulations"]) { return "an offer" }
        if any(["amt due", "amount due", "statement"]) { return "a card statement" }
        if any(["received towards", "payment towards your"]) { return "a card bill payment (your spends are already counted)" }
        return nil
    }
}
