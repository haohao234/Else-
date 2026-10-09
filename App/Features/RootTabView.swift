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
    /// `private(set)` 是有意的：**切 tab 只能走 `go(to:)`**，
    /// 否则以后随便哪个页面写一句 `nav.tab = "cats"`，就会切得没有动画、
    /// 而且把方向判断也跳过去了 —— 这类"绕过唯一入口"的写法是最难查的一类不一致。
    @Published private(set) var tab: String = "home"

    /// 切换方向：新 tab 的序号更大 → 新页面从**右边**进来（跟系统的"前进"一个方向）。
    /// 反过来时从左边进来。这样滑动方向和用户的"向左/向右找东西"的直觉一致。
    @Published private(set) var slideFromRight = true

    @Published var homePath: [AppRoute] = []
    @Published var catsPath: [AppRoute] = []
    @Published var breedingPath: [AppRoute] = []
    @Published var financePath: [AppRoute] = []
    @Published var morePath: [AppRoute] = []

    /// tab 的顺序只在这里定义一次 —— 方向判断靠它。
    /// 写两份（这里一份、RootTabView 的 items 一份）迟早会不同步。
    static let tabOrder = ["home", "cats", "breeding", "finance", "more"]

    /// ⚠️ **想调手感就改这一行。**
    /// 用 easeOut 而不是 spring：曲线可预测、不会过冲。
    /// 这个动画我自己看不到（没有眼睛验它顺不顺），所以选"最不容易出错"的那条。
    /// 想要更"弹"一点可以换成：`.spring(response: 0.32, dampingFraction: 0.86)`
    /// 想更接近 iOS 系统 tab 的做法（系统其实**不**做滑动）就把它换成 `.easeInOut(duration: 0.18)` 并配淡入淡出。
    static let tabSwitch: Animation = .easeOut(duration: 0.26)

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

    /// **所有切 tab 的入口都走这里**（tab 栏点击、程序化跳转）。
    /// 于是"方向"和"动画"只需要在一个地方算对 ——
    /// 之前 tab 栏直接绑 `nav.tab`，点它就会绕过动画；而首页的「查看明细」
    /// 走的是程序化跳转，又是另一条路。两条路迟早会不一致。
    func go(to tab: String) {
        guard tab != self.tab else { return }
        let order = AppNav.tabOrder
        let old = order.firstIndex(of: self.tab) ?? 0
        let new = order.firstIndex(of: tab) ?? 0
        slideFromRight = new > old
        withAnimation(AppNav.tabSwitch) {
            self.tab = tab
        }
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
            // `.id(nav.tab)` 不能省：五个分支的视图**类型**都是 NavigationStack，
            // 不给一个随 tab 变化的身份，SwiftUI 会认为"还是同一个视图"，过渡根本不会触发。
            .id(nav.tab)
            .transition(tabTransition)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 滑动过程中，相邻那一页必须被裁掉 —— 否则它会露到屏幕边缘外面再滑进来，
            // 看起来像"整块布被拖出画面"，而不是"新页面盖上来"。
            .clipped()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // 二级页收起 tab 栏：编辑页底部有自己的保存条，两级底部控件叠在一起
                // 既挤又容易点错；这也是"页面层级"该有的视觉语言。
                if nav.currentDepth == 0 {
                    DSTabBar(items: items, selection: tabSelection)
                }
            }
        }
        .environmentObject(nav)
    }

    /// tab 栏的选中值走一个自定义 binding：setter 里调 `nav.go(to:)`，
    /// 这样"点 tab 栏"和"程序化跳转"走同一条路（方向和动画只在一处算）。
    private var tabSelection: Binding<String> {
        Binding(get: { nav.tab }, set: { nav.go(to: $0) })
    }

    /// 新页面从哪边进来 / 旧页面往哪边出去。
    /// 注意**两个方向是相反的**：新页从右进来时，旧页要往左退 ——
    /// 两边都往同一个方向滑的话，看起来是"两页一起平移"，没有前后关系。
    private var tabTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: nav.slideFromRight ? .trailing : .leading),
            removal: .move(edge: nav.slideFromRight ? .leading : .trailing)
        )
    }
}
