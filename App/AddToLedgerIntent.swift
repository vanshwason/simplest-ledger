import AppIntents
import LedgerCore

/// "Add to Ledger" in the Shortcuts app. iOS doesn't let apps read SMS, but a Shortcuts automation
/// ("when I get a message containing debited") can pass the message here. Runs without opening the app.
struct AddToLedgerIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Ledger"
    static let openAppWhenRun = false

    @Parameter(title: "Message") var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if let reason = MessageFilter.ignoreReason(text) {
            return .result(dialog: "Skipped: this looks like \(reason).")
        }
        guard let entry = await Store.shared.addFromMessage(text) else {
            return .result(dialog: "Already added, taken off its purchase as a refund, or empty.")
        }
        if entry.needsInput { Alerts.needsInput(entry) }
        let amount = entry.amount.map(money) ?? "an amount to check"
        return .result(dialog: "Added \(amount) · \(entry.category)\(entry.needsInput ? " (needs input)" : "")")
    }
}

/// Makes the action show up in Shortcuts and Siri without any setup.
struct LedgerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddToLedgerIntent(), phrases: ["Add to \(.applicationName)"],
                    shortTitle: "Add to Ledger", systemImageName: "plus.circle")
    }
}
