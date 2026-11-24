import UserNotifications
import LedgerCore

/// A local notification (no server) when a bank SMS lands in Needs input. Tapping it opens that entry;
/// long-pressing it gives a reply box ("groceries", "lent to Rahul") that fills the entry in without opening the app.
final class Alerts: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Alerts()
    static let category = "needs-input", reply = "reply"

    /// At launch, so a tap or reply that cold-starts the app still reaches us.
    static func listen() {
        let center = UNUserNotificationCenter.current()
        center.delegate = shared
        let action = UNTextInputNotificationAction(identifier: reply, title: "Tell More", options: [],
                                                   textInputButtonTitle: "Save", textInputPlaceholder: "e.g. groceries, or lent to Rahul")
        center.setNotificationCategories([UNNotificationCategory(identifier: category, actions: [action], intentIdentifiers: [])])
    }

    /// Asks once; iOS remembers the answer, and Settings → Notifications turns it off.
    static func ask() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func needsInput(_ entry: Entry) {
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
        if let text = (response as? UNTextInputNotificationResponse)?.userText {
            await Store.shared.answer(id, with: text)
        } else {
            await MainActor.run { Store.shared.openEntry = id }
        }
    }
}
