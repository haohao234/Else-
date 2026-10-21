import SwiftUI

// MARK: - 01 首页
//
// 对应画布屏 01。这一屏刻意用满了令牌层与组件层：
// 三宫格统计、提醒行、繁育进度卡、支出趋势图 —— 组件层能不能扛住，看这一屏就知道。
// 阶段二会补：提醒页/设置页/记一笔 等二级页，以及空状态与骨架屏的接入。

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var nav: AppNav

    private var todayLine: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: DS.Space.l) {
                    statsCard
                    catsSection
                    remindersSection
                    financeSection
                }
                .padding(.horizontal, DS.Space.screenH)
                .padding(.bottom, 100)  // TabBar 高 ~94pt，留白避免遮挡
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: 顶部

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(todayLine).font(.system(size: 12)).foregroundStyle(DS.inkTertiary)
                Text("Elese的猫舍")
                    .font(DS.Typo.screenTitle)
                    .foregroundStyle(DS.ink)
            }
            Spacer(minLength: DS.Space.m)
            DSIconButton(systemName: "bell", filled: false) {
                nav.homePath.append(.reminders)
            }
            .overlay(alignment: .topTrailing) {
                if store.overdueCount > 0 {
                    Circle().fill(DS.alert).frame(width: 7, height: 7).offset(x: -5, y: 5)
                }
            }
            DSIconTile(systemName: "cat", size: 36, tint: DS.primary, background: DS.surfaceSoft)
        }
        .padding(.horizontal, DS.Space.screenH)
        .padding(.top, DS.Space.xxs)
        .padding(.bottom, DS.Space.m)
    }

    // MARK: 三宫格统计

    private var statsCard: some View {
        DSCard {
            HStack(alignment: .top, spacing: DS.Space.m) {
                DSStatTile(value: "\(store.data.cats.count)", label: "种猫总数")
                DSStatTile(value: "\(store.data.breedings.count)", label: "繁育记录")
                DSStatTile(value: "\(store.data.cats.filter { $0.gender == .female && $0.status == .pregnant }.count)", label: "怀孕中")
            }
        }
    }

    // MARK: 种猫横滑区

    /// 首页顶部横向滑动的种猫头像栏，点击进详情
    private var catsSection: some View {
        VStack(spacing: DS.Space.s) {
            DSSectionHeader(title: "我的种猫",
                            actionTitle: "\(store.data.cats.count) 只",
                            onAction: { nav.go(to: "cats") })
            if store.data.cats.isEmpty {
                DSCard {
                    Text("还没有种猫档案")
                        .font(DS.Typo.rowTitle)
                        .foregroundStyle(DS.ink)
                    Text("去「种猫」页建第一只，之后配对、记账都挂在它名下")
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.inkTertiary)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.m) {
                        ForEach(store.data.cats) { cat in
                            NavigationLink(value: AppRoute.catDetail(cat.id)) {
                                VStack(spacing: DS.Space.xs) {
                                    DSCatAvatar(name: cat.name,
                                                image: store.avatarImage(named: cat.avatarFileName),
                                                size: 52)
                                    Text(cat.name)
                                        .font(DS.Typo.caption)
                                        .foregroundStyle(DS.ink)
                                        .lineLimit(1)
                                    Text(cat.status.label)
                                        .font(.system(size: 10))
                                        .foregroundStyle(DS.inkTertiary)
                                }
                                .frame(width: 72)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: 提醒日历 + 今日待办

    private var remindersSection: some View {
        VStack(spacing: DS.Space.s) {
            DSSectionHeader(title: "提醒日历",
                            actionTitle: "全部 \(store.openReminders.count) 条",
                            onAction: { nav.homePath.append(.reminders) })

            // 迷你日历：有提醒的日期标彩色圆点
            reminderCalendar

            // 今日待办（醒目突出）
            if !todayReminders.isEmpty {
                VStack(spacing: DS.Space.s) {
                    HStack(spacing: DS.Space.xxs) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.alert)
                        Text("今天要做")
                            .font(DS.Typo.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(DS.alert)
                        Spacer(minLength: 0)
                    }
                    ForEach(todayReminders) { reminder in
                        NavigationLink(value: AppRoute.reminders) {
                            DSListRow {
                                let overdue = reminder.urgency == .overdue
                                DSIconTile(systemName: reminder.kind.symbol,
                                           tint: overdue ? DS.alert : DS.primary,
                                           background: overdue ? DS.alertSoft : DS.surfaceSoft)
                                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                                    Text(reminder.title).font(DS.Typo.rowTitle).foregroundStyle(DS.ink)
                                    Text(reminder.subtitle)
                                        .font(DS.Typo.caption)
                                        .foregroundStyle(overdue ? DS.alert : DS.inkTertiary)
                                }
                                Spacer(minLength: 0)
                                DSStatusChip(text: reminder.dueLabel.text,
                                             tone: reminder.dueLabel.isOverdue ? .alert : .current)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if store.openReminders.isEmpty {
                DSCard {
                    Text("眼下没有待办")
                        .font(DS.Typo.rowTitle)
                        .foregroundStyle(DS.ink)
                    Text("疫苗、驱虫、称重、预产期都会出现在这里")
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.inkTertiary)
                }
            } else {
                DSCard {
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(DS.CategoryTint.sale)
                        Text("今天没有待办，最近的在 \(nearestReminderDay)")
                            .font(DS.Typo.caption)
                            .foregroundStyle(DS.inkSecondary)
                    }
                }
            }
        }
    }

    /// 今天的提醒（含逾期）
    private var todayReminders: [Reminder] {
        store.openReminders.filter { $0.urgency == .today || $0.urgency == .overdue }
    }

    /// 最近一个有待办的日期文案
    private var nearestReminderDay: String {
        guard let next = store.openReminders.first else { return "--" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: next.dueDate).day ?? 0
        if days <= 0 { return "今天" }
        if days == 1 { return "明天" }
        return "\(days) 天后"
    }

    /// 迷你提醒日历：本月日历格子，有提醒的日期标圆点
    private var reminderCalendar: some View {
        let cal = Calendar.current
        let month = Date()
        let reminderDays = daysWithReminders(in: month)

        return DSCard {
            VStack(spacing: DS.Space.xs) {
                // 星期头
                let symbols = ["一", "二", "三", "四", "五", "六", "日"]
                HStack(spacing: 0) {
                    ForEach(symbols, id: \.self) { s in
                        Text(s)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DS.inkFaint)
                            .frame(maxWidth: .infinity)
                    }
                }
                // 日期格子
                let cells = calendarCells(for: month)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.xxs), count: 7),
                          spacing: DS.Space.xxs) {
                    ForEach(cells.indices, id: \.self) { i in
                        if let day = cells[i] {
                            let isToday = cal.isDateInToday(dateFor(day: day, in: month))
                            let hasReminder = reminderDays.contains(day)
                            VStack(spacing: 1) {
                                Text("\(day)")
                                    .font(.system(size: 12, weight: isToday ? .bold : .regular))
                                    .foregroundStyle(isToday ? .white : DS.ink)
                                Circle()
                                    .fill(hasReminder ? (isToday ? Color.white : DS.primary) : Color.clear)
                                    .frame(width: 4, height: 4)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(
                                isToday ? DS.primary : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                        } else {
                            Color.clear.frame(height: 32)
                        }
                    }
                }
            }
        }
    }

    /// 本月有提醒的日期集合
    private func daysWithReminders(in month: Date) -> Set<Int> {
        let cal = Calendar.current
        var days = Set<Int>()
        for r in store.data.reminders where !r.isDone {
            if cal.isDate(r.dueDate, equalTo: month, toGranularity: .month) {
                days.insert(cal.component(.day, from: r.dueDate))
            }
        }
        return days
    }

    /// 生成日历格子数组（前面补 nil 占位）
    private func calendarCells(for month: Date) -> [Int?] {
        let cal = Calendar.current
        guard let range = cal.range(of: .day, in: .month, for: month),
              let firstDay = cal.date(from: cal.dateComponents([.year, .month], from: month))
        else { return [] }
        let weekday = cal.component(.weekday, from: firstDay)
        // 周一起始：周日=7→6, 周一=2→0, ...
        let leading = (weekday + 5) % 7
        return Array(repeating: nil, count: leading) + range.map { Optional($0) }
    }

    private func dateFor(day: Int, in month: Date) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month], from: month)
        comps.day = day
        return cal.date(from: comps) ?? month
    }

    // MARK: 本月支出

    private var financeSection: some View {
        let month = Date()
        let bills = store.bills(in: month)
        let total = store.total(of: bills)
        let cal = Calendar.current
        let dayOfMonth = cal.component(.day, from: month)

        return VStack(spacing: DS.Space.s) {
            DSSectionHeader(title: "本月支出",
                            actionTitle: "查看明细",
                            onAction: { nav.go(to: "finance") })
            Button {
                nav.go(to: "finance")
            } label: {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                        Text(Money.yuan(total))
                            .font(DS.Typo.heroAmount)
                            .foregroundStyle(DS.primary)
                        Spacer(minLength: 0)
                        Text("日均 \(Money.yuan(total / Double(max(dayOfMonth, 1))))")
                            .font(DS.Typo.caption)
                            .foregroundStyle(DS.inkTertiary)
                    }
                    // 用**真实的近 7 个月数据**，不留示例数组 ——
                    // 图表里放假数据，整屏数字的可信度就一起没了。
                    DSBarChart(values: trend)
                    Text("近 7 个月 · 本月共 \(bills.count) 笔记录")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(DS.inkTertiary)
                }
                .padding(DS.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsCardSurface(radius: DS.Radius.cardLarge)
            }
            .buttonStyle(.plain)
        }
    }

    private var trend: [Double] {
        let cal = Calendar.current
        return (0..<7).reversed().map { offset in
            guard let m = cal.date(byAdding: .month, value: -offset, to: Date()) else { return 0 }
            return store.total(of: store.bills(in: m))
        }
    }
}
