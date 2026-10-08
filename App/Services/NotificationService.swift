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
    ///
    /// ⚠️ 提醒的时刻**由每条提醒自己决定**（用户在表单里能设到几点几分）。
    /// 早先这里写死 9:00 —— 那是个"实现里的假设"，被当成产品决定用了很久；
    /// 用户一问"具体多少点"就露馅了。**凡是时间/金额这类用户会在意的东西，
    /// 别藏在代码里当常量。**
    @discardableResult
    static func reschedule(reminders: [Reminder], now: Date = Date()) -> Int {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let cal = Calendar.current
        var scheduled = 0

        for reminder in reminders where !reminder.isDone {
            // ⚠️ 判据是**完整时刻**，不是"日期是不是今天以后"：
            // 今天 09:00 而现在已经 15:00 —— 那条通知不会再响了，排进去只会白排
            // （系统的行为是立刻投递或直接丢弃，两种都不该发生）。
            // 它仍然会出现在 App 内的「今天」分组里，因为该做的事没做还是没做。
            guard reminder.dueDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.detail
            content.sound = .default

            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute],
                                           from: reminder.dueDate)
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
