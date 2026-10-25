import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

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
    @State private var showImporter = false
    @State private var showDrillConfirm = false
    /// 待恢复的备份 —— **已经把内容读进内存**，而不是存 URL。
    /// 两个原因：① 从「文件」App 导入拿到的是 security-scoped URL，
    /// 出了那次回调就失效，等用户点确认时再去读必然失败；
    /// ② App 内备份与外部文件这两条来源在这里合流，于是确认框只需要一个。
    @State private var pendingRestore: RestorePayload?
    @State private var message: String?
    @State private var authStatus: UNAuthorizationStatus = .notDetermined

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    /// 交付标识：CI 注入的提交哈希前 7 位（本地构建是 local）。
    /// **这是"你装的是哪一版"的唯一可靠答案** —— 侧载场景下用户手上可能有多个包，
    /// 而它们原本全写着 1.0 (1)。
    private var appBuildSHA: String {
        Bundle.main.infoDictionary?["EleseBuildSHA"] as? String ?? "local"
    }

    var body: some View {
        DSScreen(title: "设置", onBack: { dismiss() }) {
            if let problem = store.loadProblem {
                loadProblemCard(problem)
            }
            if let message {
                banner(message)
            }
            dataCard
            if showRestoreList {
                restoreListCard
            }
            reminderCard
            selfCheckCard
            aboutCard
        }
        .onAppear(perform: refresh)
        // 从「文件」App 挑一个备份导入。**这是"数据在你手上"承诺的另一半**：
        // 能导出、但导入不了的话，那条承诺只在"同一台手机没删过 App"时才成立 ——
        // 而真正需要备份的场景，恰恰是换手机或重装。
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.json],
                      allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .alert("用这份备份覆盖当前数据？", isPresented: Binding(
            get: { pendingRestore != nil },
            set: { if !$0 { pendingRestore = nil } }
        )) {
            Button("覆盖恢复", role: .destructive) { performRestore() }
            Button("取消", role: .cancel) { pendingRestore = nil }
        } message: {
            let base = "这份备份是「\(pendingRestore?.name ?? "")」（\(pendingRestore.map { BackupService.sizeText(of: $0.data) } ?? "")）。\n当前的种猫、繁育、账单、提醒会被它整体替换，且无法撤销。\n建议先创建一份现在的备份再恢复。"
            if let note = pendingRestore?.note {
                Text(note + "\n\n" + base)
            } else {
                Text(base)
            }
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
        VStack(spacing: DS.Space.xl) {
            backupSection
            exportSection
        }
    }

    private var backupSection: some View {
        VStack(spacing: DS.Space.s) {
            DSSectionHeader(title: "备份")
            DSActionRow(systemName: "externaldrive.badge.timemachine",
                        title: "创建本地备份",
                        subtitle: "完整快照（JSON），存到「文件」App 里能看到的目录") {
                makeBackup()
            }
            DSActionRow(systemName: "square.and.arrow.down",
                        title: "从文件导入备份",
                        subtitle: "换手机 / 重装之后，用它把数据找回来") {
                showImporter = true
            }
            DSActionRow(systemName: "arrow.clockwise",
                        title: "从 App 内备份恢复",
                        subtitle: showRestoreList ? "选一份备份覆盖当前数据" : "本机生成过的那几份快照",
                        detail: backups.isEmpty ? "暂无备份" : "\(backups.count) 份",
                        showsChevron: true) {
                showRestoreList.toggle()
                if showRestoreList { refresh() }
            }
        }
    }

    /// 备份与导出**分开成两组**，不是排版问题 —— 它们的目的完全不同：
    /// 备份是"给将来的自己"（要能恢复，所以是完整 JSON），
    /// 导出是"给现在的自己"（要能拿 Excel 算，所以是扁平 CSV）。
    /// 混在一列里，用户永远分不清点下去会得到哪一个。
    private var exportSection: some View {
        VStack(spacing: DS.Space.s) {
            DSSectionHeader(title: "导出")
            DSActionRow(systemName: "tablecells",
                        title: "账单明细 CSV",
                        subtitle: "支出逐笔，可直接用 Excel 求和") {
                exportBillsCSV()
            }
            DSActionRow(systemName: "cat",
                        title: "种猫清单 CSV",
                        subtitle: "只导事实（生日、体重、状态）；年龄这类让表格自己算") {
                exportCatsCSV()
            }
            DSActionRow(systemName: "heart.text.square",
                        title: "繁育记录 CSV",
                        subtitle: "含孕期 / 哺乳天数；「阶段」那列标了「导出时」") {
                exportBreedingsCSV()
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
                        pickLocalBackup(url)
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

    // MARK: 数据读不出来时的报警（这一条是这个 App 能出的最严重的问题）

    /// 措辞要求：**先讲清"你的东西没被删"，再讲下一步。**
    /// 数据类 App 出这种问题时，用户第一反应是"全没了" —— 而事实是它被留档了。
    /// 先把这句说出来，比任何技术细节都重要。
    @ViewBuilder
    private func loadProblemCard(_ problem: String) -> some View {
        if let kept = store.quarantinedFileName {
            DSAlertCard(title: "数据文件读不出来",
                        message: "\(problem)\n\n你的原文件没有被覆盖 —— 我已经把它留档成：\(kept)",
                        hint: "现在显示的是空数据。点下面「从 App 内备份恢复」，选那份 store.corrupt 开头的文件即可找回（校验不通过时我会自动尝试逐条抢救）。")
        } else {
            DSAlertCard(title: "数据文件读不出来",
                        message: "\(problem)\n\n原文件还留在原处，但留档（改名备份）没成功。",
                        hint: "为了不把它盖掉，**我已经暂停了所有写入** —— 你现在做的修改都不会保存。\n请先用「从文件导入备份」恢复出一份数据，恢复成功后写入会自动恢复。")
        }
    }

    // MARK: 自检

    private var selfCheckCard: some View {
        VStack(spacing: DS.Space.s) {
            DSSectionHeader(title: "自检")
            DSActionRow(systemName: "stethoscope",
                        title: "演练：数据文件损坏时会怎样",
                        subtitle: "会先自动备份，再把数据文件写成坏的；需要手动重启一次 App",
                        showsChevron: false) {
                showDrillConfirm = true
            }
            Text("为什么要演练：一个没被走过一遍的安全网，不算安全网。这一步不会丢数据 —— 演练前会自动做一份备份，坏文件也会被留档。")
                .font(DS.Typo.caption)
                .foregroundStyle(DS.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .alert("演练：故意把数据文件写坏？", isPresented: $showDrillConfirm) {
            Button("开始演练", role: .destructive) { runDrill() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("会先自动创建一份备份，再把数据文件写成非法内容。\n然后请手动完全退出 App 再打开 —— 你应当看到红色警示、数据变空；\n最后用「从 App 内备份恢复」把数据拿回来。")
        }
    }

    /// 演练：**先备份，再故意写坏**。顺序不能反 —— 先写坏就等于拿用户的数据冒险。
    private func runDrill() {
        do {
            let folder = try BackupService.folder(in: store.documentsDirectory)
            let url = try BackupService.createBackup(data: try store.snapshotData(), folder: folder)
            try Data("这不是合法的 JSON".utf8).write(to: store.storeFileURL, options: .atomic)
            message = "演练准备完成：已备份为「\(url.lastPathComponent)」，数据文件已写成坏内容。\n现在请完全退出 App（上滑关掉它）再重新打开。"
            refresh()
        } catch {
            message = "演练没能开始：\(error.localizedDescription)"
        }
    }

    // MARK: 提醒

    private var reminderCard: some View {
        VStack(spacing: DS.Space.s) {
            DSSectionHeader(title: "提醒")
            DSActionRow(systemName: "bell",
                        title: "本地通知",
                        subtitle: "到期时按你设的时间提醒，不联网",
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
            DSKeyValueRow(key: "版本", value: "\(appVersion) (\(appBuild))", monospaced: true)
            DSKeyValueRow(key: "构建", value: appBuildSHA, monospaced: true)
            Text("Elese的猫舍没有账号、不联网、不统计使用行为。\n所有档案都只在这台手机上；备份文件存在你自己选的地方。\n换手机之前，记得先做一次备份。")
                .font(DS.Typo.caption)
                .foregroundStyle(DS.inkTertiary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Text("上面「构建」那行是这一版的身份 —— 反馈问题时把它一起发我就行。")
                .font(DS.Typo.caption)
                .foregroundStyle(DS.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 动作

    private func refresh() {
        backups = (try? BackupService.listBackups(in: BackupService.folder(in: store.documentsDirectory))) ?? []
        // 数据读不出来时**自动展开备份列表** —— 这时候用户最需要就是"哪份能恢复"，
        // 少点一次是一次（而且他此刻多半是慌的，不该再去找入口）。
        if store.loadProblem != nil, !backups.isEmpty {
            showRestoreList = true
        }
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
        var names: [UUID: String] = [:]
        for cat in store.data.cats { names[cat.id] = cat.name }
        writeCSV(ExportService.billsCSV(store.data.bills, catNames: names),
                 prefix: "育猫账单", count: store.data.bills.count, what: "笔账单")
    }

    private func exportCatsCSV() {
        writeCSV(ExportService.catsCSV(store.data.cats),
                 prefix: "种猫清单", count: store.data.cats.count, what: "只猫")
    }

    private func exportBreedingsCSV() {
        // 用 breedingsWithNames：列表里母亲/父亲是名字，导出也必须是名字 ——
        // 一份只有 UUID 的表格对用户毫无用处。
        writeCSV(ExportService.breedingsCSV(store.breedingsWithNames),
                 prefix: "繁育记录", count: store.data.breedings.count, what: "条繁育记录")
    }

    /// 三个导出共用的写法：**空数据不生成空文件**。
    /// 导出一个只有表头的 csv，用户会以为导出坏了（其实只是没数据）——
    /// 直接告诉他"还没有可以导出的东西"更省事。
    private func writeCSV(_ text: String, prefix: String, count: Int, what: String) {
        guard count > 0 else {
            message = "还没有可以导出的\(prefix)。"
            return
        }
        do {
            let url = try ExportService.writeCSV(text,
                                                 fileName: ExportService.stampedName(prefix: prefix, ext: "csv"),
                                                 in: store.documentsDirectory)
            message = "已导出 \(count) \(what)：\(url.lastPathComponent)\n在「文件」App → 我的 iPhone → Elese的猫舍 里能看到。"
        } catch {
            message = "导出失败：\(error.localizedDescription)"
        }
    }

    /// App 内那几份备份：选一份 → 立刻把内容读进内存 → 交给同一个确认框。
    /// 为什么不在确认之后再读：文件可能在这中间被删/被占，那时报错就太晚了；
    /// 而且"读不出来"应该马上说，不该等用户点了"覆盖恢复"才发现。
    private func pickLocalBackup(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            prepareRestore(name: fileStamp(url), data: data)
        } catch {
            message = "这份备份读不出来：\(error.localizedDescription)"
        }
    }

    /// 从「文件」App 导入。⚠️ 拿到的是 **security-scoped URL**：
    /// 必须在这一次回调里 `startAccessing…` 把数据读出来，之后再读就无权了。
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            message = "选择文件失败：\(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                prepareRestore(name: url.lastPathComponent, data: data)
            } catch {
                message = "文件读不出来（\(error.localizedDescription)）\n（选的是「\(url.lastPathComponent)」）"
            }
        }
    }

    /// 恢复前的统一入口：**先严格解，解不动就诊断 + 逐条抢救**。
    ///
    /// 为什么要有抢救这一步：严格模式是"一条坏 → 全盘失败"，
    /// 但用户真正想要的是"先把我能拿的拿回来"。数据类事故里，
    /// 80% 的内容通常都是完好的，只是被一条坏记录卡住了整份文件。
    private func prepareRestore(name: String, data: Data) {
        // ① 严格解码
        do {
            let decoded = try BackupService.decode(data)
            pendingRestore = RestorePayload(name: name, data: data,
                                            decoded: decoded, salvaged: false, note: nil)
            return
        } catch {
            // ② 严格失败 → 抢救
            if let (salvaged, report) = BackupService.salvage(data), report.keptTotal > 0 {
                pendingRestore = RestorePayload(
                    name: name, data: data, decoded: salvaged, salvaged: true,
                    note: "严格校验未通过（\(BackupService.describe(error))），已逐条抢救出：\(report.summary)")
                message = "「\(name)」校验没过，但内容能捞回来：\(report.summary)\n在确认框里点「覆盖恢复」即可先拿回这部分。"
            } else {
                // ③ 连抢救都没有内容 → 说清到底为什么
                message = "「\(name)」读不出来。\n诊断：\(BackupService.diagnose(data))\n（\(BackupService.sizeText(of: data))）"
            }
        }
    }

    private func performRestore() {
        guard let payload = pendingRestore else { return }
        pendingRestore = nil
        let restored = payload.decoded        // 进确认框之前就已经解好了，这里不会再失败
        store.replaceAll(with: restored)
        NotificationService.reschedule(reminders: restored.reminders)
        // 恢复成功 = 那个问题已经处理完了，红框该收起来（否则它会一直挂在那里变成噪音）
        store.clearLoadProblem()
        let counts = "\(restored.cats.count) 只猫 · \(restored.breedings.count) 条繁育 · \(restored.bills.count) 笔账 · \(restored.reminders.count) 条提醒"
        if payload.salvaged {
            message = "已按抢救结果恢复「\(payload.name)」：\(counts)。\n（这份备份有部分记录结构损坏，被跳过；原始文件没有任何改动。）"
        } else {
            message = "已恢复「\(payload.name)」：\(counts)。"
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

// MARK: - 待恢复的备份
//
// 只装"名字 + 内容"。名字用来在确认框里说清"你正要覆盖成哪一份" ——
// 恢复是不可撤销的，**必须让用户看见他选的是哪一个**，而不是只问"确定吗"。

private struct RestorePayload {
    let name: String
    let data: Data
    /// **已经解好**的内容。放在这里而不是恢复时再解一次：
    /// 一是避免"确认之后才发现解不开"的二次惊吓；
    /// 二是抢救模式下来的内容不可能再严格解一遍（它本来就是解不动才抢救的）。
    let decoded: AppData
    /// 是否为"抢救"结果（严格校验未通过，逐条捞回来的）
    let salvaged: Bool
    /// 抢救说明（正常解码时为 nil）
    let note: String?
}
