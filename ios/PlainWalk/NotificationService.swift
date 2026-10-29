import Foundation
import UserNotifications

struct NotificationService {
    static func configure(_ config: [String: Any]) async throws {
        let morning = config["morningNotification"] as? Bool ?? false
        let weekly = config["weeklyNotification"] as? Bool ?? false
        let interruption = config["interruptionNotification"] as? Bool ?? false
        let center = UNUserNotificationCenter.current()
        if morning || weekly || interruption {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else { throw NativeError.message("通知が許可されていません。iOS の設定を確認してください。") }
        }
        center.removePendingNotificationRequests(withIdentifiers: ["plainwalk-morning", "plainwalk-weekly"])
        if morning {
            let parts = (config["morningTime"] as? String ?? "07:45").split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { throw NativeError.message("通知の時刻が不正です。") }
            let content = UNMutableNotificationContent(); content.title = "今日は、どの道を歩こう。"; content.body = "いつもの道の、その一本となりへ。"; content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: parts[0], minute: parts[1]), repeats: true)
            try await center.add(UNNotificationRequest(identifier: "plainwalk-morning", content: content, trigger: trigger))
        }
        if weekly {
            let content = UNMutableNotificationContent(); content.title = "今週の白地図"; content.body = "今週のさんぽを、振り返ってみませんか。"; content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 20, minute: 0, weekday: 1), repeats: true)
            try await center.add(UNNotificationRequest(identifier: "plainwalk-weekly", content: content, trigger: trigger))
        }
        UserDefaults.standard.set(interruption, forKey: "plainwalk.interruptionReminder")
    }
    static func interruption() {
        guard UserDefaults.standard.bool(forKey: "plainwalk.interruptionReminder") else { return }
        let content = UNMutableNotificationContent(); content.title = "さんぽの記録が途切れています"; content.body = "位置情報の許可や端末の状態を確認してください。"; content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "plainwalk-interruption", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }
}
