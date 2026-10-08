import SwiftUI

// MARK: - 更多（第 5 个 tab）
//
// 这一屏存在的意义：把"不常点但必须有"的东西收在一处，
// 让前四个 tab 保持只有一件正事。所以它只放三样：
//   · 数据概览（我现在有多少东西）
//   · 设置入口（备份 / 导出 / 提醒开关）
//   · 一句承诺（不联网、数据只在本机）
//
// ⚠️ 这里**不出现** iCloud / 云同步 / 账号相关的任何入口与文案。

struct MoreView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var nav: AppNav

    var body: some View {
        VStack(spacing: 0) {
            DSScreenTitle(title: "更多")
            ScrollView {
                VStack(spacing: DS.Space.l) {
                    // 数据出问题时，在"更多"这一屏也要能看到 ——
                    // 设置页只有一个入口，而这件事等不了用户自己找过去。
                    if let problem = store.loadProblem {
                        DSAlertCard(title: "数据文件读不出来",
                                    message: problem,
                                    hint: "处理办法在「设置 · 备份与导出」里（红框那条下面就是）。")
                    }
                    overviewCard
                    entries
                    promiseCard
                }
                .padding(.horizontal, DS.Space.screenH)
                .padding(.bottom, DS.Space.xxl * 2)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var overviewCard: some View {
        DSCard(radius: DS.Radius.cardLarge) {
            DSSectionHeader(title: "我的数据")
            HStack(alignment: .top, spacing: DS.Space.m) {
                DSStatTile(value: "\(store.data.cats.count)", label: "种猫")
                DSStatTile(value: "\(store.data.breedings.count)", label: "繁育记录")
                DSStatTile(value: "\(store.data.bills.count)", label: "账单")
                DSStatTile(value: "\(store.openReminders.count)", label: "待办")
            }
            Text("这四个数字只统计本机这一份 store.json。App 不联网，也没有第二份副本。")
                .font(DS.Typo.caption)
                .foregroundStyle(DS.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var entries: some View {
        VStack(spacing: DS.Space.s) {
            DSSectionHeader(title: "管理")
            DSActionRow(systemName: "gearshape",
                        title: "设置 · 备份与导出",
                        subtitle: "本地备份 / 导出账单 CSV / 恢复") {
                nav.morePath.append(.settings)
            }
            DSActionRow(systemName: "bell",
                        title: "提醒通知",
                        subtitle: store.openReminders.isEmpty ? "眼下没有待办" : "\(store.openReminders.count) 条待办 · 逾期 \(store.overdueCount) 条",
                        detail: store.overdueCount > 0 ? "\(store.overdueCount) 逾期" : nil) {
                nav.morePath.append(.reminders)
            }
        }
    }

    private var promiseCard: some View {
        DSCard {
            HStack(spacing: DS.Space.m) {
                DSIconTile(systemName: "lock.shield", tint: DS.primary)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("数据只在这台手机上")
                        .font(DS.Typo.rowTitle)
                        .foregroundStyle(DS.ink)
                    Text("没有账号、不联网、不埋点。备份文件存在你自己选的地方。")
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
