import Foundation
import SwiftUI
import UIKit

// MARK: - 根数据容器
//
// 这个 struct 就是磁盘上那个 JSON 文件的结构。
// 导出 / 备份 / 恢复全部复用它 —— 不做第二套序列化，避免两边漂移。

struct AppData: Codable {
    var schemaVersion: Int = 1
    var cats: [Cat] = []
    var breedings: [BreedingRecord] = []
    var bills: [Bill] = []
    var reminders: [Reminder] = []
    /// 疫苗 / 驱虫记录。**加在最后并且给了默认值** ——
    /// 这样旧版本写出来的 store.json 仍然能解码（缺这个键就用空数组），
    /// 用户不会因为我在中间加了个字段而突然"数据读不出来"。
    var healthRecords: [HealthRecord] = []
}

// MARK: - 本地存储 + 派生数据

/// 读数据文件失败的原因。
///
/// ⚠️ 用一个小 struct，而不是直接 `Result<AppData, String>` ——
/// `Result` 的 Failure 必须 conform to `Error`，而 **`String` 并不 conform**。
/// 我一开始想当然地写了 String，被 CI 的 commit 评论当场抓住：
///     `AppStore.swift:80:48: error: type 'String' does not conform to protocol 'Error'`
/// （这条记在这里，是因为它属于"看起来一定会编译过"的那类错。）
private struct StoreReadError: Error {
    let message: String
}

@MainActor
final class AppStore: ObservableObject {

    @Published private(set) var data: AppData

    /// 数据文件**读不出来**时，这里会有一句人话说明；正常情况下是 nil。
    ///
    /// 为什么必须有它：原来的写法是 `load(...) ?? AppData.sample` ——
    /// 文件一旦损坏（或将来某次模型改动导致解码失败），用户会看到**示例数据**，
    /// 而只要他再碰一下任何东西，`save()` 就会把示例数据写回去，
    /// **把真正的那份文件永久覆盖掉**。
    /// 对一个把「数据只在本机、你自己能管」当承诺的 App，静默覆盖是最不该有的失败方式。
    @Published private(set) var loadProblem: String?

    /// 读失败时被**留档**的文件名（在「文件」App → Elese的猫舍 → Elese备份 里能找到）
    @Published private(set) var quarantinedFileName: String?

    let storeDirectory: URL
    let storeFileURL: URL

    /// 导出与备份落在 Documents，**数据库落在 Application Support**。
    /// 这样开了 UIFileSharingEnabled 之后，用户在「文件」App 里看到的只有可删的导出件，不会误删数据库。
    var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    init(fileName: String = "store.json") {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EleseCattery", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        storeDirectory = base
        storeFileURL = base.appendingPathComponent(fileName)

        // ⚠️ 三条路径必须分开，别合并成一句 `?? sample`：
        //   ① 文件不存在        → 首次启动，灌示例数据（让界面状态能被直接看到）
        //   ② 文件在且读得出来   → 正常
        //   ③ 文件在但读不出来   → **留档 + 空数据 + 报警**，绝不拿示例数据顶上
        if FileManager.default.fileExists(atPath: storeFileURL.path) {
            switch AppStore.read(from: storeFileURL) {
            case .success(let loaded):
                data = loaded
            case .failure(let reason):
                data = AppData()
                loadProblem = reason.message
                quarantinedFileName = AppStore.quarantine(storeFileURL)
            }
        } else {
            data = AppData.sample
        }
    }

    /// 用户看过报警之后的"知道了"。
    func clearLoadProblem() {
        loadProblem = nil
    }

    // MARK: 磁盘读写

    /// 读 + 解析，失败时给出**人话原因** —— 直接把 DecodingError 抛给用户看没有意义。
    private static func read(from url: URL) -> Result<AppData, StoreReadError> {
        let raw: Data
        do {
            raw = try Data(contentsOf: url)
        } catch {
            return .failure(StoreReadError(message: "数据文件读不出来（\(error.localizedDescription)）"))
        }
        guard !raw.isEmpty else {
            return .failure(StoreReadError(message: "数据文件是空的（0 字节）"))
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return .success(try decoder.decode(AppData.self, from: raw))
        } catch {
            return .failure(StoreReadError(message: "数据文件的内容不是本 App 认识的格式"))
        }
    }

    /// 把读不出来的文件**改名留档 —— 不是删除**。
    ///
    /// 为什么留档而不是丢弃：它可能只是"这一版读不懂"（字段变了、被别的东西写过），
    /// 换一版、或者拿出去看一眼还能救回来。**删除是不可逆的，而这里没有任何理由不可逆。**
    ///
    /// 为什么放到 Documents：Application Support 在「文件」App 里看不见，
    /// 而留档的意义就是"用户能拿到它"。放进已有的「Elese备份」文件夹 ——
    /// 它本来就是"你可能需要拿回来的东西"待的地方。
    private static func quarantine(_ url: URL) -> String? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmm"
        let name = "store.corrupt-\(f.string(from: Date())).json"
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = docs.appendingPathComponent(BackupService.folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = folder.appendingPathComponent(name)
        do {
            try? FileManager.default.removeItem(at: dest)     // 同一分钟重复演练时不撞名
            try FileManager.default.moveItem(at: url, to: dest)
            return name
        } catch {
            // 连改名都失败（极罕见）：那就**保持原文件不动**，至少不破坏它。
            return nil
        }
    }

    private static func encode(_ value: AppData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    /// 全量写入。数据量在"个人猫舍"量级，不需要增量。
    func save() {
        do {
            let blob = try AppStore.encode(data)
            try blob.write(to: storeFileURL, options: .atomic)
        } catch {
            // 本地写失败是"数据可能丢"级别的事，不该静默。留给上层提示。
            assertionFailure("保存失败：\(error)")
        }
    }

    /// 供备份 / 导出复用的原始快照
    func snapshotData() throws -> Data { try AppStore.encode(data) }

    func replaceAll(with incoming: AppData) {
        data = incoming
        save()
    }

    // MARK: 头像照片
    //
    // 照片存沙盒（`Application Support/EleseCattery/avatars/`），**数据库里只记文件名**。
    // 为什么不把照片塞进 JSON：那份文件要能随时导出成一个小文本，而照片是二进制大块 ——
    // 混在一起会让"导出/备份"从"几十 KB"变成"几十 MB"，而用户只是想存个账。
    //
    // ⚠️ 文件名**不带扩展名**：用户从相册选来的可能是 JPEG / PNG / HEIC，
    // 而我们不做转码。写死 `.jpg` 会让文件内容与名字不符（以后谁按后缀去解码就会踩坑）；
    // `UIImage(data:)` 是按内容识别格式的，不需要后缀。

    private var avatarCache: [String: UIImage] = [:]

    var avatarDirectory: URL {
        storeDirectory.appendingPathComponent("avatars", isDirectory: true)
    }

    /// 读头像（带内存缓存：列表滚动会反复构造行视图，不该每次都读盘）
    func avatarImage(named name: String?) -> UIImage? {
        guard let name, !name.isEmpty else { return nil }
        if let hit = avatarCache[name] { return hit }
        let url = avatarDirectory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        avatarCache[name] = image
        return image
    }

    /// 存一张新头像，返回文件名；失败返回 nil。同名覆盖（一只猫一个文件）。
    @discardableResult
    func saveAvatar(_ data: Data, for catID: UUID) -> String? {
        try? FileManager.default.createDirectory(at: avatarDirectory, withIntermediateDirectories: true)
        let name = "cat-\(catID.uuidString)"
        let url = avatarDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            avatarCache[name] = UIImage(data: data)
            return name
        } catch {
            return nil
        }
    }

    func removeAvatar(named name: String?) {
        guard let name, !name.isEmpty else { return }
        avatarCache[name] = nil
        try? FileManager.default.removeItem(at: avatarDirectory.appendingPathComponent(name))
    }

    // MARK: 种猫

    func upsert(cat: Cat) {
        if let idx = data.cats.firstIndex(where: { $0.id == cat.id }) {
            data.cats[idx] = cat
        } else {
            data.cats.append(cat)
        }
        save()
    }

    func deleteCat(id: UUID) {
        // 顺手把它的头像文件也删掉 —— 否则用户删了猫，沙盒里还留着一张照片，
        // 而那张照片在界面上再也看不到、也没法删。（数据只在本机的承诺，包括"能删干净"。）
        removeAvatar(named: data.cats.first { $0.id == id }?.avatarFileName)
        data.cats.removeAll { $0.id == id }
        // 级联：把挂在它下面的繁育记录一并清掉，避免出现指向不存在猫的记录
        data.breedings.removeAll { $0.motherID == id || $0.fatherID == id }
        save()
    }

    func cat(id: UUID?) -> Cat? {
        guard let id else { return nil }
        return data.cats.first { $0.id == id }
    }

    /// 组装好的繁育记录（把公母猫名字填进去）。
    /// 模型不持有引用，靠这里装配 —— 避免 Codable 关系带来的循环与迁移麻烦。
    var breedingsWithNames: [BreedingRecord] {
        data.breedings.map { record in
            var r = record
            r.motherName = cat(id: r.motherID)?.name ?? "未知"
            r.fatherName = cat(id: r.fatherID)?.name ?? "未知"
            return r
        }
    }

    // MARK: 繁育

    func upsert(breeding: BreedingRecord) {
        if let idx = data.breedings.firstIndex(where: { $0.id == breeding.id }) {
            data.breedings[idx] = breeding
        } else {
            data.breedings.append(breeding)
        }
        save()
    }

    func deleteBreeding(id: UUID) {
        data.breedings.removeAll { $0.id == id }
        save()
    }

    func breeding(id: UUID?) -> BreedingRecord? {
        guard let id else { return nil }
        return data.breedings.first { $0.id == id }
    }

    /// 装配好父母名字的单条记录（详情页用）。与 `breedingsWithNames` 同源，
    /// 只是少了"每次都要重算全表"的开销。
    func breedingWithNames(id: UUID) -> BreedingRecord? {
        guard let record = breeding(id: id) else { return nil }
        var out = record
        out.motherName = cat(id: record.motherID)?.name ?? "未知"
        out.fatherName = cat(id: record.fatherID)?.name ?? "未知"
        return out
    }

    /// 某只猫参与的繁育记录（按编号倒序）
    func breedings(of catID: UUID) -> [BreedingRecord] {
        breedingsWithNames
            .filter { $0.motherID == catID || $0.fatherID == catID }
            .sorted { $0.code > $1.code }
    }

    // MARK: 账单

    func upsert(bill: Bill) {
        if let idx = data.bills.firstIndex(where: { $0.id == bill.id }) {
            data.bills[idx] = bill
        } else {
            data.bills.append(bill)
        }
        save()
    }

    func deleteBill(id: UUID) {
        data.bills.removeAll { $0.id == id }
        save()
    }

    /// 本月账单。默认按日期倒序 —— 列表页依赖这个顺序，不要在视图里再排一次。
    func bills(in month: Date) -> [Bill] {
        let cal = Calendar.current
        return data.bills
            .filter { cal.isDate($0.date, equalTo: month, toGranularity: .month) }
            .sorted { $0.date > $1.date }
    }

    func total(of bills: [Bill]) -> Double {
        bills.reduce(0) { $0 + $1.amount }
    }

    /// 分类占比（金额倒序）。**只返回有金额的分类**，避免列表里出现一堆 0。
    func breakdown(of bills: [Bill]) -> [(category: BillCategory, amount: Double)] {
        var bucket: [BillCategory: Double] = [:]
        for b in bills { bucket[b.category, default: 0] += b.amount }
        return bucket
            .filter { $0.value > 0 }
            .map { (category: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    /// 某月**每天的支出合计**（键 = 几号，1…31）。
    ///
    /// 放在 store 而不是各视图里：日历格子和"按天分组的明细"都要用它 ——
    /// 各算一遍迟早出现两套口径（一个按 startOfDay、一个按 component(.day)），
    /// 于是**同一天在两处显示不同的数字**。这类"同一个事实两套算法"的 bug 最难查，
    /// 因为每一处单看都对。
    func dailyTotals(in month: Date) -> [Int: Double] {
        var out: [Int: Double] = [:]
        let cal = Calendar.current
        for bill in bills(in: month) {
            out[cal.component(.day, from: bill.date), default: 0] += bill.amount
        }
        return out
    }

    /// 某月按天分组的账单（新的一天在前），供"明细"按日展示。
    /// 每天带上自己的小计 —— 这就是用户要的"每日的记录情况"。
    ///
    /// ⚠️ 这里刻意**拆成多行 + 显式循环**，而不是一个链式表达式：
    /// 一个 .map 里塞元组字面量 + 嵌套闭包（内层还用 $0/$1）是 Swift 类型检查器
    /// 最容易超时/报怪的写法。拆开之后既好读，也不会让编译器猜。
    func dailyGroups(in month: Date) -> [(day: Int, bills: [Bill], total: Double)] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: bills(in: month)) { cal.component(.day, from: $0.date) }
        var out: [(day: Int, bills: [Bill], total: Double)] = []
        for (day, items) in grouped {
            let ordered = items.sorted { $0.date > $1.date }
            let total = ordered.reduce(0.0) { $0 + $1.amount }
            out.append((day: day, bills: ordered, total: total))
        }
        return out.sorted { $0.day > $1.day }
    }

    // MARK: 提醒

    func upsert(reminder: Reminder) {
        if let idx = data.reminders.firstIndex(where: { $0.id == reminder.id }) {
            data.reminders[idx] = reminder
        } else {
            data.reminders.append(reminder)
        }
        save()
    }

    func toggleReminder(id: UUID) {
        guard let idx = data.reminders.firstIndex(where: { $0.id == id }) else { return }
        data.reminders[idx].isDone.toggle()
        save()
    }

    func deleteReminder(id: UUID) {
        data.reminders.removeAll { $0.id == id }
        save()
    }

    /// 某只猫名下的待办（含逾期），按到期日升序
    func openReminders(of catID: UUID) -> [Reminder] {
        openReminders.filter { $0.catID == catID }
    }

    // MARK: 疫苗 / 驱虫记录

    func upsert(health: HealthRecord) {
        if let idx = data.healthRecords.firstIndex(where: { $0.id == health.id }) {
            data.healthRecords[idx] = health
        } else {
            data.healthRecords.append(health)
        }
        save()
    }

    func deleteHealth(id: UUID) {
        data.healthRecords.removeAll { $0.id == id }
        save()
    }

    /// 某只猫的记录，新的在前
    func healthRecords(of catID: UUID) -> [HealthRecord] {
        data.healthRecords.filter { $0.catID == catID }.sorted { $0.date > $1.date }
    }

    /// 某只猫某一类里**最近的一次** —— "上次内驱是什么时候"就是问这个。
    /// 排序在 healthRecords 里已经做过，这里直接取第一个。
    func latestHealth(of kind: HealthKind, for catID: UUID) -> HealthRecord? {
        healthRecords(of: catID).first { $0.kind == kind }
    }

    /// 未完成提醒，按截止日期升序（逾期的自然排在最前）
    var openReminders: [Reminder] {
        data.reminders.filter { !$0.isDone }.sorted { $0.dueDate < $1.dueDate }
    }

    func reminders(of urgency: ReminderUrgency) -> [Reminder] {
        openReminders.filter { $0.urgency == urgency }
    }

    var overdueCount: Int { reminders(of: .overdue).count }
    var todayCount: Int { reminders(of: .today).count }
    var thisWeekCount: Int { reminders(of: .thisWeek).count }
}

// MARK: - 首次启动的示例数据
//
// 内容刻意与设计稿一致（Mochi / Leo / 雪球 / 年糕 / 灰灰），
// 这样工程师跑起来第一眼看到的就是设计稿上那个界面，便于逐屏比对。

extension AppData {
    static var sample: AppData {
        let cal = Calendar.current
        let today = Date()
        func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today) ?? today }
        func month(_ offset: Int, day d: Int) -> Date {
            let base = cal.date(byAdding: .month, value: offset, to: today) ?? today
            return cal.date(bySetting: .day, value: d, of: base) ?? base
        }

        let mochi = Cat(name: "Mochi", callName: "麻薯", gender: .female, breed: "英国短毛猫",
                        coat: "银渐层 Silver Shaded", birthDate: month(-27, day: 18),
                        weightKg: 3.8, status: .pregnant, litterCount: 1)
        let leo = Cat(name: "Leo", callName: "里奥", gender: .male, breed: "英国短毛猫",
                      coat: "蓝猫 British Blue", birthDate: month(-32, day: 3),
                      weightKg: 4.8, status: .breeding, litterCount: 3)
        let xueqiu = Cat(name: "雪球", callName: "球球", gender: .female, breed: "英国短毛猫",
                         coat: "蓝金渐层 Blue Golden", birthDate: month(-20, day: 9),
                         weightKg: 3.4, status: .mating, litterCount: 0)
        let niangao = Cat(name: "年糕", callName: "糕糕", gender: .female, breed: "英国长毛猫",
                          coat: "金渐层长毛 Golden", birthDate: month(-41, day: 22),
                          weightKg: 4.2, status: .born, litterCount: 1)
        let huihui = Cat(name: "灰灰", callName: "灰灰", gender: .male, breed: "英国短毛猫",
                         coat: "乳白英短 Cream", birthDate: month(-64, day: 5),
                         weightKg: 5.1, status: .retired, litterCount: 12)

        // 注意：不再有 `stage:` 这个参数 —— 阶段由日期推导（见 BreedingRecord.stage）。
        // 下面这五条覆盖了四个阶段的全部形态，跑起来就能逐屏比对。
        let r1 = BreedingRecord(code: "BR-2026-03", motherID: mochi.id, fatherID: leo.id,
                                matedDate: day(-38), pregnantDate: day(-10),
                                expectedDueDate: day(15), kittenCount: nil,
                                note: "第二胎，B 超确认 5 个胎心", motherName: mochi.name, fatherName: leo.name)
        let r2 = BreedingRecord(code: "BR-2026-02", motherID: xueqiu.id, fatherID: leo.id,
                                matedDate: day(5), pregnantDate: nil,
                                expectedDueDate: nil, kittenCount: nil, note: "待确认怀孕",
                                motherName: xueqiu.name, fatherName: leo.name)
        let r3 = BreedingRecord(code: "BR-2026-01", motherID: niangao.id, fatherID: leo.id,
                                matedDate: day(-118), pregnantDate: day(-92),
                                expectedDueDate: day(-33), birthDate: day(-33), kittenCount: 5,
                                note: "",
                                motherName: niangao.name, fatherName: leo.name)
        let r4 = BreedingRecord(code: "BR-2025-08", motherID: niangao.id, fatherID: leo.id,
                                matedDate: day(-320), pregnantDate: day(-295),
                                expectedDueDate: day(-236), birthDate: day(-236), weanedDate: day(-180),
                                kittenCount: 4, note: "",
                                motherName: niangao.name, fatherName: leo.name)
        let r5 = BreedingRecord(code: "BR-2026-04", motherID: niangao.id, fatherID: huihui.id,
                                matedDate: day(2), pregnantDate: nil,
                                expectedDueDate: nil, kittenCount: nil, note: "计划配种",
                                motherName: niangao.name, fatherName: huihui.name)

        let bills: [Bill] = [
            Bill(title: "皇家幼猫粮 2kg", category: .food, amount: 328, date: day(0), note: "皇家幼猫粮 2kg"),
            Bill(title: "疫苗加强针", category: .vaccine, amount: 260, date: day(-5), note: "Mochi 疫苗加强针"),
            Bill(title: "配种服务费", category: .breeding, amount: 700, date: day(-11), note: "雪球 × Leo"),
            Bill(title: "猫砂 + 猫爬架", category: .supplies, amount: 540, date: day(-20), note: "猫砂 20kg + 猫爬架"),
        ]

        // 提醒是带**时刻**的，示例数据也要给出像样的时刻 ——
        // 否则它们全等于"安装 App 的那一秒"，看起来像随机数（而这是用户第一眼看到的东西）。
        func at(_ offset: Int, hour: Int) -> Date {
            let d = day(offset)
            return cal.date(bySettingHour: hour, minute: 0, second: 0, of: d) ?? d
        }

        let reminders: [Reminder] = [
            Reminder(kind: .deworm, title: "雪球 · 体内驱虫", detail: "海乐妙 · 每月一次",
                     dueDate: at(-1, hour: 9), catID: xueqiu.id),
            Reminder(kind: .weigh, title: "Leo · 体重记录", detail: "每周称重一次",
                     dueDate: at(0, hour: 20), catID: leo.id),
            Reminder(kind: .ultrasound, title: "Mochi · B 超复查", detail: "孕 5 周复查胎数",
                     dueDate: at(6, hour: 9), catID: mochi.id),
            Reminder(kind: .dueDate, title: "Mochi · 预产期临近", detail: "提前准备产房与保温箱",
                     dueDate: at(15, hour: 9), catID: mochi.id),
            Reminder(kind: .weanCheck, title: "年糕 · 幼猫出窝回访", detail: "确认 4 只幼猫健康状况",
                     dueDate: at(4, hour: 9), catID: niangao.id),
        ]

        // 疫苗 / 驱虫记录：给几只猫各留几条，让"上次是什么时候"这件事一进详情页就有内容 ——
        // 空列表看不出这个功能在干什么。刻意让三类**各有远近**：
        // 有的刚做过、有的快到点、有的已经过了，这样"参考下次"的三种状态都能被看到。
        func daysAgo(_ offset: Int) -> Date { cal.date(byAdding: .day, value: -offset, to: today) ?? today }
        let health: [HealthRecord] = [
            HealthRecord(catID: mochi.id, kind: .vaccine, date: daysAgo(300), note: "猫三联 加强"),
            HealthRecord(catID: mochi.id, kind: .dewormInternal, date: daysAgo(95), note: "海乐妙"),
            HealthRecord(catID: mochi.id, kind: .dewormExternal, date: daysAgo(38), note: "大宠爱"),

            HealthRecord(catID: leo.id, kind: .vaccine, date: daysAgo(120), note: "猫三联 + 狂犬"),
            HealthRecord(catID: leo.id, kind: .dewormInternal, date: daysAgo(20), note: "海乐妙"),
            HealthRecord(catID: leo.id, kind: .dewormExternal, date: daysAgo(12), note: "福来恩"),

            HealthRecord(catID: xueqiu.id, kind: .dewormInternal, date: daysAgo(100), note: "拜宠清"),
            HealthRecord(catID: xueqiu.id, kind: .dewormExternal, date: daysAgo(45), note: "福来恩"),

            HealthRecord(catID: niangao.id, kind: .vaccine, date: daysAgo(240), note: "猫三联 加强"),
        ]

        return AppData(cats: [mochi, leo, xueqiu, niangao, huihui],
                       breedings: [r1, r2, r3, r4, r5],
                       bills: bills,
                       reminders: reminders,
                       healthRecords: health)
    }
}
