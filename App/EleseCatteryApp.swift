import SwiftUI

// MARK: - App 入口
//
// ⚠️ 只有真机 / 模拟器编译才能真正裁决的三类问题（本工程当前的规避方式已写在注释里）：
//   1. `#Predicate` 宏的捕获限制 —— **本工程完全不用 SwiftData / #Predicate**，从源头规避；
//   2. Swift 6 严格并发下 delegate 的 nonisolated 标注 —— 工程停在 SWIFT_VERSION 5.0
//      + SWIFT_STRICT_CONCURRENCY=minimal，不会被升级成错误；想主动复现就改成 6.0 再编译；
//   3. 自定义 `Layout` 协议 —— 本工程不使用自定义 Layout，布局全走系统栈 + frame。

@main
struct EleseCatteryApp: App {

    /// 全局唯一的本地存储。App 是纯本地的，没有网络层，也没有其它注入依赖。
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
                .tint(DS.primary)
                // 设计稿只做了浅色一套，且主色在深底上会过曝。
                // 强制浅色，避免系统把未适配的界面渲染坏（Info.plist 里同时也写了 UIUserInterfaceStyle）。
                .preferredColorScheme(.light)
        }
    }
}
