import SwiftUI

// MARK: - 08 记一笔
//
// 记一笔的黄金标准是**三秒内能记完**：金额 → 分类 → 保存。
// 所以表单顺序就是使用频率顺序，而且日期默认"今天"（绝大多数账是当天记的）。
//
// 金额用 String 而不是 Double 绑定：用户敲到一半的 "12." 不该被解析，
// 也不该在输入过程中被格式化 —— 边打边加千分位是最招人烦的交互之一。

struct BillEditView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let editingID: UUID?

    @State private var draft = BillDraft()
    @State private var baseline = BillDraft()
    @State private var didLoad = false
    @State private var showDiscardAlert = false
    @State private var showDeleteConfirm = false

    init(editingID: UUID?) {
        self.editingID = editingID
    }

    private var isEditing: Bool { editingID != nil }
    private var touched: Bool { draft != baseline }
    private var canSave: Bool { draft.amount > 0 }

    var body: some View {
        DSScreen(title: isEditing ? "改这一笔" : "记一笔",
                 onBack: { attemptClose() }) {
            amountCard
            categoryCard
            detailCard
            if isEditing {
                dangerZone
            }
        }
        .safeAreaInset(edge: .bottom) { saveBar }
        .onAppear(perform: loadIfNeeded)
        .alert("放弃这次记录？", isPresented: $showDiscardAlert) {
            Button("放弃", role: .destructive) { dismiss() }
            Button("继续填写", role: .cancel) { }
        } message: {
            Text("已经填的内容不会保存。")
        }
    }

    // MARK: 金额

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("金额")
                .font(DS.Typo.caption)
                .foregroundStyle(DS.inkTertiary)
            DSMoneyField(text: $draft.amountText)
            if !draft.amountText.trimmed.isEmpty && draft.amount <= 0 {
                Text("金额要是一个大于 0 的数字")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.alert)
            }
        }
    }

    // MARK: 分类

    private var categoryCard: some View {
        DSCard {
            DSSectionHeader(title: "花在哪")
            DSCategoryGrid(selection: $draft.category)
        }
    }

    // MARK: 明细

    private var detailCard: some View {
        DSCard {
            DSSectionHeader(title: "明细")
            DSTextFieldRow(label: "标题", placeholder: "如 皇家幼猫粮 2kg", text: $draft.title)
            DSDateRow(label: "日期", date: $draft.date)
            DSNotesField(placeholder: "备注（可留空）", text: $draft.note)
            catPicker
        }
    }

    private var catPicker: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("关联猫咪（选填）")
                .font(DS.Typo.caption)
                .foregroundStyle(DS.inkTertiary)
            if store.data.cats.isEmpty {
                Text("还没有种猫档案，先去「种猫」里建一只，之后这笔账就能挂在它名下。")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: DS.Space.s)],
                          alignment: .leading,
                          spacing: DS.Space.s) {
                    ForEach(store.data.cats) { cat in
                        let active = draft.catIDs.contains(cat.id)
                        Button {
                            toggle(cat.id)
                        } label: {
                            Text(cat.name)
                                .font(.system(size: 12, weight: active ? .semibold : .regular))
                                .foregroundStyle(active ? .white : DS.inkSecondary)
                                .lineLimit(1)
                                .padding(.horizontal, DS.Space.m)
                                .frame(height: 34)
                                .frame(maxWidth: .infinity)
                                .background(
                                    active ? AnyShapeStyle(DS.primary) : AnyShapeStyle(DS.input),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var dangerZone: some View {
        VStack(spacing: DS.Space.s) {
            DSSectionHeader(title: "其他")
            DSActionRow(systemName: "trash",
                        title: "删除这一笔",
                        subtitle: "只在记错时用",
                        isDestructive: true,
                        showsChevron: false) {
                showDeleteConfirm = true
            }
        }
        .alert("删除这一笔支出？", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) {
                store.deleteBill(id: editingID ?? UUID())
                dismiss()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("删除后无法撤销。")
        }
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            DSPrimaryButton(title: isEditing ? "保存修改" : "记下这一笔", action: save)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.45)
                .padding(.horizontal, DS.Space.screenH)
                .padding(.vertical, DS.Space.m)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: 读写

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        if let id = editingID, let bill = store.data.bills.first(where: { $0.id == id }) {
            let snapshot = BillDraft(bill: bill)
            baseline = snapshot
            draft = snapshot
        }
    }

    private func toggle(_ id: UUID) {
        if let idx = draft.catIDs.firstIndex(of: id) {
            draft.catIDs.remove(at: idx)
        } else {
            draft.catIDs.append(id)
        }
    }

    private func attemptClose() {
        if touched { showDiscardAlert = true } else { dismiss() }
    }

    private func save() {
        guard canSave else { return }
        let title = draft.title.trimmed
        let finalTitle = title.isEmpty ? draft.category.label : title

        if let id = editingID, var existing = store.data.bills.first(where: { $0.id == id }) {
            existing.title = finalTitle
            existing.category = draft.category
            existing.amount = draft.amount
            existing.date = draft.date
            existing.note = draft.note.trimmed
            existing.catIDs = draft.catIDs
            store.upsert(bill: existing)
        } else {
            let bill = Bill(title: finalTitle,
                            category: draft.category,
                            amount: draft.amount,
                            date: draft.date,
                            note: draft.note.trimmed,
                            catIDs: draft.catIDs)
            store.upsert(bill: bill)
        }
        dismiss()
    }
}

// MARK: - 账单草稿

private struct BillDraft: Equatable {
    var amountText = ""
    var title = ""
    var category: BillCategory = .food
    var date: Date = Date()
    var note = ""
    var catIDs: [UUID] = []

    init() { }

    init(bill: Bill) {
        amountText = bill.amount > 0 ? String(format: "%.0f", bill.amount) : ""
        title = bill.title
        category = bill.category
        date = bill.date
        note = bill.note
        catIDs = bill.catIDs
    }

    /// 金额解析：允许用户敲中英文逗号/句点当小数点，也允许首尾空格。
    /// 解析失败一律当 0 —— 上层用 `amount > 0` 做保存闸门。
    var amount: Double {
        let cleaned = amountText.trimmed.replacingOccurrences(of: ",", with: ".")
        return Double(cleaned) ?? 0
    }
}
