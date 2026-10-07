import SwiftUI

// MARK: - 01 首页
//
// 对应画布屏 01。这一屏刻意用满了令牌层与组件层：
// 三宫格统计、提醒行、繁育进度卡、支出趋势图 —— 组件层能不能扛住，看这一屏就知道。
// 阶段二会补：提醒页/设置页/记一笔 等二级页，以及空状态与骨架屏的接入。

struct HomeView: View {
    @EnvironmentObject private var store: AppStore

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
                    remindersSection
                    breedingSection
                    financeSection
                }
                .padding(.horizontal, DS.Space.screenH)
                .padding(.bottom, DS.Space.xxl)
            }
        }
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
            DSIconButton(systemName: "bell", filled: false) { }
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

    // MARK: 今日提醒

    private var remindersSection: some View {
        VStack(spacing: DS.Space.s) {
            DSSectionHeader(title: "今日提醒",
                            actionTitle: "全部 \(store.openReminders.count) 条",
                            onAction: {})
            ForEach(store.openReminders.prefix(2)) { reminder in
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
                                 tone: reminder.dueLabel.isOverdue ? .alert : .archived)
                }
            }
        }
    }

    // MARK: 繁育进度

    private var breedingSection: some View {
        VStack(spacing: DS.Space.s) {
            DSSectionHeader(title: "繁育进度",
                            actionTitle: "\(store.data.breedings.count) 条进行中",
                            onAction: {})
            if let record = store.breedingsWithNames.first {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.title).font(DS.Typo.cardTitle).foregroundStyle(DS.ink)
                            Text("\(record.code) · 预产期临近")
                                .font(DS.Typo.caption)
                                .foregroundStyle(DS.inkTertiary)
                        }
                        Spacer(minLength: DS.Space.s)
                        DSStatusChip(text: record.stage.label, tone: record.stage.tone)
                    }
                    DSStageProgress(filled: record.stage.completedCount)
                    HStack(spacing: 0) {
                        // ⚠️ 不要写 `ForEach(Array(x.enumerated()), id: \.offset)`：
                        // 指向**元组成员**的 key path 在 Swift 里不受支持，换个编译器版本就炸。
                        // 这里改用 Identifiable 的枚举本身，下标靠比较枚举值拿。
                        ForEach(BreedingStage.allCases) { stage in
                            let isCurrent = stage == .pregnant
                            Text(stage.label)
                                .font(.system(size: 10, weight: isCurrent ? .semibold : .regular))
                                .foregroundStyle(isCurrent ? DS.primary : DS.inkTertiary)
                                .frame(maxWidth: .infinity,
                                       alignment: stage == .mated ? .leading : (stage == .weaned ? .trailing : .center))
                        }
                    }
                    HStack {
                        Text("预产期 \(Formatters.monthDay.string(from: record.expectedDueDate ?? Date()))")
                            .font(DS.Typo.caption)
                            .foregroundStyle(DS.inkTertiary)
                        Spacer(minLength: DS.Space.s)
                        Text("查看详情")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.primary)
                    }
                }
                .padding(DS.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsCardSurface(radius: DS.Radius.cardLarge)
            }
        }
    }

    // MARK: 本月支出

    private var financeSection: some View {
        let month = Date()
        let bills = store.bills(in: month)
        let total = store.total(of: bills)

        return VStack(spacing: DS.Space.s) {
            DSSectionHeader(title: "本月支出", actionTitle: "查看明细", onAction: {})
            VStack(alignment: .leading, spacing: DS.Space.m) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                    Text(Money.yuan(total))
                        .font(DS.Typo.heroAmount)
                        .foregroundStyle(DS.primary)
                    Spacer(minLength: 0)
                    Text("日均 \(Money.yuan(total / 30))")
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.inkTertiary)
                }
                DSBarChart(values: [180, 320, 240, 420, 290, total, 380])
                Text("上月同期 \(Money.yuan(total * 0.94)) · 本月共 \(bills.count) 笔记录")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(DS.inkTertiary)
            }
            .padding(DS.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCardSurface(radius: DS.Radius.cardLarge)
        }
    }
}
