import SwiftUI

// MARK: - 全 App 的二级页路由
//
// 为什么做成 enum + `navigationDestination(for:)`，而不是到处写
// `NavigationLink(destination: SomeView())`：
//   1. 后者会在**每一处入口**都立刻构造目标视图（哪怕马上被丢弃），
//      而且"这一屏能从哪些地方进"变成隐式的、散落在各文件里；
//   2. 集中成一条路由表之后，"加一屏"只改两个地方（enum + 下面那个 switch），
//      而且漏了分支编译器会直接报错 —— 这正是我们想要的失败方式。
//
// ⚠️ 每个 tab 各自持有自己的 path（RootTabView 里），
//    这样一个 tab 里翻到第三层、切走再切回来，位置还在。

enum AppRoute: Hashable {
    case catDetail(UUID)
    case catEdit(UUID?)          // nil = 新增种猫
    case breedingDetail(UUID)
    case breedingEdit(UUID?)     // nil = 新建配对
    case billEdit(UUID?)         // nil = 记一笔
    case reminders
    case reminderNew(catID: UUID?)   // nil = 不预选猫（从提醒页加）
    case reminderEdit(UUID)
    case healthEdit(catID: UUID, recordID: UUID?)   // recordID nil = 记一次新的
    case settings
}

extension View {
    /// 给每个 tab 的根视图装同一套二级页。
    /// 必须装在**每个 NavigationStack 内部**——navigationDestination 只对它所在的那个栈生效。
    func dsRoutes() -> some View {
        navigationDestination(for: AppRoute.self) { route in
            switch route {
            case .catDetail(let id): CatDetailView(catID: id)
            case .catEdit(let id): CatEditView(editingID: id)
            case .breedingDetail(let id): BreedingDetailView(recordID: id)
            case .breedingEdit(let id): BreedingEditView(editingID: id)
            case .billEdit(let id): BillEditView(editingID: id)
            case .reminders: RemindersView()
            case .reminderNew(let catID): ReminderEditView(editingID: nil, presetCatID: catID)
            case .reminderEdit(let id): ReminderEditView(editingID: id, presetCatID: nil)
            case .healthEdit(let catID, let recordID): HealthRecordEditView(catID: catID, editingID: recordID)
            case .settings: SettingsView()
            }
        }
    }
}

// MARK: - 二级页的公共外壳
//
// 设计稿的二级页一律是：自绘导航栏（返回 + 居中标题 + 右侧动作）+ 可滚动内容。
// 抽出来是因为 6 个二级页都要这一套，各写一份必然会有人漏掉某个 padding。
//
// ⚠️ 右侧动作故意用 `AnyView?` 而不是第三个泛型参数：
//    泛型版会让 init 出现**两个闭包参数**（trailing 与 content），
//    而 `onBack` 也是闭包类型、还有默认值 —— 多个尾随闭包在这种签名下
//    绑定到哪个参数是含糊的，属于"看着能编过、其实绑错"的那类问题。
//    只留一个闭包参数（content），调用处就不可能绑错。

struct DSScreen<Content: View>: View {
    let title: String
    var onBack: (() -> Void)? = nil
    var trailing: AnyView? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            DSNavBar(title: title, onBack: onBack) {
                if let trailing { trailing }
            }
            ScrollView {
                VStack(spacing: DS.Space.l) { content }
                    .padding(.horizontal, DS.Space.screenH)
                    .padding(.bottom, DS.Space.xxl * 2)
            }
            // 数字键盘（金额、体重）**没有回车键**，所以给它一条退路：
            // 拖动表单 → 键盘跟着手势收起来。
            //
            // ⚠️⚠️ **不要再往这里加任何 TapGesture**（包括 simultaneousGesture）。
            // 曾经加过一条"点空白处收起键盘"，结果**把整屏的按钮点按全部吃掉了** ——
            // 二级页所有功能都点不动，只有底部 tab 还能切（它在这个手势之外）。
            // 用户实测报回来的原话：「所有功能都用不了，除了滑动动画」。
            // 教训：**在容器上加手势，会改变整棵子树的命中判定**；
            //       而这类问题编译、静态检查、拆包自验**一个都发现不了**。
            //       要拦截点按，只用"自己那一层的" onTapGesture（比如给一个 Color.clear 层），
            //       绝不要加在 ScrollView 这种包着全部内容的容器上。
            .scrollDismissesKeyboard(.interactively)
        }
        // 用自绘导航栏取代系统导航栏：设计稿的标题是**居中**的，
        // 而系统导航栏的标题会跟着大标题模式变成左对齐。
        .toolbar(.hidden, for: .navigationBar)
    }
}
