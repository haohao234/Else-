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
        .buttonStyle(.plain)
    }

    private var monthBar: some View {
        DSMonthSwitcher(title: Formatters.monthTitle.string(from: month),
                        onPrev: { monthOffset -= 1; clearDaySelection() },
                        onNext: { if monthOffset < 0 { monthOffset += 1; clearDaySelection() } })
            .padding(.horizontal, DS.Space.screenH)
            .padding(.bottom, DS.Space.m)
    }

    /// 换月必须清掉选中日和折叠状态 —— 否则筛选停在"上个月的 8 号"，
    /// 而新月份里那天可能没有记录，用户会看到一张莫名其妙空着的明细。
    private func clearDaySelection() {
        selectedDay = nil
        collapsedDays = []
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
                .padding(.bottom, 100)  // TabBar 高 ~94pt，留白避免遮挡
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

    // MARK: ① 本月收支总览

    private var totalCard: some View {
        let expenseTotal = store.expense(of: bills)
        let incomeTotal = store.income(of: bills)
        let netTotal = incomeTotal - expenseTotal

        return VStack(alignment: .leading, spacing: DS.Space.m) {
            // 净额大数字
            Text(isCurrentMonth ? "本月净收支" : "\(Formatters.monthTitle.string(from: month))净收支")
                .font(DS.Typo.caption)
                .foregroundStyle(DS.inkTertiary)
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                Text(Money.netYuan(netTotal))
                    .font(DS.Typo.heroAmount)
                    .foregroundStyle(netTotal >= 0 ? DS.CategoryTint.sale : DS.primary)
                Spacer(minLength: 0)
                Text("共 \(bills.count) 笔")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.inkTertiary)
            }

            // 支出 / 收入 双行摘要
            HStack(spacing: DS.Space.l) {
                HStack(spacing: DS.Space.xxs) {
                    Circle().fill(DS.primary).frame(width: 6, height: 6)
                    Text("支出 " + Money.yuan(expenseTotal))
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.inkSecondary)
                }
                if incomeTotal > 0 {
                    HStack(spacing: DS.Space.xxs) {
                        Circle().fill(DS.CategoryTint.sale).frame(width: 6, height: 6)
                        Text("收入 " + Money.yuan(incomeTotal))
                            .font(DS.Typo.caption)
                            .foregroundStyle(DS.inkSecondary)
                    }
                }
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

    // MARK: ② 花在哪了 / 收入从哪来

    private var breakdownCard: some View {
        let expenseItems = breakdown.filter { !$0.category.isIncome }
        let incomeItems = breakdown.filter { $0.category.isIncome }
        let expenseTotal = store.expense(of: bills)

        return DSCard {
            DSSectionHeader(title: "分类占比")
            ForEach(expenseItems, id: \.category) { item in
                HStack(spacing: DS.Space.s) {
                    Circle()
                        .fill(DS.CategoryTint.color(for: item.category))
                        .frame(width: 8, height: 8)
                    Text(item.category.label)
                        .font(DS.Typo.body)
                        .foregroundStyle(DS.inkSecondary)
                    Spacer(minLength: DS.Space.s)
                    Text(percentText(item.amount, of: expenseTotal))
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.inkTertiary)
                    Text(Money.yuan(item.amount))
                        .font(DS.Typo.rowAmount)
                        .foregroundStyle(DS.ink)
                }
            }
            // 收入单独一组，不参与支出占比
            if !incomeItems.isEmpty {
                Divider().padding(.vertical, DS.Space.xxs)
                ForEach(incomeItems, id: \.category) { item in
                    HStack(spacing: DS.Space.s) {
                        Circle()
                            .fill(DS.CategoryTint.color(for: item.category))
                            .frame(width: 8, height: 8)
                        Text(item.category.label)
                            .font(DS.Typo.body)
                            .foregroundStyle(DS.inkSecondary)
                        Spacer(minLength: DS.Space.s)
                        Text(Money.incomeYuan(item.amount))
                            .font(DS.Typo.rowAmount)
                            .foregroundStyle(DS.CategoryTint.sale)
                    }
                }
            }
        }
    }

    private func percentText(_ amount: Double, of total: Double) -> String {
        guard total > 0 else { return "" }
        return String(format: "%.0f%%", amount / total * 100)
    }

    // MARK: ③ 每一笔（按天分组，可折叠）

    /// 记录哪些天是折叠状态。默认全部展开，点头部收起。
    @State private var collapsedDays: Set<Int> = []

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

    /// 一天一组：头部可点击折叠/展开。
    /// 数据多的时候收起不关心的天，只看关键日期 —— 不用滚一屏的列表。
    private func dayBlock(_ group: (day: Int, bills: [Bill], total: Double)) -> some View {
        let collapsed = collapsedDays.contains(group.day)

        return VStack(spacing: DS.Space.s) {
            // 日小计行（可点击折叠）
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if collapsed {
                        collapsedDays.remove(group.day)
                    } else {
                        collapsedDays.insert(group.day)
                    }
                }
            } label: {
                HStack(spacing: DS.Space.s) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.inkFaint)
                    Text("\(group.day) 日")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.inkSecondary)
                    Text("\(group.bills.count) 笔")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.inkFaint)
                    Spacer(minLength: DS.Space.s)
                    // 收入/支出分行显示小计
                    let dayExpense = group.bills.filter { !$0.category.isIncome }.reduce(0.0) { $0 + $1.amount }
                    let dayIncome = group.bills.filter { $0.category.isIncome }.reduce(0.0) { $0 + $1.amount }
                    if dayIncome > 0 {
                        Text(Money.incomeYuan(dayIncome))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(DS.CategoryTint.sale)
                    }
                    Text(Money.signedYuan(dayExpense))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DS.inkSecondary)
                }
                .padding(.horizontal, DS.Space.xxs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !collapsed {
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
                            if bill.category.isIncome {
                                Text(Money.incomeYuan(bill.amount))
                                    .font(DS.Typo.rowAmount)
                                    .foregroundStyle(DS.CategoryTint.sale)
                            } else {
                                Text(Money.signedYuan(bill.amount))
                                    .font(DS.Typo.rowAmount)
                                    .foregroundStyle(DS.ink)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
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
