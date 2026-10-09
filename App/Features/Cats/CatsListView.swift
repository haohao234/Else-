import SwiftUI

// MARK: - 02 种猫档案
//
// 列表页的通用结构（05 繁育、07 账单都照它）：大标题 + 搜索 + 筛选芯片 + 列表。
//
// 三种"空"必须分开表达，因为它们对应**完全不同的下一步动作**：
//   ① 一只猫都没有     → 主 CTA「新增第一只猫」
//   ② 筛掉了 / 搜不到  → 主 CTA「清空筛选」，次 CTA 才是「新增」
//   ③ 数据还没读出来   → 骨架屏（形状能让人预判内容，比转圈等待感低）
// 画布上的状态屏（11–15）讲的就是这件事；列表页不区分它们，是"空状态"最容易做废的地方。

struct CatsListView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var filter: CatStatus?

    private var allCats: [Cat] { store.data.cats }

    private var keyword: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var filtered: [Cat] {
        allCats.filter { cat in
            if let filter, cat.status != filter { return false }
            guard !keyword.isEmpty else { return true }
            return cat.name.localizedCaseInsensitiveContains(keyword)
                || cat.callName.localizedCaseInsensitiveContains(keyword)
                || cat.breed.localizedCaseInsensitiveContains(keyword)
                || cat.coat.localizedCaseInsensitiveContains(keyword)
        }
    }

    private var hasFilter: Bool { filter != nil || !keyword.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            DSScreenTitle(title: "种猫档案", trailing: AnyView(addButton))
            controls
            content
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: 右上角新增

    private var addButton: some View {
        NavigationLink(value: AppRoute.catEdit(nil)) {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(DS.primary, in: RoundedRectangle(cornerRadius: DS.Radius.iconButton, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: 搜索 + 筛选

    private var controls: some View {
        VStack(spacing: DS.Space.s) {
            DSSearchField(placeholder: "搜索名字 / 品种 / 毛色", text: $query)
                .padding(.horizontal, DS.Space.screenH)

            ScrollView(.horizontal) {
                HStack(spacing: DS.Space.xs) {
                    filterChip(title: "全部", active: filter == nil) { filter = nil }
                    ForEach(CatStatus.allCases) { status in
                        filterChip(title: status.label, active: filter == status) { filter = status }
                    }
                }
                .padding(.horizontal, DS.Space.screenH)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.bottom, DS.Space.m)
    }

    private func filterChip(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? .white : DS.inkSecondary)
                .padding(.horizontal, DS.Space.l)
                .frame(height: 32)
                .background(
                    active ? AnyShapeStyle(DS.primary) : AnyShapeStyle(DS.surface),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: 内容

    @ViewBuilder
    private var content: some View {
        if allCats.isEmpty {
            emptyNoCats
        } else if filtered.isEmpty {
            emptyNoMatch
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: DS.Space.s) {
                ForEach(filtered) { cat in
                    NavigationLink(value: AppRoute.catDetail(cat.id)) {
                        DSListRow {
                            DSCatAvatar(name: cat.name,
                                        image: store.avatarImage(named: cat.avatarFileName),
                                        size: 56)
                            VStack(alignment: .leading, spacing: DS.Space.xs) {
                                Text(cat.name)
                                    .font(DS.Typo.rowTitle)
                                    .foregroundStyle(DS.ink)
                                Text("\(cat.gender.label) · \(cat.breed) · \(cat.ageLine)")
                                    .font(DS.Typo.caption)
                                    .foregroundStyle(DS.inkTertiary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: DS.Space.s)
                            VStack(alignment: .trailing, spacing: DS.Space.xs) {
                                DSStatusChip(text: cat.status.label, tone: cat.status.tone)
                                Text("\(cat.litterCount) 胎")
                                    .font(DS.Typo.caption)
                                    .foregroundStyle(DS.inkTertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Space.screenH)
            .padding(.bottom, DS.Space.xxl)
        }
    }

    private var emptyNoCats: some View {
        VStack(spacing: 0) {
            Spacer(minLength: DS.Space.xxl * 2)
            DSEmptyState(systemName: "cat",
                         title: "还没有种猫档案",
                         message: "先把家里的公猫母猫建档\n之后每一胎的配对、生产都挂在它们身上",
                         hint: "数据只存在这台手机上，可随时导出备份") {
                DSPrimaryLink(title: "新增第一只猫", route: .catEdit(nil))
            }
            Spacer(minLength: 0)
        }
    }

    private var emptyNoMatch: some View {
        VStack(spacing: 0) {
            Spacer(minLength: DS.Space.xxl * 2)
            DSEmptyState(systemName: "magnifyingglass",
                         title: "没有符合条件的猫",
                         message: "换个关键词，或者清掉筛选条件试试",
                         hint: "搜的是名字、呼名、品种与毛色") {
                VStack(spacing: DS.Space.s) {
                    DSPrimaryButton(title: "清空筛选条件") {
                        query = ""
                        filter = nil
                    }
                    DSPrimaryLink(title: "新增一只猫", route: .catEdit(nil), height: 44)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
