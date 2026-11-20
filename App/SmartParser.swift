import Foundation
import FoundationModels
import LedgerCore

@Generable
struct AIEntry {
    @Guide(description: "Amount in Indian rupees as a plain number. 0 if the text gives no amount.")
    var amount: Double
    @Guide(description: "Type of transaction from the writer's point of view",
           .anyOf(["expense", "income", "lent", "borrowed", "repaid_to_me", "repaid_by_me"]))
    var kind: String
    // Keep in sync with RuleParser.categoryNames.
    @Guide(description: "Spending category. Dining Out = eating or drinking at a place; Food Delivery = Swiggy, Zomato or ordered in; Groceries = food to cook at home; Utilities = electricity, wifi, water, gas, phone recharge; Online Shopping = Amazon, Flipkart and similar.",
           .anyOf(["Food Delivery", "Groceries", "Dining Out", "Utilities", "Rent", "Transport", "Online Shopping",
                   "Shopping", "Subscriptions", "Entertainment", "Health", "Personal Care", "Travel", "Education",
                   "EMI & Insurance", "Salary", "Gift", "Loan", "Income", "Other"]))
    var category: String
    @Guide(description: "How it was paid",
           .anyOf(["Credit Card", "Debit Card", "UPI", "Cash", "Bank Transfer", "Card", "Unknown"]))
    var method: String
    @Guide(description: "First name of the other person when money was lent, borrowed or repaid. Empty otherwise.")
    var person: String
    @Guide(description: "A short English note, for example 'snacks' or 'cab to office'.")
    var note: String
    @Guide(description: "The whole input rewritten as one short plain-English sentence, e.g. 'Spent 1500 on snacks via UPI'.")
    var english: String
}

/// Rules first (instant, offline), then Apple's on-device model refines when it is available.
enum SmartParser {
    static func parse(_ text: String) async -> Entry {
        var entry = RuleParser.parse(text)
        if SystemLanguageModel.default.isAvailable, let ai = try? await ask(text) {
            if entry.amount == nil, ai.amount > 0 { entry.amount = Decimal(string: String(ai.amount)) }
            entry.kind = Kind(rawValue: ai.kind) ?? entry.kind
            if ai.category != "Other" || entry.category == "Other" { entry.category = ai.category }
            if entry.method.isEmpty, ai.method != "Unknown" { entry.method = ai.method }
            if !ai.person.isEmpty { entry.person = ai.person }
            entry.note = ai.note
            // Hindi typed or dictated: keep your words in `raw`, show this English sentence instead.
            if entry.displayText == entry.raw, !ai.english.isEmpty,
               text.unicodeScalars.contains(where: { $0.properties.isAlphabetic && $0.value >= 0x250 }) {
                entry.note = ai.english
            }
        }
        entry.question = entry.missingInfo()
        return entry
    }

    private static func ask(_ text: String) async throws -> AIEntry {
        let session = LanguageModelSession(instructions: """
            You read one line from a personal money ledger kept in India. The line may be in English, Hindi or \
            Hinglish. Extract the single transaction it describes. Always write the note and names in English.
            """)
        return try await session.respond(to: text, generating: AIEntry.self).content
    }
}
