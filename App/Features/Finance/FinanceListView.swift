import SwiftUI

// MARK: - 07 育猫记账
//
// 这一屏回答三个问题，顺序不能乱：
//   ① 这个月花了多少（大数字）
//   ② 花在哪了（分类占比 —— 配搭色的唯一正当用途，与分类选择网格一一对应）
//   ③ 具体每一笔（列表，可点进去改）
//
// 月份是**可翻的**，不是只有"本月"。原因很实在：育猫的支出集中在配种、生产、
// 疫苗这几个节点，用户月底想复盘的是"上个月那笔 700 的配种费到底记了没"。
// 只能看本月的话，这笔账就得靠记忆。

struct FinanceListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var monthOffset = 0
    /// 在月历上选中的"几号"。选中后明细只显示那一天 ——
    /// 这就是"每日的记录情况"：从"看整月"下钻到"看某一天"，而不是再开一屏。
    @State private var selectedDay: Int?

    private var calendar: Calendar { Calendar.current }

    private var month: Date {
        calendar.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
    }

    private var bills: [Bill] { store.bills(in: month) }
    private var total: Double { store.total(of: bills) }
    private var breakdown: [(category: BillCategory, amount: Double)] { store.breakdown(of: bills) }

    private var isCurrentMonth: Bool { monthOffset == 0 }

    /// 近 7 个月（含当前显示的月份）的支出，给柱状图。
    /// 用**逐月真实数据**而不是示例数组 —— 图表一旦是假的，整屏数字都会失去可信度。
    private var trend: [Double] {
        (0..<7).reversed().map { offset in
            guard let m = calendar.date(byAdding: .month, value: -offset, to: month) else { return 0 }
            return store.total(of: store.bills(in: m))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            DSScreenTitle(title: "育猫记账", trailing: AnyView(addButton))
            monthBar
            content
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var addButton: some View {
        NavigationLink(value: AppRoute.billEdit(nil)) {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(DS.primary, in: RoundedRectangle(cornerRadius: DS.Radius.iconButton, style: .continuous))
        }
        .buttonStyle(.dsPressable)
    }

    private var monthBar: some View {
        DSMonthSwitcher(title: Formatters.monthTitle.string(from: month),
                        onPrev: { monthOffset -= 1; clearDaySelection() },
                        onNext: { if monthOffset < 0 { monthOffset += 1; clearDaySelection() } })
            .padding(.horizontal, DS.Space.screenH)
            .padding(.bottom, DS.Space.m)
    }

    /// 换月必须清掉选中日 —— 否则筛选停在"上个月的 8 号"，
    /// 而新月份里那天可能没有记录，用户会看到一张莫名其妙空着的明细。
    private func clearDaySelection() {
        selectedDay = nil
    }

    @ViewBuilder
    private var content: some View {
        if bills.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: DS.Space.l) {
                    totalCard
                    calendarCard
                    breakdownCard
                    listSection
                }
                .padding(.horizontal, DS.Space.screenH)
                .padding(.bottom, DS.Space.xxl * 2)
            }
        }
    }

    // MARK: 月历（每天的支出，一眼看形状）

    private var calendarCard: some View {
        DSCard {
            DSSectionHeader(title: "月历")
            DSMonthCalendar(month: month,
                            amounts: store.dailyTotals(in: month),
                            selectedDay: $selectedDay)
        }
    }

    // MARK: ① 这个月花了多少

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text(isCurrentMonth ? "本月累计支出" : "\(Formatters.monthTitle.string(from: month))支出")
                .font(DS.Typo.caption)
                .foregroundStyle(DS.inkTertiary)
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                Text(Money.yuan(total))
                    .font(DS.Typo.heroAmount)
                    .foregroundStyle(DS.primary)
                Spacer(minLength: 0)
                Text("共 \(bills.count) 笔")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.inkTertiary)
            }
            DSBarChart(values: trend, height: 44)
            Text("近 7 个月趋势 · 最高 \(Money.yuan(trend.max() ?? 0))")
                .font(DS.Typo.caption)
                .foregroundStyle(DS.inkTertiary)
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCardSurface(radius: DS.Radius.cardLarge)
    }

    // MARK: ② 花在哪了

    private var breakdownCard: some View {
        DSCard {
            DSSectionHeader(title: "分类占比")
            ForEach(breakdown, id: \.category) { item in
                HStack(spacing: DS.Space.s) {
                    Circle()
                        .fill(DS.CategoryTint.color(for: item.category))
                        .frame(width: 8, height: 8)
                    Text(item.category.label)
                        .font(DS.Typo.body)
                        .foregroundStyle(DS.inkSecondary)
                    Spacer(minLength: DS.Space.s)
                    Text(percentText(item.amount))
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.inkTertiary)
                    Text(Money.yuan(item.amount))
                        .font(DS.Typo.rowAmount)
                        .foregroundStyle(DS.ink)
                }
            }
        }
    }

    private func percentText(_ amount: Double) -> String {
        guard total > 0 else { return "" }
        return String(format: "%.0f%%", amount / total * 100)
    }

    // MARK: ③ 每一笔（按天分组，每天都带自己的小计）

    private var listSection: some View {
        let groups = store.dailyGroups(in: month)
        let shown = selectedDay.map { day in groups.filter { $0.day == day } } ?? groups
        return VStack(spacing: DS.Space.l) {
            if let selectedDay {
                DSSectionHeader(title: "\(selectedDay) 日的记录",
                                actionTitle: "显示整月",
                                onAction: clearDaySelection)
            } else {
                DSSectionHeader(title: "明细")
            }
            ForEach(shown.indices, id: \.self) { index in
                dayBlock(shown[index])
            }
        }
    }

    /// 一天一组：上面是「几号 · 几笔 · 小计」，下面才是那天的每笔账。
    /// 这个"日小计行"就是用户要的「每日的记录情况」——
    /// 它把"这一天花了多少"从"要自己把几行加起来"变成一眼可见。
    private func dayBlock(_ group: (day: Int, bills: [Bill], total: Double)) -> some View {
        VStack(spacing: DS.Space.s) {
            HStack(spacing: DS.Space.s) {
                Text("\(group.day) 日")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.inkSecondary)
                Text("\(group.bills.count) 笔")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.inkFaint)
                Spacer(minLength: DS.Space.s)
                Text(Money.yuan(group.total))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DS.inkSecondary)
            }
            .padding(.horizontal, DS.Space.xxs)

            ForEach(group.bills) { bill in
                NavigationLink(value: AppRoute.billEdit(bill.id)) {
                    DSListRow {
                        DSIconTile(systemName: bill.category.symbol,
                                   tint: DS.CategoryTint.color(for: bill.category))
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(bill.title)
                                .font(DS.Typo.rowTitle)
                                .foregroundStyle(DS.ink)
                                .lineLimit(1)
                            Text(catLine(bill))
                                .font(DS.Typo.caption)
                                .foregroundStyle(DS.inkTertiary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: DS.Space.s)
                        Text(Money.signedYuan(bill.amount))
                            .font(DS.Typo.rowAmount)
                            .foregroundStyle(DS.ink)
                    }
                }
                .buttonStyle(.dsPressable)
            }
        }
    }

    private func catLine(_ bill: Bill) -> String {
        let names = bill.catIDs.compactMap { store.cat(id: $0)?.name }
        if names.isEmpty { return bill.metaLine }
        return bill.metaLine + " · " + names.joined(separator: "、")
    }

    // MARK: 空状态

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer(minLength: DS.Space.xxl * 2)
            DSEmptyState(systemName: "creditcard",
                         title: isCurrentMonth ? "本月还没有记账" : "这个月没有记录",
                         message: "猫粮、医疗、疫苗、配种费随手记一笔\n月底就能看清钱花在哪",
                         hint: "可以在「更多 → 设置」里把账单导出成 CSV") {
                if isCurrentMonth {
                    DSPrimaryLink(title: "记一笔", route: .billEdit(nil))
                } else {
                    DSPrimaryButton(title: "回到本月") { monthOffset = 0 }
                }
            }
            Spacer(minLength: 0)
        }
    }
}
