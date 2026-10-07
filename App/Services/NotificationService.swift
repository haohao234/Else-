import Foundation
import UserNotifications

// MARK: - 本地通知
//
// 这个 App 是**完全离线**的：提醒能力全部来自本地通知（UNUserNotificationCenter），
// 不需要服务器、不需要推送证书、不需要任何账号。这也是"数据只在本机"这句承诺的一部分。
//
// 排程策略：**每次全清重排**。
// 为什么不做增量：增量要维护"哪些已排、哪些要撤、哪些改了时间"三份状态，
// 而本地通知的数量在几十条量级 —— 全清重排几毫秒就完成，却消掉了一整类同步 bug。
// 判断依据很干脆：**当"省下的开销"远小于"要维护的状态"时，就别省。**

enum NotificationService {

    /// 到期日当天的提醒时刻。用 9 点而不是"截止时刻"：
    /// 提醒的语义是"今天该做这件事"，而不是"到这一秒才告诉你"。
    private static let hourOfDay = 9

    static func authorizationStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            DispatchQueue.main.async { completion(status) }
        }
    }

    static func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                DispatchQueue.main.async { completion(granted) }
            }
    }

    /// 按当前未完成的提醒重排全部本地通知。返回实际排出去的条数。
    @discardableResult
    static func reschedule(reminders: [Reminder], now: Date = Date()) -> Int {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var scheduled = 0

        for reminder in reminders where !reminder.isDone {
            // 已经过期的排不了（系统会立刻投递或直接丢弃），跳过 —— 它们由 App 内的"已逾期"分组负责。
            guard cal.startOfDay(for: reminder.dueDate) >= today else { continue }

            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.detail
            content.sound = .default

            var comps = cal.dateComponents([.year, .month, .day], from: reminder.dueDate)
            comps.hour = hourOfDay
            comps.minute = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: reminder.id.uuidString,
                                                content: content,
                                                trigger: trigger)
            center.add(request) { _ in }
            scheduled += 1
        }
        return scheduled
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// 给界面用的一句话状态文案。
    static func statusText(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized, .provisional, .ephemeral: return "已开启"
        case .denied: return "已关闭"
        case .notDetermined: return "未开启"
        @unknown default: return "未知"
        }
    }
}
