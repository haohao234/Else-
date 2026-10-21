import SwiftUI

// MARK: - 05 繁育记录
//
// 重构理念：
//   · 卡片主角是**倒计时大数字**（不是阶段进度条）
//   · 快捷操作一键完成（确认怀孕 / 确认生产 / 确认出窝），不用点进详情
//   · 筛选简化为：全部 / 待产中 / 已完成
//   · 待产按预产期升序排列，最紧急的排最前

struct BreedingListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var filter: FilterOption = .all
    @State private var birthSheetRecord: BreedingRecord?

    enum FilterOption: String, CaseIterable, Identifiable {
        case all, active, completed
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "全部"
            case .active: return "待产中"
            case .completed: return "已完成"
            }
        }
    }

    // MARK: 数据

    private var allRecords: [BreedingRecord] {
        store.breedingsWithNames.sorted { a, b in
            let ra = sortRank(a), rb = sortRank(b)
            if ra != rb { return ra < rb }
            // 同阶段内：待产按预产期升序（最近排最前），已完成按生产日期降序
            if a.stage == .birth || a.stage == .weaned {
                return (a.birthDate ?? .distantPast) > (b.birthDate ?? .distantPast)
            }
            return (a.expectedDueDate ?? .distantFuture) < (b.expectedDueDate ?? .distantFuture)
        }
    }

    private func sortRank(_ r: BreedingRecord) -> Int {
        switch r.stage {
        case .pregnant: return 0
        case .mated: return 1
        case .birth: return 2
        case .weaned: return 3
        }
    }

    private var activeRecords: [BreedingRecord] {
        allRecords.filter { $0.stage == .mated || $0.stage == .pregnant }
    }

    private var completedRecords: [BreedingRecord] {
        allRecords.filter { $0.stage == .birth || $0.stage == .weaned }
    }

    private var filtered: [BreedingRecord] {
        switch filter {
        case .all: return allRecords
        case .active: return activeRecords
        case .completed: return completedRecords
        }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            DSScreenTitle(title: "繁育记录", trailing: AnyView(addButton))
            filterChips
            content
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $birthSheetRecord) { record in
            QuickBirthSheet(record: record) { date, count in
                confirmBirth(record, date: date, kittenCount: count)
            }
        }
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

    // MARK: 筛选

    private var filterChips: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(FilterOption.allCases) { option in
                chip(title: option.label, active: filter == option) { filter = option }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.screenH)
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

    // MARK: 内容

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
            VStack(spacing: DS.Space.m) {
                ForEach(filtered) { record in
                    if record.stage == .mated || record.stage == .pregnant {
                        NavigationLink(value: AppRoute.breedingDetail(record.id)) {
                            ActiveRecordCard(
                                record: record,
                                onQuickBirth: { birthSheetRecord = record },
                                onQuickPregnant: { confirmPregnant(record) }
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink(value: AppRoute.breedingDetail(record.id)) {
                            CompletedRecordCard(
                                record: record,
                                onQuickWeaned: { confirmWeaned(record) }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, DS.Space.screenH)
            .padding(.bottom, 100)  // TabBar 高 ~94pt，留白避免遮挡
        }
    }

    // MARK: 空状态

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
                         message: "换个筛选看看，或者新建一条",
                         hint: nil) {
                VStack(spacing: DS.Space.s) {
                    DSPrimaryButton(title: "看全部记录") { filter = .all }
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

    // MARK: 快捷操作

    /// 确认怀孕：设置怀孕日期为今天，阶段自动推进为 .pregnant
    private func confirmPregnant(_ record: BreedingRecord) {
        var r = record
        r.pregnantDate = Date()
        store.upsert(breeding: r)
    }

    /// 确认生产：设置生产日期 + 产仔数，并清理预产期提醒
    private func confirmBirth(_ record: BreedingRecord, date: Date, kittenCount: Int?) {
        var r = record
        r.birthDate = date
        r.kittenCount = kittenCount
        store.upsert(breeding: r)
        // 清理预产期提醒（已生产，不再需要）
        if let rem = store.data.reminders.first(where: {
            $0.kind == .dueDate && $0.catID == record.motherID && $0.detail.contains("预产期")
        }) {
            store.deleteReminder(id: rem.id)
        }
    }

    /// 确认出窝：设置出窝日期为今天
    private func confirmWeaned(_ record: BreedingRecord) {
        var r = record
        r.weanedDate = Date()
        store.upsert(breeding: r)
    }
}

// MARK: - 待产卡片（倒计时为中心）

struct ActiveRecordCard: View {
    let record: BreedingRecord
    let onQuickBirth: () -> Void
    let onQuickPregnant: () -> Void

    private var daysLeft: Int? {
        guard let dueDate = record.expectedDueDate else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day],
            from: cal.startOfDay(for: Date()),
            to: cal.startOfDay(for: dueDate)).day ?? 0
    }

    private var isUrgent: Bool { (daysLeft ?? 99) <= 7 && (daysLeft ?? 0) >= 0 }
    private var isOverdue: Bool { (daysLeft ?? 0) < 0 }
    private var accentColor: Color {
        if isOverdue { return DS.alert }
        if isUrgent { return Color(hex: 0xE39BC8) }  // 玫红
        return DS.primary
    }

    var body: some View {
        VStack(spacing: DS.Space.m) {
            // 头部：🐱 + 名字 + 阶段标签
            HStack(spacing: DS.Space.xs) {
                Image(systemName: "cat.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DS.primary)
                Text(record.title)
                    .font(DS.Typo.cardTitle)
                    .foregroundStyle(DS.ink)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.s)
                DSStatusChip(text: record.stage.label, tone: record.stage.tone)
            }

            // 倒计时区
            if let days = daysLeft {
                VStack(spacing: DS.Space.xxs) {
                    Text("\(abs(days))")
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundStyle(accentColor)
                        .monospacedDigit()
                    Text(countdownLabel(days: days))
                        .font(DS.Typo.caption)
                        .foregroundStyle(accentColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Space.s)
                .background(
                    accentColor.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                )

                // 日期行
                HStack(spacing: DS.Space.m) {
                    if let mated = record.matedDate {
                        Label("配种 " + Formatters.monthDay.string(from: mated),
                              systemImage: "heart.fill")
                    }
                    if let due = record.expectedDueDate {
                        Label("预产 " + Formatters.monthDay.string(from: due),
                              systemImage: "calendar")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(DS.inkTertiary)
            } else if record.matedDate != nil {
                // 已配种但没设预产期
                HStack(spacing: DS.Space.xxs) {
                    Image(systemName: "calendar.badge.plus")
                        .foregroundStyle(DS.primary)
                    Text("还没有预产期，去设置 →")
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.primary)
                }
            }

            // 快捷操作按钮
            HStack(spacing: DS.Space.s) {
                if record.stage == .mated && record.pregnantDate == nil {
                    Button(action: onQuickPregnant) {
                        Label("确认怀孕", systemImage: "checkmark.circle")
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(
                                DS.primary.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                            )
                            .foregroundStyle(DS.primary)
                    }
                    .buttonStyle(.plain)
                }

                if record.expectedDueDate != nil {
                    Button(action: onQuickBirth) {
                        Label("确认生产", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(
                                DS.primaryGradient,
                                in: RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                            )
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(Color.white)
                .shadow(color: accentColor.opacity(0.10), radius: 10, y: 3)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .strokeBorder(accentColor.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func countdownLabel(days: Int) -> String {
        if days > 7 { return "天后预产" }
        if days > 0 { return "即将生产" }
        if days == 0 { return "今天预产期" }
        return "已过期 \(abs(days)) 天"
    }
}

// MARK: - 已完成卡片

struct CompletedRecordCard: View {
    let record: BreedingRecord
    let onQuickWeaned: () -> Void

    var body: some View {
        VStack(spacing: DS.Space.s) {
            // 头部
            HStack(spacing: DS.Space.xs) {
                Image(systemName: "cat.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DS.primary)
                Text(record.title)
                    .font(DS.Typo.cardTitle)
                    .foregroundStyle(DS.ink)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.s)
                DSStatusChip(text: record.stage.label, tone: record.stage.tone)
            }

            // 摘要行
            HStack(spacing: DS.Space.xxs) {
                if let birth = record.birthDate {
                    Text(Formatters.monthDay.string(from: birth) + " 生产")
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.inkSecondary)
                }
                if let count = record.kittenCount {
                    Text("·")
                        .foregroundStyle(DS.inkTertiary)
                    Text("\(count) 只崽")
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.inkSecondary)
                }
                if let weaned = record.weanedDate {
                    Text("·")
                        .foregroundStyle(DS.inkTertiary)
                    Text(Formatters.monthDay.string(from: weaned) + " 出窝")
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.inkSecondary)
                }
                Spacer(minLength: 0)
                Text(record.code)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(DS.inkTertiary)
            }

            // 出窝按钮（仅已生产未出窝时显示）
            if record.stage == .birth {
                Button(action: onQuickWeaned) {
                    Label("确认出窝", systemImage: "shippingbox")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            DS.primary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                        )
                        .foregroundStyle(DS.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(Color.white)
                .shadow(color: DS.ink.opacity(0.06), radius: 8, y: 2)
        )
    }
}

// MARK: - 快速确认生产 Sheet

struct QuickBirthSheet: View {
    let record: BreedingRecord
    let onConfirm: (Date, Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var birthDate = Date()
    @State private var kittenText = ""

    init(record: BreedingRecord, onConfirm: @escaping (Date, Int?) -> Void) {
        self.record = record
        self.onConfirm = onConfirm
    }

    private var kittenCount: Int? {
        let trimmed = kittenText.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : Int(trimmed)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: DS.Space.l) {
                // 母猫信息
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: "cat.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(DS.primary)
                    Text(record.title)
                        .font(DS.Typo.cardTitle)
                        .foregroundStyle(DS.ink)
                }
                .padding(.top, DS.Space.m)

                // 生产日期
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("生产日期")
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.inkSecondary)
                    DatePicker("", selection: $birthDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                }

                // 产仔数
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("产仔数（可选）")
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.inkSecondary)
                    TextField("几只崽？", text: $kittenText)
                        .keyboardType(.numberPad)
                        .font(.system(size: 16))
                        .padding(DS.Space.s)
                        .background(
                            DS.surface,
                            in: RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                        )
                }

                Spacer()

                // 确认按钮
                Button {
                    onConfirm(birthDate, kittenCount)
                    dismiss()
                } label: {
                    Text("确认生产")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            DS.primaryGradient,
                            in: RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .padding(.bottom, DS.Space.m)
            }
            .padding(.horizontal, DS.Space.screenH)
            .navigationTitle("确认生产")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
