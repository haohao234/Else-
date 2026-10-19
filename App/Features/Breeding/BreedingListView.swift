import SwiftUI

// MARK: - 05 繁育记录
//
// 这一屏的核心不是"列出记录"，而是**让用户一眼看出哪一胎该干活了**：
//   · 阶段芯片 + 四段进度条 → 现在停在哪一步
//   · 进展描述（配对 x · 怀孕 y）→ 上一次动作是哪天
//   · 预产期临近的排在最前（stage 排序：怀孕 > 配对 > 生产 > 出窝）
// 排序规则必须由数据推导，不能让用户手动排序 —— 手动排序在数据变化后必然过期。

struct BreedingListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var filter: BreedingStage?

    private var allRecords: [BreedingRecord] {
        store.breedingsWithNames.sorted { a, b in
            let ra = rank(a.stage), rb = rank(b.stage)
            if ra != rb { return ra < rb }
            return a.code > b.code
        }
    }

    /// 需要关注的排前面：怀孕（要盯预产期）→ 配对（等确认）→ 已生产（要照看）→ 已出窝（归档）
    private func rank(_ stage: BreedingStage) -> Int {
        switch stage {
        case .pregnant: return 0
        case .mated: return 1
        case .birth: return 2
        case .weaned: return 3
        }
    }

    private var filtered: [BreedingRecord] {
        guard let filter else { return allRecords }
        return allRecords.filter { $0.stage == filter }
    }

    /// 有预产期且尚未生产的记录（按预产期升序，最近的排最前）
    private var dueSoonRecords: [DueSoonItem] {
        let items = allRecords.compactMap { record -> DueSoonItem? in
            guard let dueDate = record.expectedDueDate,
                  record.stage == .mated || record.stage == .pregnant else { return nil }
            let cal = Calendar.current
            let days = cal.dateComponents([.day],
                from: cal.startOfDay(for: Date()),
                to: cal.startOfDay(for: dueDate)).day ?? 0
            return DueSoonItem(record: record, daysLeft: days)
        }
        return items.sorted { $0.daysLeft < $1.daysLeft }
    }

    var body: some View {
        VStack(spacing: 0) {
            DSScreenTitle(title: "繁育记录", trailing: AnyView(addButton))
            controls
            if !dueSoonRecords.isEmpty {
                countdownBanner
            }
            content
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var addButton: some View {
        NavigationLink(value: AppRoute.breedingEdit(nil)) {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(DS.primary, in: RoundedRectangle(cornerRadius: DS.Radius.iconButton, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var controls: some View {
        ScrollView(.horizontal) {
            HStack(spacing: DS.Space.xs) {
                chip(title: "全部", active: filter == nil) { filter = nil }
                ForEach(BreedingStage.allCases) { stage in
                    chip(title: stage.label, active: filter == stage) { filter = stage }
                }
            }
            .padding(.horizontal, DS.Space.screenH)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .padding(.bottom, DS.Space.m)
    }

    private func chip(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? .white : DS.inkSecondary)
                .padding(.horizontal, DS.Space.l)
                .frame(height: 32)
                .background(active ? AnyShapeStyle(DS.primary) : AnyShapeStyle(DS.surface), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 待产倒计时横滚条

    /// 可爱风格的横向滚动倒计时卡片，每张对应一只待产母猫
    private var countdownBanner: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(spacing: DS.Space.xxs) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.alert)
                Text("待产提醒")
                    .font(DS.Typo.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.inkSecondary)
            }
            .padding(.leading, DS.Space.screenH)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.s) {
                    ForEach(dueSoonRecords) { item in
                        NavigationLink(value: AppRoute.breedingDetail(item.record.id)) {
                            DueSoonCard(record: item.record, daysLeft: item.daysLeft)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DS.Space.screenH)
            }
        }
        .padding(.bottom, DS.Space.m)
    }

    @ViewBuilder
    private var content: some View {
        if allRecords.isEmpty {
            emptyNoRecords
        } else if filtered.isEmpty {
            emptyNoMatch
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: DS.Space.s) {
                ForEach(filtered) { record in
                    NavigationLink(value: AppRoute.breedingDetail(record.id)) {
                        BreedingRowCard(record: record)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Space.screenH)
            .padding(.bottom, DS.Space.xxl)
        }
    }

    private var emptyNoRecords: some View {
        VStack(spacing: 0) {
            Spacer(minLength: DS.Space.xxl * 2)
            DSEmptyState(systemName: "heart",
                         title: "还没有繁育记录",
                         message: "选一只母猫和一只公猫配对吧\n之后怀孕、生产、出窝都在这条记录里推进",
                         hint: hintForNewRecord) {
                if canCreate {
                    DSPrimaryLink(title: "新建配对", route: .breedingEdit(nil))
                } else {
                    DSPrimaryLink(title: "先去建种猫档案", route: .catEdit(nil))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var emptyNoMatch: some View {
        VStack(spacing: 0) {
            Spacer(minLength: DS.Space.xxl * 2)
            DSEmptyState(systemName: "line.3.horizontal.decrease.circle",
                         title: "这个阶段还没有记录",
                         message: "换个阶段看看，或者新建一条",
                         hint: nil) {
                VStack(spacing: DS.Space.s) {
                    DSPrimaryButton(title: "看全部记录") { filter = nil }
                    DSPrimaryLink(title: "新建配对", route: .breedingEdit(nil), height: 44)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var canCreate: Bool {
        store.data.cats.contains { $0.gender == .female } && store.data.cats.contains { $0.gender == .male }
    }

    private var hintForNewRecord: String {
        canCreate ? "需要一只母猫和一只公猫" : "先建档案：至少一只母猫 + 一只公猫"
    }
}

// MARK: - 繁育行卡（05 列表与首页共用同一张卡）

struct BreedingRowCard: View {
    let record: BreedingRecord

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                Text(record.title)
                    .font(DS.Typo.cardTitle)
                    .foregroundStyle(DS.ink)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.s)
                DSStatusChip(text: record.stage.label, tone: record.stage.tone)
            }
            DSStageProgress(filled: record.stage.completedCount)
            HStack(spacing: 0) {
                ForEach(BreedingStage.allCases) { stage in
                    let isCurrent = stage == record.stage
                    Text(stage.label)
                        .font(.system(size: 10, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? DS.primary : DS.inkTertiary)
                        .frame(maxWidth: .infinity,
                               alignment: stage == .mated ? .leading : (stage == .weaned ? .trailing : .center))
                }
            }
            HStack {
                Text(record.progressLine)
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.inkTertiary)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.s)
                Text(record.code)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(DS.inkTertiary)
            }
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsRowSurface()
    }
}

// MARK: - 待产倒计时数据项

private struct DueSoonItem: Identifiable {
    let id: UUID  // = record.id
    let record: BreedingRecord
    let daysLeft: Int

    init(record: BreedingRecord, daysLeft: Int) {
        self.id = record.id
        self.record = record
        self.daysLeft = daysLeft
    }
}

// MARK: - 待产倒计时卡片（繁育列表页横滚条用）

struct DueSoonCard: View {
    let record: BreedingRecord
    let daysLeft: Int

    private var isUrgent: Bool { daysLeft <= 7 && daysLeft >= 0 }
    private var isOverdue: Bool { daysLeft < 0 }
    private var accentColor: Color {
        if isOverdue { return DS.alert }
        if isUrgent { return Color(hex: 0xE39BC8) }  // 玫红（配搭色）
        return DS.primary
    }

    var body: some View {
        VStack(spacing: DS.Space.s) {
            // 🐱 猫猫头 + 名字
            Image(systemName: "cat.fill")
                .font(.system(size: 28))
                .foregroundStyle(accentColor)
                .frame(width: 48, height: 48)
                .background(accentColor.opacity(0.12), in: Circle())

            Text(record.motherName)
                .font(DS.Typo.caption)
                .fontWeight(.medium)
                .foregroundStyle(DS.ink)
                .lineLimit(1)

            // 大数字倒计时
            Text(daysLeft >= 0 ? "\(daysLeft)" : "\(-daysLeft)+")
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(accentColor)
                .monospacedDigit()

            // 状态文案 + 预产日期
            Text(countdownLabel)
                .font(.system(size: 11))
                .foregroundStyle(isOverdue ? DS.alert : DS.inkTertiary)

            if let dueDate = record.expectedDueDate {
                Text(Formatters.monthDay.string(from: dueDate) + " 预产")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.inkTertiary.opacity(0.7))
            }
        }
        .frame(width: 120)
        .padding(.vertical, DS.Space.m)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(Color.white)
                .shadow(color: accentColor.opacity(0.08), radius: 8, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .strokeBorder(accentColor.opacity(0.15), lineWidth: 1)
                )
        )
    }

    private var countdownLabel: String {
        if daysLeft > 7 { return "天后预产" }
        if daysLeft > 0 { return "即将生产" }
        if daysLeft == 0 { return "今天预产期" }
        return "已过期"
    }
}
