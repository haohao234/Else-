import SwiftUI

// MARK: - 根容器：自绘底部导航
//
// 设计稿用的是悬浮胶囊导航（不是系统 TabView），所以这里手写。
// 用 `.safeAreaInset(edge:)` 承载它 —— 内容会自动获得正确底部内边距，
// 不需要每个屏各自加 padding（那种做法一定会有人在某一屏漏掉）。

struct RootTabView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection: String = "home"

    private let items: [DSTabItem] = [
        DSTabItem(id: "home", systemName: "house", title: "首页"),
        DSTabItem(id: "cats", systemName: "cat", title: "种猫"),
        DSTabItem(id: "breeding", systemName: "heart", title: "繁育"),
        DSTabItem(id: "finance", systemName: "creditcard", title: "记账"),
        DSTabItem(id: "more", systemName: "square.grid.2x2", title: "更多"),
    ]

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            Group {
                switch selection {
                case "home": HomeView()
                case "cats": CatsTabView()
                case "breeding": BreedingTabView()
                case "finance": FinanceTabView()
                default: MoreTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DSTabBar(items: items, selection: $selection)
            }
        }
    }
}

// MARK: - 以下四个 tab 的完整版在「阶段二」逐屏补齐。
// 现在它们都已经是**可编译、可运行**的真实视图（走同一套令牌与组件），
// 只是内容还没填满 —— 这样阶段一就能拿到编译器结论，而不是等全部写完才知道有没有错。

struct CatsTabView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            DSScreenTitle(title: "种猫档案")
            ScrollView {
                VStack(spacing: DS.Space.m) {
                    ForEach(store.data.cats) { cat in
                        DSListRow {
                            DSIconTile(systemName: "cat", size: 56)
                            VStack(alignment: .leading, spacing: DS.Space.xs) {
                                Text(cat.name).font(DS.Typo.rowTitle).foregroundStyle(DS.ink)
                                Text("\(cat.gender.label) · \(cat.ageLine) · \(Formatters.isoDay.string(from: cat.birthDate))")
                                    .font(DS.Typo.caption)
                                    .foregroundStyle(DS.inkTertiary)
                            }
                            Spacer(minLength: 0)
                            DSStatusChip(text: cat.status.label, tone: cat.status.tone)
                        }
                    }
                }
                .padding(.horizontal, DS.Space.screenH)
            }
        }
    }
}

struct BreedingTabView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            DSScreenTitle(title: "繁育记录")
            ScrollView {
                VStack(spacing: DS.Space.m) {
                    ForEach(store.breedingsWithNames) { record in
                        VStack(alignment: .leading, spacing: DS.Space.m) {
                            HStack {
                                Text(record.title).font(DS.Typo.cardTitle).foregroundStyle(DS.ink)
                                Spacer(minLength: DS.Space.s)
                                DSStatusChip(text: record.stage.label, tone: record.stage.tone)
                            }
                            DSStageProgress(filled: record.stage.completedCount)
                            HStack {
                                Text(record.progressLine).font(DS.Typo.caption).foregroundStyle(DS.inkTertiary)
                                Spacer(minLength: 0)
                                Text(record.code).font(.system(size: 10, design: .monospaced)).foregroundStyle(DS.inkTertiary)
                            }
                        }
                        .padding(DS.Space.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .dsRowSurface()
                    }
                }
                .padding(.horizontal, DS.Space.screenH)
            }
        }
    }
}

struct FinanceTabView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let month = Date()
        let bills = store.bills(in: month)
        let breakdown = store.breakdown(of: bills)

        return VStack(spacing: 0) {
            DSScreenTitle(title: "育猫记账")
            ScrollView {
                VStack(spacing: DS.Space.l) {
                    DSCard(radius: DS.Radius.cardLarge) {
                        Text("本月累计支出").font(DS.Typo.caption).foregroundStyle(DS.inkTertiary)
                        Text(Money.yuan(store.total(of: bills)))
                            .font(DS.Typo.heroAmount)
                            .foregroundStyle(DS.primary)
                    }

                    if breakdown.isEmpty {
                        DSEmptyState(systemName: "creditcard",
                                     title: "本月还没有记账",
                                     message: "猫粮、医疗、疫苗、配种费随手记下来\n月底就能看清钱花在哪",
                                     hint: "支持导出 CSV / Excel 到「文件」App")
                        .padding(.top, DS.Space.xxl * 2)
                    } else {
                        DSCard {
                            Text("分类占比").font(DS.Typo.cardTitle).foregroundStyle(DS.ink)
                            ForEach(breakdown, id: \.category) { item in
                                HStack {
                                    Circle().fill(DS.primary).frame(width: 8, height: 8)
                                    Text(item.category.label).font(DS.Typo.body).foregroundStyle(DS.inkSecondary)
                                    Spacer(minLength: DS.Space.s)
                                    Text(Money.yuan(item.amount))
                                        .font(DS.Typo.rowAmount)
                                        .foregroundStyle(DS.ink)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Space.screenH)
            }
        }
    }
}

struct MoreTabView: View {
    var body: some View {
        VStack(spacing: 0) {
            DSScreenTitle(title: "更多")
            ScrollView {
                VStack(spacing: DS.Space.m) {
                    DSEmptyState(systemName: "gearshape",
                                 title: "设置与备份",
                                 message: "设置页（本地备份 / 导出 / 提醒规则）在阶段二补齐\n已经砍掉了所有云同步相关的功能与文案",
                                 hint: "本 App 不联网、不埋点，数据只在本机")
                    .padding(.top, DS.Space.xxl * 3)
                }
                .padding(.horizontal, DS.Space.screenH)
            }
        }
    }
}
