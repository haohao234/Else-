import SwiftUI

// MARK: - 新建 / 编辑配对
//
// 这一屏问"谁和谁" + "什么时候配的" + "怀孕周期多少天"。
// 系统根据「配种日 + 周期」自动算出预产期，并创建一条到期提醒 ——
// 用户不用自己算日子、不用手动去提醒页加一条，填完配对信息就全自动。
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
    /// 怀孕周期（天）。默认 65，参考范围 58–72（见 BreedingRecord.gestationReference）。
    @State private var pregnancyCycleText = "65"
    @State private var note = ""
    @State private var didLoad = false

    init(editingID: UUID?) {
        self.editingID = editingID
    }

    private var isEditing: Bool { editingID != nil }

    /// 解析后的周期天数。非法输入回退到默认 65。
    private var pregnancyCycleDays: Int {
        let t = pregnancyCycleText.trimmed
        guard !t.isEmpty, let v = Int(t) else { return 65 }
        return max(BreedingRecord.gestationReference.lowerBound,
                   min(BreedingRecord.gestationReference.upperBound, v))
    }

    /// 自动计算的预产期 = 配种日 + 周期天数
    private var calculatedDueDate: Date? {
        Calendar.current.date(byAdding: .day, value: pregnancyCycleDays, to: matedDate)
    }

    private var dueDateLabel: String {
        guard let d = calculatedDueDate else { return "" }
        return Formatters.monthDay.string(from: d)
    }

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
            datesCard
        }
        .safeAreaInset(edge: .bottom) { saveBar }
        .onAppear(perform: loadIfNeeded)
    }

    // MARK: 缺少种猫

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

    // MARK: 父母

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

    // MARK: 日期与周期

    private var datesCard: some View {
        DSCard {
            DSSectionHeader(title: "编号与时间")
            DSTextFieldRow(label: "编号", placeholder: "如 BR-2026-03", text: $code)
            DSDateRow(label: "配对日", date: $matedDate)

            // 怀孕周期输入
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("怀孕周期（天）")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.inkTertiary)
                HStack(spacing: DS.Space.s) {
                    TextField("65", text: $pregnancyCycleText)
                        .keyboardType(.numberPad)
                        .font(DS.Typo.body)
                        .foregroundStyle(DS.ink)
                        .padding(.horizontal, DS.Space.l)
                        .frame(height: DS.Metrics.inputHeight)
                        .background(DS.input, in: RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous))

                    // 预产期预览
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("预产期")
                            .font(DS.Typo.caption)
                            .foregroundStyle(DS.inkTertiary)
                        Text(dueDateLabel.isEmpty ? "--" : dueDateLabel)
                            .font(DS.Typo.rowTitle)
                            .foregroundStyle(DS.primary)
                    }
                }
            }

            // 参考范围提示
            Text("猫的一般孕期为 \(BreedingRecord.gestationReference.lowerBound)–\(BreedingRecord.gestationReference.upperBound) 天（常见 63–65 天）。系统会按你填的天数自动算预产期并创建提醒。")
                .font(DS.Typo.caption)
                .foregroundStyle(DS.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)

            DSNotesField(placeholder: "备注（可留空）：如「第二胎」「计划配种」", text: $note)
            Text("编号默认按年份自动排，改了也没关系；它只是给你自己看的。")
                .font(DS.Typo.caption)
                .foregroundStyle(DS.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 底部保存

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
            // 编辑时：如果有已存的预产期，反推周期天数显示
            if let ed = record.expectedDueDate, let md = record.matedDate {
                let days = Calendar.current.dateComponents([.day], from: md, to: ed).day ?? 65
                pregnancyCycleText = String(days)
            }
        } else {
            code = suggestedCode
            motherID = females.first?.id
            fatherID = males.first?.id
        }
    }

    private func save() {
        guard canSave, let motherID, let fatherID else { return }

        let dueDate = calculatedDueDate

        if let id = editingID, var existing = store.breeding(id: id) {
            existing.code = code.trimmed
            existing.motherID = motherID
            existing.fatherID = fatherID
            existing.matedDate = matedDate
            existing.expectedDueDate = dueDate
            existing.note = note
            store.upsert(breeding: existing)
        } else {
            let record = BreedingRecord(code: code.trimmed,
                                        motherID: motherID,
                                        fatherID: fatherID,
                                        matedDate: matedDate,
                                        expectedDueDate: dueDate,
                                        note: note)
            store.upsert(breeding: record)
        }
        dismiss()
    }
}
