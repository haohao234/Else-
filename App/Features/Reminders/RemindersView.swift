import SwiftUI
import UserNotifications

// MARK: - 09 提醒通知
//
// 三件事，按重要性排：
//   ① 逾期的排最前，且是**唯一允许出现警示色**的地方（设计上的硬约束）
//   ② 点一下就能标记完成 —— 提醒页的核心动作是"消掉它"，不是"阅读它"
//   ③ 本地通知的状态要看得见：用户开了飞行模式也知道提醒还能不能来（能，因为不走网络）
//
// 这里的"完成"是本地状态（isDone），不是"删除"：做完的事留在已完成里可回查，
// 因为它同时也是"这只猫上次驱虫是什么时候"的线索。

struct RemindersView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var showDone = false

    var body: some View {
        DSScreen(title: "提醒通知", onBack: { dismiss() }) {
            notificationCard
            if store.openReminders.isEmpty {
                emptyState
            } else {
                section(.overdue)
                section(.today)
                section(.thisWeek)
            }
            doneSection
        }
        .onAppear(perform: refreshAuth)
    }

    // MARK: 通知状态

    private var notificationCard: some View {
        DSCard {
            HStack(spacing: DS.Space.m) {
                DSIconTile(systemName: "bell.badge")
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("到期当天提醒你")
                        .font(DS.Typo.rowTitle)
                        .foregroundStyle(DS.ink)
                    Text("本地通知 · 不需要联网 · 不上传任何数据")
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.inkTertiary)
                }
                Spacer(minLength: DS.Space.s)
                Text(NotificationService.statusText(authStatus))
                    .font(DS.Typo.caption)
                    .foregroundStyle(authStatus == .denied ? DS.alert : DS.inkTertiary)
            }
            if authStatus == .notDetermined {
                DSPrimaryButton(title: "开启提醒", height: 44) {
                    NotificationService.requestAuthorization { granted in
                        refreshAuth()
                        if granted {
                            NotificationService.reschedule(reminders: store.data.reminders)
                        }
                    }
                }
            } else if authStatus == .denied {
                Text("系统里关掉了通知。可以到「设置 → 通知 → Elese的猫舍」重新打开；\n关掉也不影响 App 内的提醒列表。")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 分组

    @ViewBuilder
    private func section(_ urgency: ReminderUrgency) -> some View {
        let items = store.reminders(of: urgency)
        if !items.isEmpty {
            VStack(spacing: DS.Space.s) {
                DSSectionHeader(title: "\(urgency.groupTitle) · \(items.count)")
                ForEach(items) { reminder in
                    row(reminder)
                }
            }
        }
    }

    private func row(_ reminder: Reminder) -> some View {
        let overdue = reminder.urgency == .overdue
        return Button {
            store.toggleReminder(id: reminder.id)
            NotificationService.reschedule(reminders: store.data.reminders)
        } label: {
            DSListRow {
                DSIconTile(systemName: reminder.kind.symbol,
                           tint: overdue ? DS.alert : DS.primary,
                           background: overdue ? DS.alertSoft : DS.surfaceSoft)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(reminder.title)
                        .font(DS.Typo.rowTitle)
                        .foregroundStyle(DS.ink)
                        .multilineTextAlignment(.leading)
                    Text(reminder.subtitle)
                        .font(DS.Typo.caption)
                        .foregroundStyle(overdue ? DS.alert : DS.inkTertiary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: DS.Space.s)
                VStack(alignment: .trailing, spacing: DS.Space.xs) {
                    DSStatusChip(text: reminder.dueLabel.text,
                                 tone: reminder.dueLabel.isOverdue ? .alert : .archived)
                    Image(systemName: "circle")
                        .font(.system(size: 17))
                        .foregroundStyle(DS.inkFaint)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: 已完成

    @ViewBuilder
    private var doneSection: some View {
        let done = store.data.reminders.filter { $0.isDone }.sorted { $0.dueDate > $1.dueDate }
        if !done.isEmpty {
            VStack(spacing: DS.Space.s) {
                DSSectionHeader(title: "已完成 · \(done.count)",
                                actionTitle: showDone ? "收起" : "展开",
                                onAction: { showDone.toggle() })
                if showDone {
                    ForEach(done) { reminder in
                        Button {
                            store.toggleReminder(id: reminder.id)
                        } label: {
                            DSListRow {
                                DSIconTile(systemName: "checkmark",
                                           tint: DS.icon,
                                           background: DS.surfaceSoft)
                                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                                    Text(reminder.title)
                                        .font(DS.Typo.rowTitle)
                                        .foregroundStyle(DS.inkTertiary)
                                        .multilineTextAlignment(.leading)
                                    Text(reminder.subtitle)
                                        .font(DS.Typo.caption)
                                        .foregroundStyle(DS.inkFaint)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                                Text(Formatters.monthDay.string(from: reminder.dueDate))
                                    .font(DS.Typo.caption)
                                    .foregroundStyle(DS.inkFaint)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Text("点一下可以撤回「已完成」")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.inkFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, DS.Space.xxs)
                }
            }
        }
    }

    // MARK: 空状态

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer(minLength: DS.Space.xxl * 2)
            DSEmptyState(systemName: "bell",
                         title: "眼下没有待办",
                         message: "疫苗、驱虫、称重、B 超、预产期都会出现在这里\n做完点一下就能划掉",
                         hint: "提醒跟着猫走：在种猫详情里能看到它名下的全部待办")
            Spacer(minLength: 0)
        }
    }

    // MARK: 权限

    private func refreshAuth() {
        NotificationService.authorizationStatus { status in
            authStatus = status
        }
    }
}
