import SwiftUI

// MARK: - 新增 / 编辑提醒
//
// 这是"疫苗驱虫称重不用记在脑子里"这条承诺的**入口**。
// 之前这个模块只有一个列表和示例数据 —— 能看不能加，等于没有。
//
// 表单顺序 = 用户脑子里的顺序：
//   ① 是哪一类（疫苗 / 驱虫 / 称重 / B 超 / 预产期 / 出窝回访）—— 它决定了图标
//   ② 给谁（哪只猫）—— 猫舍里同时有好几只，不指定的话一周后自己都认不出
//   ③ 哪天到期 —— 只有日期是必填的，因为提醒的全部意义就是那个日期
//   ④ 说明（如"海乐妙 · 每月一次"）—— 可选，但回看时最有用
//
// 标题**可以留空**：留空就按"猫名 · 类型"自动生成（与「记一笔」同一条规则：
// 单据的名字不该是用户的负担）。想自己写就写。

struct ReminderEditView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let editingID: UUID?
    let presetCatID: UUID?

    @State private var draft = ReminderDraft()
    @State private var baseline = ReminderDraft()
    @State private var didLoad = false
    @State private var showDiscardAlert = false
    @State private var showDeleteConfirm = false

    init(editingID: UUID?, presetCatID: UUID?) {
        self.editingID = editingID
        self.presetCatID = presetCatID
    }

    private var isEditing: Bool { editingID != nil }
    private var touched: Bool { draft != baseline }

    /// 留空时用的标题。放在这里而不是塞进 draft —— 它是**派生值**，不该被存两次。
    private var suggestedTitle: String {
        if let cat = store.cat(id: draft.catID) { return "\(cat.name) · \(draft.kind.label)" }
        return draft.kind.label
    }

    var body: some View {
        DSScreen(title: isEditing ? "改提醒" : "新增提醒",
                 onBack: { attemptClose() }) {
            kindCard
            whoCard
            whenCard
            if isEditing { dangerZone }
        }
        .safeAreaInset(edge: .bottom) { saveBar }
        .onAppear(perform: loadIfNeeded)
        .alert("放弃这次编辑？", isPresented: $showDiscardAlert) {
            Button("放弃", role: .destructive) { dismiss() }
            Button("继续编辑", role: .cancel) { }
        } message: {
            Text("已经填的内容不会保存。")
        }
    }
    // MARK: ① 是哪一类

    private var kindCard: some View {
        DSCard {
            DSSectionHeader(title: "提醒什么")
            DSMenuRow(label: "类型",
                      options: ReminderKind.allCases.map { (value: $0, label: $0.label) },
                      selection: $draft.kind)
            HStack(spacing: DS.Space.m) {
                DSIconTile(systemName: draft.kind.symbol)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("标题")
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.inkTertiary)
                    Text(suggestedTitle)
                        .font(DS.Typo.rowTitle)
                        .foregroundStyle(DS.primary)
                }
                Spacer(minLength: 0)
            }
            DSTextFieldRow(label: "标题",
                           placeholder: "留空就用上面那个",
                           text: $draft.title)
            DSNotesField(placeholder: "说明（可留空）：如「海乐妙 · 每月一次」", text: $draft.detail)
        }
    }

    // MARK: ② 给谁

    private var whoCard: some View {
        DSCard {
            DSSectionHeader(title: "给谁")
            if store.data.cats.isEmpty {
                Text("还没有种猫档案。不关联也可以 —— 但关联之后，在它的详情页里就能看到这条待办。")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                DSMenuRow(label: "种猫",
                          options: [(value: Optional<UUID>.none, label: "不关联")]
                              + store.data.cats.map { (value: Optional($0.id), label: $0.name) },
                          selection: $draft.catID,
                          placeholder: "不关联")
            }
        }
    }

    // MARK: ③ 哪天几点

    private var whenCard: some View {
        DSCard {
            DSSectionHeader(title: "哪天几点")
            DSDateRow(label: "到期", date: $draft.dueDate, showsTime: true)
            timePresets
            Text("会在 \(Formatters.monthDayTime.string(from: draft.dueDate)) 提醒你一次（本地通知，不联网）。")
                .font(DS.Typo.caption)
                .foregroundStyle(DS.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            if Reminder.isPast(dueDate: draft.dueDate) {
                Text("这个时刻已经过去了 —— 它会直接出现在「已逾期」里，通知不会再响。")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.alert)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 常用时刻快捷键。猫舍里就那么几个时间点（早上喂药、中午、晚上），
    /// 让"几点"变成**一次点击**，而不是去滚轮里找 —— 手机上滚轮找分钟很烦。
    private var timePresets: some View {
        HStack(spacing: DS.Space.xs) {
            Text("常用")
                .font(DS.Typo.caption)
                .foregroundStyle(DS.inkTertiary)
            ForEach(Self.presetHours, id: \.self) { hour in
                let active = isPresetHour(hour)
                Button {
                    setHour(hour)
                } label: {
                    Text(String(format: "%02d:00", hour))
                        .font(.system(size: 12, weight: active ? .semibold : .regular))
                        .foregroundStyle(active ? .white : DS.inkSecondary)
                        .padding(.horizontal, DS.Space.m)
                        .frame(height: 30)
                        .background(active ? AnyShapeStyle(DS.primary) : AnyShapeStyle(DS.input),
                                    in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private var dangerZone: some View {
        VStack(spacing: DS.Space.s) {
            DSSectionHeader(title: "其他")
            DSActionRow(systemName: "trash",
                        title: "删除这条提醒",
                        subtitle: "做完的事不必删，点一下就划掉了",
                        isDestructive: true,
                        showsChevron: false) {
                showDeleteConfirm = true
            }
        }
        .alert("删除这条提醒？", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) {
                store.deleteReminder(id: editingID ?? UUID())
                reschedule()
                dismiss()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("删除后无法撤销。")
        }
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            // 这里的按钮**永远可点**：提醒只有"哪天到期"是必填的，而日期永远有值；
            // 标题留空会自动生成。**不给一个"看起来该亮却没亮"的按钮** ——
            // 那种按钮会让人反复检查自己是不是漏填了什么。
            DSPrimaryButton(title: isEditing ? "保存修改" : "加进待办", action: save)
                .padding(.horizontal, DS.Space.screenH)
                .padding(.vertical, DS.Space.m)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: 读写

    /// 常用时刻。加新的往这里加一行即可。
    private static let presetHours = [9, 12, 20]

    /// 新增时的默认到期时刻：**今天 9:00；若已过 9:00 就顺到明天 9:00**。
    /// 为什么不直接给"此刻"：默认值要像一个"明天该做的事"，
    /// 给"此刻"会立刻变成已逾期（用户一进来就看到红色的东西，是很糟的第一印象）。
    private static var defaultDueDate: Date {
        let cal = Calendar.current
        let now = Date()
        let todayNine = cal.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
        if todayNine > now { return todayNine }
        return cal.date(byAdding: .day, value: 1, to: todayNine) ?? todayNine
    }

    private func isPresetHour(_ hour: Int) -> Bool {
        let cal = Calendar.current
        return cal.component(.hour, from: draft.dueDate) == hour
            && cal.component(.minute, from: draft.dueDate) == 0
    }

    private func setHour(_ hour: Int) {
        let cal = Calendar.current
        draft.dueDate = cal.date(bySettingHour: hour, minute: 0, second: 0, of: draft.dueDate) ?? draft.dueDate
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        if let id = editingID, let reminder = store.data.reminders.first(where: { $0.id == id }) {
            let snapshot = ReminderDraft(reminder: reminder)
            baseline = snapshot
            draft = snapshot
        } else {
            // 新增：只把"从某只猫进来"的预选和一个体面的默认时刻填上，其余留空让用户自己写 ——
            // 预填太多会让人以为那是系统给定的值，反而不敢改。
            var fresh = ReminderDraft()
            fresh.catID = presetCatID
            fresh.dueDate = Self.defaultDueDate
            baseline = fresh
            draft = fresh
        }
    }

    private func attemptClose() {
        if touched { showDiscardAlert = true } else { dismiss() }
    }

    private func save() {
        let title = draft.title.trimmed.isEmpty ? suggestedTitle : draft.title.trimmed
        if let id = editingID, var existing = store.data.reminders.first(where: { $0.id == id }) {
            existing.kind = draft.kind
            existing.title = title
            existing.detail = draft.detail.trimmed
            existing.dueDate = draft.dueDate
            existing.catID = draft.catID
            store.upsert(reminder: existing)
        } else {
            let reminder = Reminder(kind: draft.kind,
                                    title: title,
                                    detail: draft.detail.trimmed,
                                    dueDate: draft.dueDate,
                                    catID: draft.catID)
            store.upsert(reminder: reminder)
        }
        reschedule()
        dismiss()
    }

    /// 提醒变了就重排本地通知 —— 不重排的话，用户改了日期而通知还响在旧的哪天，
    /// 这比没有通知更伤人（会让人开始不信任提醒）。
    private func reschedule() {
        NotificationService.reschedule(reminders: store.data.reminders)
    }
}

// MARK: - 提醒草稿

private struct ReminderDraft: Equatable {
    var kind: ReminderKind = .vaccine
    var title = ""
    var detail = ""
    var dueDate: Date = Date()
    var catID: UUID?

    init() { }

    init(reminder: Reminder) {
        kind = reminder.kind
        title = reminder.title
        detail = reminder.detail
        dueDate = reminder.dueDate
        catID = reminder.catID
    }
}
