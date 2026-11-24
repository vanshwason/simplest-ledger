import UserNotifications
import LedgerCore

/// A local notification (no server) when a bank SMS lands in Needs input. Tapping it opens that entry.
final class Alerts: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Alerts()

    /// At launch, so a tap that cold-starts the app still reaches us.
    static func listen() { UNUserNotificationCenter.current().delegate = shared }

    /// Asks once; iOS remembers the answer, and Settings → Notifications turns it off.
    static func ask() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func needsInput(_ entry: Entry) {
        let content = UNMutableNotificationContent()
        content.title = "\(entry.amount.map(money) ?? "SMS") needs input"
        content.body = entry.question
        content.sound = .default
        content.userInfo = ["id": entry.id.uuidString]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: entry.id.uuidString, content: content, trigger: nil))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = (response.notification.request.content.userInfo["id"] as? String).flatMap(UUID.init) else { return }
        await MainActor.run { Store.shared.openEntry = id }
    }
}
