import SwiftUI

// MARK: - 根容器：自绘底部导航 + 每个 tab 一个导航栈
//
// 设计稿用的是悬浮胶囊导航（不是系统 TabView），所以这里手写。
//
// 为什么把 tab 与各栈路径收进 `AppNav` 这个对象：
//   首页的「查看明细」要跳到**记账 tab** —— 跨 tab 跳转如果靠 @State 层层传
//   binding，RootTabView 会迅速退化成一个什么都往里塞的中转站。
//   收进一个对象之后，任何页面都能 `nav.go(to: "finance")`，且栈深可见（下面要用）。
//
// 为什么每层各有一个 path：一个 tab 里翻到第三层、切走再切回来，位置还在。
// 用一个共享 path 会让"在种猫里翻到详情、切到记账、再切回来"直接乱掉。

@MainActor
final class AppNav: ObservableObject {
    @Published var tab: String = "home"

    @Published var homePath: [AppRoute] = []
    @Published var catsPath: [AppRoute] = []
    @Published var breedingPath: [AppRoute] = []
    @Published var financePath: [AppRoute] = []
    @Published var morePath: [AppRoute] = []

    /// 当前 tab 的栈深。二级页要占满整屏，得靠它决定收不收起底部导航。
    var currentDepth: Int {
        switch tab {
        case "home": return homePath.count
        case "cats": return catsPath.count
        case "breeding": return breedingPath.count
        case "finance": return financePath.count
        default: return morePath.count
        }
    }

    func go(to tab: String) {
        self.tab = tab
    }

    /// 往**当前 tab** 的栈里压一屏。
    /// 为什么需要它：`NavigationLink(value:)` 只能在视图树里用；
    /// 而 `.contextMenu`（长按菜单）这类地方拿不到那个环境 —— 于是需要程序化压栈。
    /// 不判断当前 tab 就直接改某个 path 的话，切到别的 tab 会发现屏幕被"莫名"压了一屏。
    func push(_ route: AppRoute) {
        switch tab {
        case "home": homePath.append(route)
        case "cats": catsPath.append(route)
        case "breeding": breedingPath.append(route)
        case "finance": financePath.append(route)
        default: morePath.append(route)
        }
    }
}

struct RootTabView: View {
    @StateObject private var nav = AppNav()

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
                switch nav.tab {
                case "home":
                    NavigationStack(path: $nav.homePath) { HomeView().dsRoutes() }
                case "cats":
                    NavigationStack(path: $nav.catsPath) { CatsListView().dsRoutes() }
                case "breeding":
                    NavigationStack(path: $nav.breedingPath) { BreedingListView().dsRoutes() }
                case "finance":
                    NavigationStack(path: $nav.financePath) { FinanceListView().dsRoutes() }
                default:
                    NavigationStack(path: $nav.morePath) { MoreView().dsRoutes() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // 二级页收起 tab 栏：编辑页底部有自己的保存条，两级底部控件叠在一起
                // 既挤又容易点错；这也是"页面层级"该有的视觉语言。
                if nav.currentDepth == 0 {
                    DSTabBar(items: items, selection: $nav.tab)
                }
            }
        }
        .environmentObject(nav)
    }
}
