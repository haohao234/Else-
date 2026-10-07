import SwiftUI
import UserNotifications

// MARK: - 10 设置 · 备份与导出
//
// ⚠️ 这一屏有一条硬约束：**不出现 iCloud / 云同步 / 云账号相关的任何文案与图标。**
//    这不是"还没做"，是产品决定 —— 数据只在本机，所以设置页只做「本地备份 + 导出」两件事。
//
// 为什么备份和导出要分成两个入口：它们是两个不同的目的 ——
//   · 备份：**给将来的自己**用的（换手机、误删之后恢复），所以格式是完整的 JSON
//   · 导出：**给现在的自己**用的（想用 Excel 算一笔账），所以格式是账单 CSV
// 合成一个按钮的话，用户永远不知道点下去是哪一个。

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var backups: [URL] = []
    @State private var showRestoreList = false
    @State private var pendingRestore: URL?
    @State private var message: String?
    @State private var authStatus: UNAuthorizationStatus = .notDetermined

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        DSScreen(title: "设置", onBack: { dismiss() }) {
            if let message {
                banner(message)
            }
            dataCard
            if showRestoreList {
                restoreListCard
            }
            reminderCard
            aboutCard
        }
        .onAppear(perform: refresh)
        .alert("用这份备份覆盖当前数据？", isPresented: Binding(
            get: { pendingRestore != nil },
            set: { if !$0 { pendingRestore = nil } }
        )) {
            Button("覆盖恢复", role: .destructive) { performRestore() }
            Button("取消", role: .cancel) { pendingRestore = nil }
        } message: {
            Text("当前的种猫、繁育、账单、提醒会被这份备份「整体替换」，且无法撤销。\n建议先创建一份现在的备份再恢复。")
        }
    }

    // MARK: 顶部提示条

    private func banner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(DS.primary)
            Text(text)
                .font(DS.Typo.caption)
                .foregroundStyle(DS.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                message = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.inkTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surfaceSoft, in: RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous))
    }

    // MARK: 数据

    private var dataCard: some View {
        VStack(spacing: DS.Space.s) {
            DSSectionHeader(title: "数据")
            DSActionRow(systemName: "externaldrive.badge.timemachine",
                        title: "创建本地备份",
                        subtitle: "完整快照（JSON），存到「文件」App 里能看到的目录") {
                makeBackup()
            }
            DSActionRow(systemName: "tablecells",
                        title: "导出账单 CSV",
                        subtitle: "全是支出明细，可直接用 Excel / 数字表格打开") {
                exportBillsCSV()
            }
            DSActionRow(systemName: "arrow.clockwise",
                        title: "从备份恢复",
                        subtitle: showRestoreList ? "选一份备份覆盖当前数据" : "换手机、误删之后用",
                        detail: backups.isEmpty ? "暂无备份" : "\(backups.count) 份",
                        showsChevron: true) {
                showRestoreList.toggle()
                if showRestoreList { refresh() }
            }
        }
    }

    private var restoreListCard: some View {
        VStack(spacing: DS.Space.s) {
            if backups.isEmpty {
                DSCard {
                    Text("还没有备份")
                        .font(DS.Typo.rowTitle)
                        .foregroundStyle(DS.ink)
                    Text("先点上面的「创建本地备份」，之后这里会列出每一次备份。")
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(backups, id: \.self) { url in
                    Button {
                        pendingRestore = url
                    } label: {
                        DSListRow {
                            DSIconTile(systemName: "doc.text", tint: DS.primary)
                            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                                Text(fileStamp(url))
                                    .font(DS.Typo.rowTitle)
                                    .foregroundStyle(DS.ink)
                                    .monospacedDigit()
                                Text(BackupService.summary(of: url))
                                    .font(DS.Typo.caption)
                                    .foregroundStyle(DS.inkTertiary)
                            }
                            Spacer(minLength: DS.Space.s)
                            Text(BackupService.sizeText(of: url))
                                .font(DS.Typo.caption)
                                .foregroundStyle(DS.inkFaint)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 提醒

    private var reminderCard: some View {
        VStack(spacing: DS.Space.s) {
            DSSectionHeader(title: "提醒")
            DSActionRow(systemName: "bell",
                        title: "本地通知",
                        subtitle: "到期当天 9:00 提醒，不联网",
                        detail: NotificationService.statusText(authStatus),
                        showsChevron: false) {
                openNotifications()
            }
        }
    }

    // MARK: 关于

    private var aboutCard: some View {
        DSCard {
            DSSectionHeader(title: "关于")
            DSKeyValueRow(key: "版本", value: appVersion, monospaced: true)
            DSKeyValueRow(key: "数据", value: "只存本机")
            Text("Elese的猫舍没有账号、不联网、不统计使用行为。\n所有档案都只在这台手机上；备份文件存在你自己选的地方。\n换手机之前，记得先做一次备份。")
                .font(DS.Typo.caption)
                .foregroundStyle(DS.inkTertiary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 动作

    private func refresh() {
        backups = (try? BackupService.listBackups(in: BackupService.folder(in: store.documentsDirectory))) ?? []
        NotificationService.authorizationStatus { status in
            authStatus = status
        }
    }

    private func makeBackup() {
        do {
            let folder = try BackupService.folder(in: store.documentsDirectory)
            let data = try store.snapshotData()
            let url = try BackupService.createBackup(data: data, folder: folder)
            message = "备份已生成：\(url.lastPathComponent)（\(BackupService.sizeText(of: url))）\n在「文件」App → 我的 iPhone → Elese的猫舍 里能看到。"
            refresh()
        } catch {
            message = "备份失败：\(error.localizedDescription)"
        }
    }

    private func exportBillsCSV() {
        do {
            var names: [UUID: String] = [:]
            for cat in store.data.cats { names[cat.id] = cat.name }
            let csv = ExportService.billsCSV(store.data.bills, catNames: names)
            let fileName = ExportService.stampedName(prefix: "育猫账单", ext: "csv")
            let url = try ExportService.write(text: csv, fileName: fileName, in: store.documentsDirectory)
            message = "已导出 \(store.data.bills.count) 笔账单：\(url.lastPathComponent)\n在「文件」App → 我的 iPhone → Elese的猫舍 里能看到。"
        } catch {
            message = "导出失败：\(error.localizedDescription)"
        }
    }

    private func performRestore() {
        guard let url = pendingRestore else { return }
        pendingRestore = nil
        do {
            let data = try Data(contentsOf: url)
            let restored = try BackupService.decode(data)
            store.replaceAll(with: restored)
            NotificationService.reschedule(reminders: restored.reminders)
            message = "已恢复：\(restored.cats.count) 只猫 · \(restored.breedings.count) 条繁育 · \(restored.bills.count) 笔账。"
        } catch {
            message = "恢复失败：这个文件读不出来（\(error.localizedDescription)）"
        }
    }

    private func openNotifications() {
        switch authStatus {
        case .notDetermined:
            NotificationService.requestAuthorization { _ in
                refresh()
            }
        default:
            NotificationService.reschedule(reminders: store.data.reminders)
            message = "已经按当前的到期日重排了一遍本地通知。"
            refresh()
        }
    }

    private func fileStamp(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }
}
