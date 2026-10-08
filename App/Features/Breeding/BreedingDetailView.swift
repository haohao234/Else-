import SwiftUI

// MARK: - 06 繁育详情
//
// 这一屏是**日常真正在用的那一屏**：一胎从配到出窝，四个多月里会回来十几次，
// 每次回来说的都是同一句话 —— "这件事发生了，记一下"。
// 所以它同时是"详情"和"编辑器"：所有日期就地可改，底部一个保存条。
//
// 阶段（配对/怀孕/生产/出窝）**不在这里选** —— 它由日期推导（见 BreedingRecord.stage）。
// 用户只要诚实地填"哪天确认怀孕的""哪天生的"，阶段自然就对。
// 这也是这一屏最值得守住的一条：**不让用户维护一个能和事实打架的字段。**

struct BreedingDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let recordID: UUID

    @State private var draft = BreedingDraft()
    @State private var baseline = BreedingDraft()
    @State private var didLoad = false
    @State private var showDeleteConfirm = false
    @State private var showDiscardAlert = false

    init(recordID: UUID) {
        self.recordID = recordID
    }

    private var record: BreedingRecord? { store.breedingWithNames(id: recordID) }
    private var touched: Bool { draft != baseline }

    /// 实时预览"这么填之后算什么阶段" —— 让推导规则对用户是可见的。
    private var previewStage: BreedingStage {
        BreedingRecord.stage(matedDate: draft.matedDate,
                             pregnantDate: draft.pregnantDate,
                             birthDate: draft.birthDate,
                             weanedDate: draft.weanedDate)
    }

    var body: some View {
        if let record {
            DSScreen(title: record.code, onBack: { attemptClose() }) {
                headerCard(record)
                datesCard
                timelineCard
                costCard
                extraCard
                dangerZone
            }
            .safeAreaInset(edge: .bottom) { saveBar }
            .onAppear(perform: loadIfNeeded)
            .alert("放弃这次修改？", isPresented: $showDiscardAlert) {
                Button("放弃", role: .destructive) { dismiss() }
                Button("继续修改", role: .cancel) { }
            } message: {
                Text("已经改的内容不会保存。")
            }
        } else {
            notFound
        }
    }

    // MARK: 头部

    private func headerCard(_ record: BreedingRecord) -> some View {
        DSCard(radius: DS.Radius.cardLarge) {
            HStack {
                Text(record.title)
                    .font(DS.Typo.screenTitle)
                    .foregroundStyle(DS.ink)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.s)
                DSStatusChip(text: previewStage.label, tone: previewStage.tone)
            }
            DSStageProgress(filled: previewStage.completedCount)
            HStack(spacing: 0) {
                ForEach(BreedingStage.allCases) { stage in
                    let isCurrent = stage == previewStage
                    Text(stage.label)
                        .font(.system(size: 10, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? DS.primary : DS.inkTertiary)
                        .frame(maxWidth: .infinity,
                               alignment: stage == .mated ? .leading : (stage == .weaned ? .trailing : .center))
                }
            }
            if !record.note.isEmpty {
                Text(record.note)
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            NavigationLink(value: AppRoute.breedingEdit(record.id)) {
                HStack(spacing: DS.Space.xxs) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .semibold))
                    Text("改父母或编号")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(DS.primary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 记录日期（这一屏的正文：事实在这里填）

    private var datesCard: some View {
        DSCard {
            DSSectionHeader(title: "记录日期")
            Text("哪天真的发生了，就在哪天打开这里填一下 —— 阶段会自动跟着走。")
                .font(DS.Typo.caption)
                .foregroundStyle(DS.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)

            DSOptionalDateRow(label: "配对日", date: $draft.matedDate)
            DSOptionalDateRow(label: "怀孕", date: $draft.pregnantDate)
            DSOptionalDateRow(label: "预产期", date: $draft.expectedDueDate,
                              defaultDate: defaultDueDate)
            DSOptionalDateRow(label: "生产", date: $draft.birthDate)
            DSOptionalDateRow(label: "出窝", date: $draft.weanedDate)
        }
    }

    // MARK: 时间线（把填过的事实读成一段经历）

    private var timelineCard: some View {
        DSCard {
            DSSectionHeader(title: "时间线")
            if timelineEntries.isEmpty {
                Text("还没有填任何日期 —— 上面填一个，这里就会长出来。")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(timelineEntries.indices, id: \.self) { index in
                        let entry = timelineEntries[index]
                        DSTimelineStep(title: entry.title,
                                       dateText: Formatters.monthDay.string(from: entry.date),
                                       note: entry.note,
                                       isLast: index == timelineEntries.count - 1)
                    }
                }
            }
            if let total = BreedingRecord.totalDays(matedDate: draft.matedDate,
                                                    weanedDate: draft.weanedDate) {
                Text("从配对到出窝共 \(total) 天")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.primary)
            }
        }
    }

    /// 把草稿里填过的日期排成一条时间线（草稿，所以改了立刻反映）✓
    private var timelineEntries: [TimelineEntry] {
        var out: [TimelineEntry] = []
        if let d = draft.matedDate {
            out.append(TimelineEntry(id: "mated", title: "配对", date: d))
        }
        if let d = draft.pregnantDate {
            let gap = BreedingRecord.gestationDays(matedDate: draft.matedDate, birthDate: d)
            out.append(TimelineEntry(id: "pregnant", title: "确认怀孕", date: d,
                                     note: gap.map { "配对后 \($0) 天确认" }))
        }
        if let d = draft.expectedDueDate {
            // 预产期是**计划**，不是事实 —— 所以措辞上要区分开，不然回看时会把计划当成记录。
            out.append(TimelineEntry(id: "due", title: "预产期（计划）", date: d))
        }
        if let d = draft.birthDate {
            var notes: [String] = []
            if let g = BreedingRecord.gestationNote(matedDate: draft.matedDate, birthDate: d) { notes.append(g) }
            if let n = draft.kittenCount { notes.append("产仔 \(n) 只") }
            out.append(TimelineEntry(id: "birth", title: "生产", date: d,
                                     note: notes.isEmpty ? nil : notes.joined(separator: " · ")))
        }
        if let d = draft.weanedDate {
            var notes: [String] = []
            if let n = BreedingRecord.nursingNote(birthDate: draft.birthDate, weanedDate: d) { notes.append(n) }
            if let n = draft.kittenCount { notes.append("出窝 \(n) 只") }
            out.append(TimelineEntry(id: "weaned", title: "出窝", date: d,
                                     note: notes.isEmpty ? nil : notes.joined(separator: " · ")))
        }
        return out
    }

    // MARK: 配对以来的开销（派生，不存）

    /// 配对以来的开销。
    /// ⚠️ **口径必须写在界面上**：只统计"把公猫或母猫关联进去"的账单。
    /// 没关联猫的账（比如一袋猫砂）不算 —— 否则这个数字会变成一个说不清来源的数，
    /// 而说不清来源的数字比没有数字更糟（用户会拿它去做决定）。
    private var costSummary: (total: Double, count: Int, from: Date, to: Date)? {
        guard let record, let from = draft.matedDate ?? record.matedDate else { return nil }
        let to = draft.weanedDate ?? Date()
        let hit = store.data.bills.filter { bill in
            guard bill.date >= from, bill.date <= to else { return false }
            return bill.catIDs.contains(record.motherID) || bill.catIDs.contains(record.fatherID)
        }
        guard !hit.isEmpty else { return nil }
        return (store.total(of: hit), hit.count, from, to)
    }

    private var costCard: some View {
        DSCard {
            DSSectionHeader(title: "配对以来的开销")
            if let summary = costSummary, let record {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                    Text(Money.yuan(summary.total))
                        .font(DS.Typo.statNumber)
                        .foregroundStyle(DS.primary)
                    Spacer(minLength: 0)
                    Text("\(summary.count) 笔")
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.inkTertiary)
                }
                Text("\(Formatters.monthDay.string(from: summary.from)) 起 · 截至 \(Formatters.monthDay.string(from: summary.to))")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.inkTertiary)
                Text("只统计把 \(record.motherName) 或 \(record.fatherName) 关联进去的账单；没关联猫的账不算在内。")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("这段时间还没有关联到这对猫的账单。")
                    .font(DS.Typo.body)
                    .foregroundStyle(DS.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("在「记一笔」里把猫选上，这里就能看出这一胎大概花了多少。")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var extraCard: some View {
        DSCard {
            DSSectionHeader(title: "产仔与备注")
            DSDigitFieldRow(label: "产仔数", unit: "只", text: $draft.kittenText)
            DSNotesField(placeholder: "备注：如「B 超确认 5 个胎心」", text: $draft.note)
            if draft.birthDate != nil && draft.kittenCount == nil {
                Text("已经填了生产日期，建议把产仔数也填上 —— 出窝回访时要用。")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.alert)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var dangerZone: some View {
        VStack(spacing: DS.Space.s) {
            DSSectionHeader(title: "其他")
            DSActionRow(systemName: "trash",
                        title: "删除这条繁育记录",
                        subtitle: "只在录错时用；结束的胎次不必删",
                        isDestructive: true,
                        showsChevron: false) {
                showDeleteConfirm = true
            }
        }
        // ⚠️ 确认框挂在这一行自己身上，而不是和外层"放弃修改"并排挂在同一个视图上：
        // 两个 `.alert` 挂在同一个视图时只有最后一个会生效，另一个变成静默失效 ——
        // 这种 bug 在"点了删除没反应"时才暴露，而那时最容易去怀疑数据层。
        .alert("删除这条繁育记录？", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) {
                store.deleteBreeding(id: recordID)
                dismiss()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("删除后无法撤销。它下面的账单不会跟着删（账单是独立的一笔账）。")
        }
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            DSPrimaryButton(title: touched ? "保存进展" : "没有修改") {
                save()
            }
            .disabled(!touched)
            .opacity(touched ? 1 : 0.45)
            .padding(.horizontal, DS.Space.screenH)
            .padding(.vertical, DS.Space.m)
        }
        .background(.ultraThinMaterial)
    }

    private var notFound: some View {
        DSScreen(title: "繁育详情", onBack: { dismiss() }) {
            VStack(spacing: 0) {
                Spacer(minLength: DS.Space.xxl * 3)
                DSEmptyState(systemName: "questionmark.circle",
                             title: "找不到这条记录",
                             message: "它可能已经被删除了",
                             hint: nil)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: 读写

    /// 预产期默认值：猫的孕期按 65 天算（配种日 + 65）。
    /// 给默认值是为了让"填预产期"变成一次点击，而不是翻日历数两个月。
    private var defaultDueDate: Date {
        let base = draft.matedDate ?? Date()
        return Calendar.current.date(byAdding: .day, value: 65, to: base) ?? base
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let record else { return }
        let snapshot = BreedingDraft(record: record)
        baseline = snapshot
        draft = snapshot
    }

    private func attemptClose() {
        if touched { showDiscardAlert = true } else { dismiss() }
    }

    private func save() {
        guard var record = store.breeding(id: recordID) else { return }
        record.matedDate = draft.matedDate
        record.pregnantDate = draft.pregnantDate
        record.expectedDueDate = draft.expectedDueDate
        record.birthDate = draft.birthDate
        record.weanedDate = draft.weanedDate
        record.kittenCount = draft.kittenCount
        record.note = draft.note
        store.upsert(breeding: record)
        dismiss()
    }
}

// MARK: - 详情草稿
//
// 与 CatDraft 同一个思路：改到一半按返回，原记录一个字都没动。

private struct BreedingDraft: Equatable {
    var matedDate: Date?
    var pregnantDate: Date?
    var expectedDueDate: Date?
    var birthDate: Date?
    var weanedDate: Date?
    var kittenText = ""
    var note = ""

    init() { }

    init(record: BreedingRecord) {
        matedDate = record.matedDate
        pregnantDate = record.pregnantDate
        expectedDueDate = record.expectedDueDate
        birthDate = record.birthDate
        weanedDate = record.weanedDate
        kittenText = record.kittenCount.map { String($0) } ?? ""
        note = record.note
    }

    var kittenCount: Int? {
        let t = kittenText.trimmed
        guard !t.isEmpty else { return nil }
        return Int(t)
    }
}

// MARK: - 时间线上的一步
//
// 从草稿**现算**出来，而不是存一份：时间线的内容完全由那五个日期决定，
// 存一份就等于多了一个会和日期打架的真相（这份代码里已经吃过一次这个亏）。

private struct TimelineEntry: Identifiable {
    let id: String
    let title: String
    let date: Date
    var note: String? = nil
}
