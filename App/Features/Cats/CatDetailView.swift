import SwiftUI

// MARK: - 03 种猫详情
//
// 详情页的信息层级（这个顺序不是随便定的）：
//   ① 它是谁 —— 头像 + 名字 + 呼名 + 状态（一眼确认找对了猫）
//   ② 它现在什么状态 —— 性别 / 年龄 / 体重（判断繁育安排要看这个）
//   ③ 它参与过什么 —— 关联繁育记录（这一屏真正的"正文"）
//   ④ 危险操作 —— 删除，放最下面且带确认（不放在导航栏，避免误触）

struct CatDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let catID: UUID

    @State private var showDeleteConfirm = false

    init(catID: UUID) {
        self.catID = catID
    }

    private var cat: Cat? { store.cat(id: catID) }

    private var relatedBreedings: [BreedingRecord] {
        store.breedingsWithNames
            .filter { $0.motherID == catID || $0.fatherID == catID }
            .sorted { $0.code > $1.code }
    }

    var body: some View {
        if let cat {
            DSScreen(title: cat.name,
                     onBack: { dismiss() },
                     trailing: AnyView(editLink(cat))) {
                headerCard(cat)
                factsCard(cat)
                remindersSection
                breedingsSection
                dangerZone(cat)
            }
            .alert("删除这只猫？", isPresented: $showDeleteConfirm) {
                Button("删除", role: .destructive) {
                    store.deleteCat(id: cat.id)
                    dismiss()
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("它名下的 \(relatedBreedings.count) 条繁育记录会一起删掉，且无法撤销。\n如果只是不再繁育，建议把状态改成「已退役」。")
            }
        } else {
            notFound
        }
    }

    private func editLink(_ cat: Cat) -> some View {
        NavigationLink(value: AppRoute.catEdit(cat.id)) {
            Image(systemName: "pencil")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.ink)
                .frame(width: 36, height: 36)
                .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.iconButton, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: ① 它是谁

    private func headerCard(_ cat: Cat) -> some View {
        DSCard(radius: DS.Radius.cardLarge) {
            HStack(spacing: DS.Space.xl) {
                DSCatAvatar(name: cat.name,
                            image: store.avatarImage(named: cat.avatarFileName),
                            size: 72)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(cat.name)
                        .font(DS.Typo.screenTitle)
                        .foregroundStyle(DS.ink)
                    if !cat.callName.isEmpty {
                        Text("呼名 \(cat.callName)")
                            .font(DS.Typo.caption)
                            .foregroundStyle(DS.inkTertiary)
                    }
                    HStack(spacing: DS.Space.xs) {
                        DSStatusChip(text: cat.gender.label, tone: .mid)
                        DSStatusChip(text: cat.status.label, tone: cat.status.tone)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: ② 它现在的状态

    private func factsCard(_ cat: Cat) -> some View {
        DSCard {
            DSSectionHeader(title: "基础信息")
            DSKeyValueRow(key: "品种", value: cat.breed.isEmpty ? "—" : cat.breed)
            DSKeyValueRow(key: "毛色", value: cat.coat.isEmpty ? "—" : cat.coat)
            DSKeyValueRow(key: "生日", value: Formatters.isoDay.string(from: cat.birthDate), monospaced: true)
            DSKeyValueRow(key: "年龄", value: cat.ageLine)
            DSKeyValueRow(key: "体重", value: String(format: "%.1f kg", cat.weightKg), monospaced: true)
            DSKeyValueRow(key: "累计", value: "\(cat.litterCount) 胎", monospaced: true)
        }
    }

    // MARK: ③ 它有什么待办

    /// 提醒**挂在猫身上**才活得下去：猫舍里同时好几只，
    /// 一个不带主语的"驱虫"过一周就没人认得出是给谁的。
    /// 所以详情页是"新增提醒"的第二入口（第一入口在提醒页的「+」）。
    private var remindersSection: some View {
        let open = store.openReminders(of: catID)
        return VStack(spacing: DS.Space.s) {
            DSSectionHeader(title: "它的待办")
            DSActionRow(systemName: "bell.badge",
                        title: "给它加个提醒",
                        subtitle: open.isEmpty ? "疫苗 / 驱虫 / 称重 / 预产期" : "已关联 \(open.count) 条",
                        showsChevron: true,
                        route: .reminderNew(catID: catID))
            ForEach(open.prefix(3)) { reminder in
                DSListRow {
                    let overdue = reminder.urgency == .overdue
                    DSIconTile(systemName: reminder.kind.symbol,
                               tint: overdue ? DS.alert : DS.primary,
                               background: overdue ? DS.alertSoft : DS.surfaceSoft)
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(reminder.title).font(DS.Typo.rowTitle).foregroundStyle(DS.ink)
                        Text(reminder.subtitle).font(DS.Typo.caption).foregroundStyle(DS.inkTertiary)
                    }
                    Spacer(minLength: DS.Space.s)
                    DSStatusChip(text: reminder.dueLabel.text,
                                 tone: reminder.dueLabel.isOverdue ? .alert : .archived)
                }
            }
            if open.count > 3 {
                Text("还有 \(open.count - 3) 条，到「提醒通知」里看全部")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Space.xxs)
            }
        }
    }

    // MARK: ④ 它参与过什么

    private var breedingsSection: some View {
        VStack(spacing: DS.Space.s) {
            if relatedBreedings.isEmpty {
                DSSectionHeader(title: "繁育记录")
                DSCard {
                    Text("还没有参与过繁育记录")
                        .font(DS.Typo.body)
                        .foregroundStyle(DS.inkTertiary)
                    Text("在「繁育」里新建一条配对，选它当母猫或公猫即可。")
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.inkFaint)
                }
            } else {
                ForEach(relatedBreedings) { record in
                    NavigationLink(value: AppRoute.breedingDetail(record.id)) {
                        VStack(alignment: .leading, spacing: DS.Space.s) {
                            HStack {
                                Text(record.title).font(DS.Typo.cardTitle).foregroundStyle(DS.ink)
                                Spacer(minLength: DS.Space.s)
                                DSStatusChip(text: record.stage.label, tone: record.stage.tone)
                            }
                            DSStageProgress(filled: record.stage.completedCount)
                            HStack {
                                Text(record.progressLine)
                                    .font(DS.Typo.caption)
                                    .foregroundStyle(DS.inkTertiary)
                                Spacer(minLength: 0)
                                Text(record.code)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(DS.inkTertiary)
                            }
                        }
                        .padding(DS.Space.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .dsRowSurface()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: ⑤ 危险操作

    private func dangerZone(_ cat: Cat) -> some View {
        VStack(spacing: DS.Space.s) {
            DSSectionHeader(title: "其他")
            DSActionRow(systemName: "trash",
                        title: "删除这只猫",
                        subtitle: "会连同它的繁育记录一起删除",
                        isDestructive: true,
                        showsChevron: false) {
                showDeleteConfirm = true
            }
            Text("这只猫的档案只存在这台手机上（文件：store.json）")
                .font(.system(size: 11))
                .foregroundStyle(DS.inkFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Space.xxs)
        }
    }

    // MARK: 兜底

    private var notFound: some View {
        DSScreen(title: "种猫详情", onBack: { dismiss() }) {
            VStack(spacing: 0) {
                Spacer(minLength: DS.Space.xxl * 3)
                DSEmptyState(systemName: "questionmark.circle",
                             title: "找不到这只猫",
                             message: "它可能已经被删除了",
                             hint: nil)
                Spacer(minLength: 0)
            }
        }
    }
}
