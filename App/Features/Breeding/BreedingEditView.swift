import SwiftUI

// MARK: - 新建 / 编辑配对
//
// 这一屏**只问"谁和谁"**：父母 + 编号 + 配对日期。
// 怀孕、生产、出窝不在这里填 —— 那些是随着时间推移才会发生的事实，
// 应该在实际发生的那天回到详情页补。把五个日期一次性摆在"新建"表单里，
// 会诱导用户瞎填未来日期，等于自己毁掉这个功能的可信度。
//
// 编号自动给一个（BR-年份-序号），但可以改 —— 猫舍往往有自己的编号习惯。

struct BreedingEditView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let editingID: UUID?

    @State private var code = ""
    @State private var motherID: UUID?
    @State private var fatherID: UUID?
    @State private var matedDate: Date = Date()
    @State private var note = ""
    @State private var didLoad = false

    init(editingID: UUID?) {
        self.editingID = editingID
    }

    private var isEditing: Bool { editingID != nil }

    private var females: [Cat] {
        store.data.cats.filter { $0.gender == .female }.sorted { $0.name < $1.name }
    }

    private var males: [Cat] {
        store.data.cats.filter { $0.gender == .male }.sorted { $0.name < $1.name }
    }

    private var canSave: Bool {
        !code.trimmed.isEmpty && motherID != nil && fatherID != nil && !females.isEmpty && !males.isEmpty
    }

    var body: some View {
        DSScreen(title: isEditing ? "编辑配对" : "新建配对",
                 onBack: { dismiss() }) {
            if females.isEmpty || males.isEmpty {
                missingCatsCard
            }
            parentsCard
            codeCard
        }
        .safeAreaInset(edge: .bottom) { saveBar }
        .onAppear(perform: loadIfNeeded)
    }

    private var missingCatsCard: some View {
        DSCard {
            DSSectionHeader(title: "先补齐种猫")
            Text(females.isEmpty ? "还没有母猫档案" : "还没有公猫档案")
                .font(DS.Typo.rowTitle)
                .foregroundStyle(DS.ink)
            Text("配对需要一只母猫和一只公猫。先去「种猫」里建好档案，再回来新建配对。")
                .font(DS.Typo.caption)
                .foregroundStyle(DS.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var parentsCard: some View {
        DSCard {
            DSSectionHeader(title: "谁和谁")
            DSMenuRow(label: "母亲",
                      options: females.map { (value: Optional($0.id), label: $0.name) },
                      selection: $motherID,
                      placeholder: "选择母猫")
            DSMenuRow(label: "父亲",
                      options: males.map { (value: Optional($0.id), label: $0.name) },
                      selection: $fatherID,
                      placeholder: "选择公猫")
            if let motherID, let fatherID,
               let mother = store.cat(id: motherID), let father = store.cat(id: fatherID) {
                Text("\(mother.name) × \(father.name)")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.primary)
            }
        }
    }

    private var codeCard: some View {
        DSCard {
            DSSectionHeader(title: "编号与时间")
            DSTextFieldRow(label: "编号", placeholder: "如 BR-2026-03", text: $code)
            DSDateRow(label: "配对日", date: $matedDate)
            DSNotesField(placeholder: "备注（可留空）：如「第二胎」「计划配种」", text: $note)
            Text("编号默认按年份自动排，改了也没关系；它只是给你自己看的。")
                .font(DS.Typo.caption)
                .foregroundStyle(DS.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            DSPrimaryButton(title: isEditing ? "保存配对" : "创建配对", action: save)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.45)
                .padding(.horizontal, DS.Space.screenH)
                .padding(.vertical, DS.Space.m)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: 读写

    private var suggestedCode: String {
        let year = Calendar.current.component(.year, from: Date())
        let prefix = "BR-\(year)-"
        let used = store.data.breedings.filter { $0.code.hasPrefix(prefix) }.count
        return prefix + String(format: "%02d", used + 1)
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        if let id = editingID, let record = store.breeding(id: id) {
            code = record.code
            motherID = record.motherID
            fatherID = record.fatherID
            matedDate = record.matedDate ?? Date()
            note = record.note
        } else {
            code = suggestedCode
            motherID = females.first?.id
            fatherID = males.first?.id
        }
    }

    private func save() {
        guard canSave, let motherID, let fatherID else { return }
        if let id = editingID, var existing = store.breeding(id: id) {
            existing.code = code.trimmed
            existing.motherID = motherID
            existing.fatherID = fatherID
            existing.matedDate = matedDate
            existing.note = note
            store.upsert(breeding: existing)
        } else {
            let record = BreedingRecord(code: code.trimmed,
                                        motherID: motherID,
                                        fatherID: fatherID,
                                        matedDate: matedDate,
                                        note: note)
            store.upsert(breeding: record)
        }
        dismiss()
    }
}
