import Foundation

// MARK: - 导出与备份
//
// 两者是**同一件事的两个方向**，所以放在一起、复用同一份序列化：
//   · 备份：把 `AppData` 原样写成 JSON（要能恢复回来，字段一个都不能少）
//   · 导出：把账单写成 CSV（给人看的，字段是做减法之后的结果）
//
// 为什么备份不做第二套"精简格式"：真要恢复的时候，任何"精简"都会变成数据丢失。
// 备份文件就是 store.json 的同构副本，恢复 = 解回来直接替换。
//
// ⚠️ 全部落在 Documents 目录。数据库在 Application Support ——
//    这样开了文件共享后，用户在「文件」App 里看到的只有能删的导出件，不会误删数据库。

enum ExportService {

    // MARK: 账单 CSV

    /// 账单 CSV。列的顺序就是"看账"的顺序；金额**不带 ¥ 也不带负号**，
    /// 因为 Excel 里要能直接对这一列求和 —— 带符号的文本列是求和失败的头号原因。
    static func billsCSV(_ bills: [Bill], catNames: [UUID: String]) -> String {
        var lines: [String] = ["日期,分类,标题,金额,关联猫咪,备注"]
        let day = Formatters.isoDay
        for bill in bills.sorted(by: { $0.date < $1.date }) {
            let names = bill.catIDs.compactMap { catNames[$0] }.joined(separator: "、")
            let fields = [
                day.string(from: bill.date),
                bill.category.label,
                bill.title,
                String(format: "%.2f", bill.amount),
                names,
                bill.note,
            ]
            lines.append(fields.map(csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    // MARK: 种猫清单 CSV

    /// 种猫清单。
    /// **只导事实，不导派生值** —— 比如年龄：它今天算出来是"1 岁 2 个月"，
    /// 下个月这个文件就在骗人了。生日是事实，年龄让表格自己去算
    /// （理由与 App 里"阶段由日期推导"是同一条）。
    static func catsCSV(_ cats: [Cat]) -> String {
        var lines: [String] = ["名字,呼名,性别,品种,毛色,生日,体重(kg),状态"]
        let day = Formatters.isoDay
        for cat in cats.sorted(by: { $0.name < $1.name }) {
            let fields = [
                cat.name,
                cat.callName,
                cat.gender.label,
                cat.breed,
                cat.coat,
                day.string(from: cat.birthDate),
                cat.weightKg > 0 ? String(format: "%.1f", cat.weightKg) : "",
                cat.status.label,
            ]
            lines.append(fields.map(csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    // MARK: 繁育记录 CSV

    /// 繁育记录。两个刻意的取舍：
    ///   · 阶段列**必须叫「阶段（导出时）」** —— 它依赖"现在"，导出那一刻之后就固定在文件里了，
    ///     不写清楚，过几天看这份表会以为它还准；
    ///   · 孕期/哺乳天数**可以直接导** —— 它们只由**这一行自己的两个日期**决定，
    ///     放多久都不会变，属于"可以从事实算出来且不随时间漂移"的那类。
    ///   （判据：这个派生值会不会随"今天"变化？会 → 要么不导，要么标明是快照。）
    static func breedingsCSV(_ records: [BreedingRecord]) -> String {
        var lines: [String] = ["编号,母亲,父亲,阶段（导出时）,配对日,确认怀孕,预产期,生产日,出窝日,配种到生产(天),生产到出窝(天),产仔数,备注"]
        let day = Formatters.isoDay
        for record in records.sorted(by: { $0.code > $1.code }) {
            func d(_ date: Date?) -> String { date.map { day.string(from: $0) } ?? "" }
            func n(_ value: Int?) -> String { value.map { String($0) } ?? "" }
            let fields = [
                record.code,
                record.motherName,
                record.fatherName,
                record.stage.label,
                d(record.matedDate),
                d(record.pregnantDate),
                d(record.expectedDueDate),
                d(record.birthDate),
                d(record.weanedDate),
                n(BreedingRecord.gestationDays(matedDate: record.matedDate, birthDate: record.birthDate)),
                n(BreedingRecord.nursingDays(birthDate: record.birthDate, weanedDate: record.weanedDate)),
                n(record.kittenCount),
                record.note,
            ]
            lines.append(fields.map(csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// CSV 字段转义：含逗号 / 引号 / 换行的必须用引号包起来，内部引号翻倍。
    /// 不转义的后果不是"格式难看"，是**列错位** —— 而错位的表格比没有表格更危险。
    static func csvField(_ raw: String) -> String {
        if raw.contains(",") || raw.contains("\"") || raw.contains("\n") || raw.contains("\r") {
            return "\"" + raw.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return raw
    }

    // MARK: 写文件

    /// 写进 Documents，返回落盘后的 URL（用于在设置页展示"已生成 xxx"）。
    @discardableResult
    static func write(text: String, fileName: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(fileName)
        guard let blob = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try blob.write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    static func write(data: Data, fileName: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: CSV 的编码

    /// 写 CSV（**自动带 UTF-8 BOM**）。
    ///
    /// 为什么要带 BOM：不带的话，中文在 **Windows 版 Excel** 里会显示成乱码 ——
    /// Excel 会按本地代码页去猜编码。而这份文件恰恰就是"导出给人用 Excel 看"的。
    /// Numbers / Google 表格 / 大多数文本编辑器都会忽略 BOM，
    /// 所以带上它是**只赚不亏**的一件事（早先版本的注释写着"无 BOM"，那是想窄了）。
    @discardableResult
    static func writeCSV(_ text: String, fileName: String, in directory: URL) throws -> URL {
        try write(data: csvData(text), fileName: fileName, in: directory)
    }

    /// 文本 → 带 BOM 的 UTF-8 数据
    static func csvData(_ text: String) -> Data {
        var out = Data([0xEF, 0xBB, 0xBF])
        out.append(Data(text.utf8))
        return out
    }

    /// 带时间戳的文件名（本地时区，给人看）。
    static func stampedName(prefix: String, ext: String, now: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return "\(prefix)-\(f.string(from: now)).\(ext)"
    }
}

enum BackupService {

    /// 备份放一个单独的文件夹，别和导出的 CSV 混在一起 ——
    /// 备份是"恢复时要用"的，用户不该在一堆导出件里找它。
    static let folderName = "Elese备份"

    static func folder(in documents: URL) throws -> URL {
        let url = documents.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 已有备份，**按文件名倒序**（文件名带时间戳，所以字典序即时间序）。
    static func listBackups(in folder: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: folder,
                                                                 includingPropertiesForKeys: nil)) ?? []
        return items
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    @discardableResult
    static func createBackup(data: Data, folder: URL, now: Date = Date()) throws -> URL {
        let name = ExportService.stampedName(prefix: "elesecattery-backup", ext: "json", now: now)
        return try ExportService.write(data: data, fileName: name, in: folder)
    }

    static func decode(_ data: Data) throws -> AppData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppData.self, from: data)
    }

    /// 备份文件的"一句话摘要"，用于恢复列表里让人认得出是哪一份。
    static func summary(of url: URL) -> String {
        guard let data = try? Data(contentsOf: url), let appData = try? decode(data) else {
            return "无法读取"
        }
        return "\(appData.cats.count) 只猫 · \(appData.breedings.count) 条繁育 · \(appData.bills.count) 笔账"
    }

    /// 通用文件大小文案（两个入口共用同一套换算 —— 分两份写必然会出现两套阈值）
    static func sizeText(of url: URL) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return byteText((attrs?[.size] as? Int) ?? 0)
    }

    /// 同上，但对象是**内存里的数据**（待恢复的备份只有 Data，没有文件）。
    static func sizeText(of data: Data) -> String {
        byteText(data.count)
    }

    private static func byteText(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1 { return "\(bytes) B" }
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }
}
