import Foundation

/// Bank texts that mention money but aren't a transaction that happened: OTPs, failed or scheduled payments,
/// offers, statements, payment requests, card-bill receipts (counting those would double-count your spends).
public enum MessageFilter {
    static let otp = try! Regex(#"otp\s*(?:is|for|:)?\s*\d{4,8}|\d{4,8}\s+is\s+(?:the|your)\s+otp"#).ignoresCase()

    /// Why the message should be skipped, or nil if it's a real transaction.
    public static func ignoreReason(_ text: String) -> String? {
        let t = text.lowercased()
        func any(_ phrases: [String]) -> Bool { phrases.contains { t.contains($0) } }
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
