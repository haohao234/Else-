import SwiftUI

// MARK: - 记一次疫苗 / 驱虫
//
// 这一屏只干一件事：把"哪天做了什么"记下来。
// 所以字段只有三个，而**日期是唯一必填的** —— 名称/备注留空也成立
// （"3 月 5 日打过疫苗"本身就是一条完整的信息）。
//
// ⚠️ 它**不负责**"下次什么时候做"：
// 那是从记录 + 参考间隔**推**出来的，不在这里问用户。
// 存一份"下次日期"等于给自己造第二个真相 —— 改了记录忘了改它，两者就开始互相骗人。

struct HealthRecordEditView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let catID: UUID
    let editingID: UUID?

    @State private var draft = HealthDraft()
    @State private var baseline = HealthDraft()
    @State private var didLoad = false
    @State private var showDiscardAlert = false
    @State private var showDeleteConfirm = false
    @State private var reminderMade: String?

    init(catID: UUID, editingID: UUID?) {
        self.catID = catID
        self.editingID = editingID
    }

    private var isEditing: Bool { editingID != nil }
    private var touched: Bool { draft != baseline }
    private var catName: String { store.cat(id: catID)?.name ?? "这只猫" }

    var body: some View {
        DSScreen(title: isEditing ? "改记录" : "记一次",
                 onBack: { attemptClose() }) {
            whatCard
            // 「参考下次」只对**已存在的记录**显示：新记录还没保存时就算出"下次"，
            // 会让人以为那条推算已经被存下来了。
            if isEditing {
                planCard
                dangerZone
            }
        }
        .safeAreaInset(edge: .bottom) { saveBar }
        .onAppear(perform: loadIfNeeded)
        .alert("放弃这次记录？", isPresented: $showDiscardAlert) {
            Button("放弃", role: .destructive) { dismiss() }
            Button("继续填", role: .cancel) { }
        } message: {
            Text("已经填的内容不会保存。")
        }
    }

    // MARK: 记了什么

    private var whatCard: some View {
        DSCard {
            DSSectionHeader(title: "\(catName) 做了什么")
            DSMenuRow(label: "类型",
                      options: HealthKind.allCases.map { (value: $0, label: $0.label) },
                      selection: $draft.kind)
            DSDateRow(label: "日期", date: $draft.date)
            DSTextFieldRow(label: "名称", placeholder: "如 猫三联 加强 / 海乐妙", text: $draft.note)
            Text("名称可以留空 —— 「3 月 5 日打过疫苗」本身就是一条完整的信息。")
                .font(DS.Typo.caption)
                .foregroundStyle(DS.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 参考下次 + 加进提醒
    //
    // 这是记录与提醒之间**唯一**的桥：从记录推一个日期出来，让用户一键变成待办。
    // 不自动生成 —— 自动生成的话，用户会收到一堆他没确认过的待办，那比没有更烦。

    private var planCard: some View {
        DSCard {
            DSSectionHeader(title: "参考下次")
            if let next = draft.referenceNextDate {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                    Text(Formatters.monthDay.string(from: next))
                        .font(DS.Typo.statNumber)
                        .foregroundStyle(DS.primary)
                    Spacer(minLength: 0)
                    Text(HealthRecord.dueText(next))
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.inkTertiary)
                }
                Text("按「\(draft.kind.label)」常见的 \(draft.kind.referenceIntervalDays) 天间隔推算 —— 这只是参考，具体请以兽医和药品说明为准。")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                DSPrimaryButton(title: "按这个日期加一条提醒", height: 44) {
                    makeReminder(next)
                }
                if let reminderMade {
                    Text(reminderMade)
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("填上日期就能算出参考下次。")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.inkTertiary)
            }
        }
    }

    private var dangerZone: some View {
        VStack(spacing: DS.Space.s) {
            DSSectionHeader(title: "其他")
            DSActionRow(systemName: "trash",
                        title: "删除这条记录",
                        subtitle: "只在记错时用",
                        isDestructive: true,
                        showsChevron: false) {
                showDeleteConfirm = true
            }
        }
        .alert("删除这条记录？", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) {
                store.deleteHealth(id: editingID ?? UUID())
                dismiss()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("删除后无法撤销。")
        }
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            DSPrimaryButton(title: isEditing ? "保存修改" : "记下这一次", action: save)
                .padding(.horizontal, DS.Space.screenH)
                .padding(.vertical, DS.Space.m)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: 读写

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        if let editingID, let record = store.data.healthRecords.first(where: { $0.id == editingID }) {
            let snapshot = HealthDraft(record: record)
            baseline = snapshot
            draft = snapshot
        }
    }

    private func attemptClose() {
        if touched { showDiscardAlert = true } else { dismiss() }
    }

    private func save() {
        if let editingID, var existing = store.data.healthRecords.first(where: { $0.id == editingID }) {
            existing.kind = draft.kind
            existing.date = draft.date
            existing.note = draft.note.trimmed
            store.upsert(health: existing)
        } else {
            let record = HealthRecord(catID: catID,
                                      kind: draft.kind,
                                      date: draft.date,
                                      note: draft.note.trimmed)
            store.upsert(health: record)
        }
        dismiss()
    }

    /// 把"参考下次"变成一条真的提醒。**标题里带上猫名和内外驱** ——
    /// 提醒列表里同时有好几只猫的待办，一个光秃秃的"驱虫"过一周就没人认得出是给谁的。
    private func makeReminder(_ date: Date) {
        let title = "\(catName) · \(draft.kind.label)"
        let detail = draft.note.isEmpty ? "按上次记录推算" : "上次 \(Formatters.monthDay.string(from: draft.date))：\(draft.note)"
        let reminder = Reminder(kind: draft.kind.reminderKind,
                                title: title,
                                detail: detail,
                                dueDate: date,
                                catID: catID)
        store.upsert(reminder: reminder)
        NotificationService.reschedule(reminders: store.data.reminders)
        reminderMade = "已加进提醒：\(title) · \(Formatters.monthDay.string(from: date))。\n在「提醒通知」里能看到，也可以在那里改时间。"
    }
}

// MARK: - 记录草稿

private struct HealthDraft: Equatable {
    var kind: HealthKind = .vaccine
    var date: Date = Date()
    var note = ""

    init() { }

    init(record: HealthRecord) {
        kind = record.kind
        date = record.date
        note = record.note
    }

    /// 参考下一次（按类型的常见间隔推）
    var referenceNextDate: Date? {
        Calendar.current.date(byAdding: .day, value: kind.referenceIntervalDays, to: date)
    }
}
