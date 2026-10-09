import SwiftUI
import UIKit
import PhotosUI

// MARK: - 04 新增 / 编辑种猫
//
// 同一个视图承担"新增"和"编辑"：`editingID == nil` 就是新增。
// 拆成两个屏会让表单字段维护两份 —— 这是"两份必然漂移"的典型。
//
// 是否有改动，用**基线快照对比**（draft != baseline）而不是 onChange 打标记：
// 后者在"加载草稿"这一步就会把标记置脏，于是新增页什么都没填也弹"放弃编辑"。
// 这类 bug 的共性是：判据选错了对象（该比内容，却去数事件）。

struct CatEditView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let editingID: UUID?

    @State private var draft = CatDraft()
    @State private var baseline = CatDraft()
    @State private var didLoad = false
    @State private var showDiscardAlert = false

    // 头像单独放，**不进 draft**：draft 是 Equatable、每次敲键盘都要比一次，
    // 往里面塞几百 KB 的 Data 等于让每次输入都做一次大对象比较 —— 纯浪费。
    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedData: Data?
    @State private var pickedImage: UIImage?
    @State private var originalAvatarName: String?
    @State private var avatarRemoved = false

    init(editingID: UUID?) {
        self.editingID = editingID
    }

    private var isEditing: Bool { editingID != nil }
    private var touched: Bool { draft != baseline || pickedData != nil || avatarRemoved }
    private var canSave: Bool { !draft.name.trimmed.isEmpty }

    /// 该显示哪张头像：**草稿照片优先**，其次已保存的，最后是首字兜底。
    /// 这样"刚选完还没保存"时就能看到效果 —— 表单里最忌讳"点了没反应"。
    private var previewAvatar: UIImage? {
        if let pickedImage { return pickedImage }
        if avatarRemoved { return nil }
        return store.avatarImage(named: originalAvatarName)
    }

    var body: some View {
        DSScreen(title: isEditing ? "编辑种猫" : "新增种猫",
                 onBack: { attemptClose() }) {
            identityCard
            statusCard
            breedCard
        }
        .safeAreaInset(edge: .bottom) { saveBar }
        .onAppear(perform: loadIfNeeded)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            // loadTransferable 是异步的：照片可能要等 iCloud 下载。
            // Task 在 MainActor 上下文里创建，所以直接改 @State 是安全的。
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    pickedData = data
                    pickedImage = UIImage(data: data)
                    avatarRemoved = false
                }
            }
        }
        .alert("放弃这次编辑？", isPresented: $showDiscardAlert) {
            Button("放弃", role: .destructive) { dismiss() }
            Button("继续编辑", role: .cancel) { }
        } message: {
            Text("已经填的内容不会保存。")
        }
    }

    // MARK: 表单

    private var identityCard: some View {
        DSCard {
            DSSectionHeader(title: "它是谁")
            avatarRow
            DSTextFieldRow(label: "名字", placeholder: "如 Mochi", text: $draft.name)
            DSTextFieldRow(label: "呼名", placeholder: "如 麻薯（可留空）", text: $draft.callName)
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Text("性别")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.inkTertiary)
                DSSegmented(options: [(value: CatGender.female, label: "母"),
                                      (value: CatGender.male, label: "公")],
                            selection: $draft.gender)
            }
        }
    }

    private var avatarRow: some View {
        HStack(spacing: DS.Space.xl) {
            DSCatAvatar(name: draft.name, image: previewAvatar, size: 72)
            VStack(alignment: .leading, spacing: DS.Space.s) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Text(previewAvatar == nil ? "选一张头像" : "换一张照片")
                        .font(DS.Typo.rowTitle)
                        .foregroundStyle(DS.primary)
                }
                .buttonStyle(.plain)
                if previewAvatar != nil {
                    Button {
                        pickedData = nil
                        pickedImage = nil
                        avatarRemoved = true
                    } label: {
                        Text("移除头像")
                            .font(DS.Typo.caption)
                            .foregroundStyle(DS.inkTertiary)
                    }
                    .buttonStyle(.plain)
                }
                Text("照片只存本机，不会上传。")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.inkFaint)
            }
            Spacer(minLength: 0)
        }
    }

    private var statusCard: some View {
        DSCard {
            DSSectionHeader(title: "当前状态")
            statusMenu
            Text(statusHint)
                .font(DS.Typo.caption)
                .foregroundStyle(DS.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusMenu: some View {
        Menu {
            ForEach(CatStatus.allCases) { status in
                Button {
                    draft.status = status
                } label: {
                    Text(status.label)
                }
            }
        } label: {
            HStack(spacing: DS.Space.m) {
                Text("状态")
                    .font(DS.Typo.body)
                    .foregroundStyle(DS.inkSecondary)
                    .frame(width: 64, alignment: .leading)
                Spacer(minLength: 0)
                DSStatusChip(text: draft.status.label, tone: draft.status.tone)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.inkFaint)
            }
            .padding(.horizontal, DS.Space.l)
            .frame(height: DS.Metrics.inputHeight)
            .background(DS.input, in: RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous))
        }
    }

    private var statusHint: String {
        switch draft.status {
        case .breeding: return "在繁育计划里，可以参与配对"
        case .mating: return "正在配种，等确认怀孕"
        case .pregnant: return "已确认怀孕，注意预产期提醒"
        case .born: return "刚生产完，正在带小猫"
        case .retired: return "不再参与繁育，档案保留"
        }
    }

    private var breedCard: some View {
        DSCard {
            DSSectionHeader(title: "品种与身体数据")
            DSTextFieldRow(label: "品种", placeholder: "如 英国短毛猫", text: $draft.breed)
            DSTextFieldRow(label: "毛色", placeholder: "如 银渐层 Silver Shaded", text: $draft.coat)
            DSDateRow(label: "生日", date: $draft.birthDate)
            DSDigitFieldRow(label: "体重", unit: "kg", text: $draft.weightText)
            Text("体重与生日会用于详情页的年龄/体型展示，可以先留空，之后随时补。")
                .font(DS.Typo.caption)
                .foregroundStyle(DS.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 底部保存

    private var saveBar: some View {
        VStack(spacing: 0) {
            DSPrimaryButton(title: isEditing ? "保存修改" : "保存档案", action: save)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.45)
                .padding(.horizontal, DS.Space.screenH)
                .padding(.top, DS.Space.m)
                .padding(.bottom, DS.Space.m)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: 读写

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        if let id = editingID, let cat = store.cat(id: id) {
            let snapshot = CatDraft(cat: cat)
            baseline = snapshot
            draft = snapshot
            originalAvatarName = cat.avatarFileName
        }
    }

    private func attemptClose() {
        if touched { showDiscardAlert = true } else { dismiss() }
    }

    private func save() {
        let name = draft.name.trimmed
        guard !name.isEmpty else { return }
        // ⚠️ id 在这里就定下来（新增时也自己生成）：
        // 头像文件名是 `cat-<id>`，先有 id 才能一次 upsert 落库，
        // 否则得"先存猫、再回填文件名"，多一次写盘和一个中间态。
        let id = editingID ?? UUID()
        let weight = Double(draft.weightText.replacingOccurrences(of: ",", with: ".")) ?? 0

        var avatarName = originalAvatarName
        if let pickedData {
            avatarName = store.saveAvatar(pickedData, for: id)
        } else if avatarRemoved {
            store.removeAvatar(named: originalAvatarName)
            avatarName = nil
        }

        if var existing = store.cat(id: id) {
            existing.name = name
            existing.callName = draft.callName.trimmed
            existing.gender = draft.gender
            existing.breed = draft.breed.trimmed
            existing.coat = draft.coat.trimmed
            existing.birthDate = draft.birthDate
            existing.weightKg = weight
            existing.status = draft.status
            existing.avatarFileName = avatarName
            store.upsert(cat: existing)
        } else {
            let cat = Cat(id: id,
                          name: name,
                          callName: draft.callName.trimmed,
                          gender: draft.gender,
                          breed: draft.breed.trimmed,
                          coat: draft.coat.trimmed,
                          birthDate: draft.birthDate,
                          weightKg: weight,
                          status: draft.status,
                          avatarFileName: avatarName)
            store.upsert(cat: cat)
        }
        dismiss()
    }
}

// MARK: - 表单草稿
//
// 用草稿而不是直接绑到 Cat：编辑到一半按返回时，**原对象一个字都没被改过**。
// 直接绑的话，"取消"就变成了"改一半也生效"，这是表单最经典的坑。

private struct CatDraft: Equatable {
    var name = ""
    var callName = ""
    var gender: CatGender = .female
    var breed = ""
    var coat = ""
    var birthDate = Date()
    var weightText = ""
    var status: CatStatus = .breeding

    init() { }

    init(cat: Cat) {
        name = cat.name
        callName = cat.callName
        gender = cat.gender
        breed = cat.breed
        coat = cat.coat
        birthDate = cat.birthDate
        weightText = cat.weightKg > 0 ? String(format: "%.1f", cat.weightKg) : ""
        status = cat.status
    }
}
