import UserNotifications
import LedgerCore

/// A local notification (no server) when a bank SMS lands in Needs input. Tapping it opens that entry;
/// long-pressing it gives your top categories, Not an expense, and a reply box ("groceries", "lent to Rahul")
/// that fill the entry in without opening the app.
final class Alerts: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Alerts()
    static let category = "needs-input", reply = "reply", notExpense = "not-expense", pick = "category:"

    /// At launch, so a tap or reply that cold-starts the app still reaches us.
    static func listen() {
        UNUserNotificationCenter.current().delegate = shared
        setButtons(["Food Delivery", "Groceries"])
    }

    /// Notification buttons are registered ahead of time, so they're refreshed with your current top categories.
    static func setButtons(_ categories: [String]) {
        let text = UNTextInputNotificationAction(identifier: reply, title: "Tell More", options: [],
                                                 textInputButtonTitle: "Save", textInputPlaceholder: "e.g. groceries, or lent to Rahul")
        let picks = categories.map { UNNotificationAction(identifier: pick + $0, title: $0, options: []) }
        let drop = UNNotificationAction(identifier: notExpense, title: "Not an expense", options: [.destructive])
        UNUserNotificationCenter.current().setNotificationCategories(
            [UNNotificationCategory(identifier: category, actions: picks + [text, drop], intentIdentifiers: [])])
    }

    /// Asks once; iOS remembers the answer, and Settings → Notifications turns it off.
    static func ask() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func needsInput(_ entry: Entry, buttons: [String]) {
        setButtons(buttons)
        let content = UNMutableNotificationContent()
        content.title = "\(entry.amount.map(money) ?? "SMS") needs input"
        content.body = entry.question
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo = ["id": entry.id.uuidString]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: entry.id.uuidString, content: content, trigger: nil))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = (response.notification.request.content.userInfo["id"] as? String).flatMap(UUID.init) else { return }
        let action = response.actionIdentifier
        if let text = (response as? UNTextInputNotificationResponse)?.userText {
            await Store.shared.answer(id, with: text)
        } else if action.hasPrefix(Alerts.pick) {
            await Store.shared.setCategory(id, to: String(action.dropFirst(Alerts.pick.count)))
        } else if action == Alerts.notExpense {
            await Store.shared.delete(ids: [id])
        } else {
            await MainActor.run { Store.shared.openEntry = id }
            return
        }
        await Store.shared.finishBackup()
    }
}
