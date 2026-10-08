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
    @EnvironmentObject private var nav: AppNav
    @Environment(\.dismiss) private var dismiss

    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var showDone = false

    var body: some View {
        DSScreen(title: "提醒通知",
                 onBack: { dismiss() },
                 trailing: AnyView(addLink)) {
            notificationCard
            if store.openReminders.isEmpty {
                emptyState
            } else {
                HStack(spacing: DS.Space.xxs) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 10))
                    Text("点一下 = 完成 · 长按 = 改日期或删除")
                        .font(.system(size: 11))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(DS.inkFaint)
                .padding(.horizontal, DS.Space.xxs)
                section(.overdue)
                section(.today)
                section(.thisWeek)
            }
            doneSection
        }
        .onAppear(perform: refreshAuth)
    }

    private var addLink: some View {
        NavigationLink(value: AppRoute.reminderNew(catID: nil)) {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(DS.primary, in: RoundedRectangle(cornerRadius: DS.Radius.iconButton, style: .continuous))
        }
        .buttonStyle(.plain)
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
        // 长按菜单用来"改 / 删"：把这两个动作放在菜单里，而不是往行上再加两个按钮 ——
        // 一行的主动作只能有一个（这里是"完成"），其余的藏进长按是 iOS 的常规语言。
        .contextMenu {
            Button {
                nav.push(.reminderEdit(reminder.id))
            } label: {
                Label("改日期或说明", systemImage: "calendar")
            }
            Button(role: .destructive) {
                store.deleteReminder(id: reminder.id)
                NotificationService.reschedule(reminders: store.data.reminders)
            } label: {
                Label("删除这条提醒", systemImage: "trash")
            }
        }
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
                         message: "疫苗、驱虫、称重、B 超、预产期都可以加进来\n做完点一下就能划掉",
                         hint: "提醒跟着猫走：在种猫详情里能看到它名下的待办") {
                DSPrimaryLink(title: "新增提醒", route: .reminderNew(catID: nil))
            }
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
