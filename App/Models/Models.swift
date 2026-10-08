import Foundation

// MARK: - 数据模型
//
// 存储方案的选择（与设计文档的字段定义无关，这里只讲决定）：
//   · 用 **Codable + 单个 JSON 文件**，不用 SwiftData。
//     理由：① 产品承诺"数据只在本机、你自己能删"，那么"数据库"就是一个文件，导出与备份天然同源；
//           ② 避开 `#Predicate` 宏 —— 那是本轮唯一"只有编译器能裁决"的高风险项；
//           ③ 规模合适：个人猫舍约 20 只猫 / 每年几百条账单，内存数组完全够。
//     代价：没有查询引擎、全量写入。到这个数据量级可以忽略。
//   · 文件位置：Application Support/EleseCattery/store.json（**不在 Documents**）。
//     导出与备份文件才放 Documents，这样开了文件共享后用户看到的是"能删的东西"，不会误删数据库。

// MARK: 枚举

enum CatGender: String, Codable, CaseIterable, Identifiable {
    case female, male
    var id: String { rawValue }
    var label: String { self == .female ? "母" : "公" }
}

/// 种猫状态。**顺序即显示顺序**，与画布列表的筛选芯片一致。
enum CatStatus: String, Codable, CaseIterable, Identifiable {
    case breeding     // 繁育中
    case mating       // 配种中
    case pregnant     // 怀孕中
    case born         // 已生产
    case retired      // 已退役

    var id: String { rawValue }

    var label: String {
        switch self {
        case .breeding: return "繁育中"
        case .mating: return "配种中"
        case .pregnant: return "怀孕中"
        case .born: return "已生产"
        case .retired: return "已退役"
        }
    }

    /// 状态 → 徽章强度。**这是"状态靠填充强度表达"这条设计约定的落地点**：
    /// 进行中的用实心主色，已完成的用主色浅底，终态用中性浅底，只有需关注才给警示色。
    var tone: DSChipTone {
        switch self {
        case .breeding, .pregnant: return .current
        case .mating: return .done
        case .born: return .mid
        case .retired: return .archived
        }
    }
}

/// 繁育四阶段：配对 → 怀孕 → 生产 → 出窝
enum BreedingStage: String, Codable, CaseIterable, Identifiable {
    case mated, pregnant, birth, weaned
    var id: String { rawValue }

    var label: String {
        switch self {
        case .mated: return "配对"
        case .pregnant: return "怀孕"
        case .birth: return "生产"
        case .weaned: return "出窝"
        }
    }

    /// 已达成阶段数（1…4），用于四段进度条。
    /// 「配对」= 1 而不是 2 —— 阶段名说的是"现在停在哪一步"，
    /// 停留在配对阶段就是完成了 1 格（原来写 2 是个安静的错，会让"配对中"看起来像已经怀孕）。
    var completedCount: Int {
        switch self {
        case .mated: return 1
        case .pregnant: return 2
        case .birth: return 3
        case .weaned: return 4
        }
    }

    var tone: DSChipTone {
        switch self {
        case .mated: return .mid
        case .pregnant: return .current
        case .birth: return .mid
        case .weaned: return .archived
        }
    }
}

enum BillCategory: String, Codable, CaseIterable, Identifiable {
    case food, medical, vaccine, breeding, supplies, other
    var id: String { rawValue }

    var label: String {
        switch self {
        case .food: return "猫粮主食"
        case .medical: return "医疗健康"
        case .vaccine: return "疫苗驱虫"
        case .breeding: return "配种费用"
        case .supplies: return "用品耗材"
        case .other: return "其他支出"
        }
    }

    /// SF Symbols 映射（画布上是手绘 SVG，这里是平台等价物）
    var symbol: String {
        switch self {
        case .food: return "bag"
        case .medical: return "cross.case"
        case .vaccine: return "syringe"
        case .breeding: return "heart"
        case .supplies: return "shippingbox"
        case .other: return "ellipsis"
        }
    }
}

enum ReminderKind: String, Codable, CaseIterable {
    case vaccine, deworm, weigh, ultrasound, dueDate, weanCheck

    var label: String {
        switch self {
        case .vaccine: return "疫苗"
        case .deworm: return "驱虫"
        case .weigh: return "称重"
        case .ultrasound: return "B 超复查"
        case .dueDate: return "预产期"
        case .weanCheck: return "出窝回访"
        }
    }

    var symbol: String {
        switch self {
        case .vaccine: return "checkmark.shield"
        case .deworm: return "drop"
        case .weigh: return "scalemass"
        case .ultrasound: return "waveform.path.ecg"
        case .dueDate: return "calendar"
        case .weanCheck: return "pawprint"
        }
    }
}

/// 提醒的紧急度。**逾期是唯一允许出现警示色的一档。**
enum ReminderUrgency: String, Codable {
    case overdue, today, thisWeek

    var tone: DSChipTone { self == .overdue ? .alert : .archived }

    var groupTitle: String {
        switch self {
        case .overdue: return "已逾期"
        case .today: return "今天"
        case .thisWeek: return "本周"
        }
    }
}

// MARK: 实体

struct Cat: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var callName: String
    var gender: CatGender
    var breed: String
    var coat: String
    var birthDate: Date
    var weightKg: Double
    var status: CatStatus
    /// 头像落沙盒后**只记文件名，不存绝对路径** —— 沙盒路径在每次安装后都会变，存路径必然失效。
    var avatarFileName: String?
    /// 累计繁育胎数
    var litterCount: Int = 0

    /// 年龄文案。列表卡与详情页共用这一个纯函数，避免两处各写一份必然漂移。
    static func ageLine(birthDate: Date, now: Date = Date()) -> String {
        let months = Calendar.current.dateComponents([.month], from: birthDate, to: now).month ?? 0
        let years = months / 12
        let rest = months % 12
        if years <= 0 { return "\(max(months, 0)) 月龄" }
        return rest == 0 ? "\(years) 岁" : "\(years) 岁 \(rest) 个月"
    }

    var ageLine: String { Cat.ageLine(birthDate: birthDate) }
}

struct BreedingRecord: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var code: String                 // BR-2026-03
    var motherID: UUID
    var fatherID: UUID
    var matedDate: Date?
    var pregnantDate: Date?
    var expectedDueDate: Date?
    var birthDate: Date?
    var weanedDate: Date?
    var kittenCount: Int?
    var note: String = ""

    /// ⚠️ 阶段**由日期推导**，不是存下来的字段 —— 与 `Reminder.urgency` 同一条约定。
    ///
    /// 为什么这件事必须做对：如果把 stage 存成一个可手改的字段，它迟早会和日期打架
    /// （显示"怀孕中"却没有怀孕日期、显示"已出窝"却没有出窝日期）。
    /// 而"两个真相"的代价不是显示难看，是**用户开始不信任这个列表** ——
    /// 而繁育记录这个功能的价值，恰恰就是"我不用记，它都记着"。
    ///
    /// 推导规则就是"事实推进到哪一步"：出窝 > 生产 > 怀孕 > 配对。
    var stage: BreedingStage {
        BreedingRecord.stage(matedDate: matedDate,
                             pregnantDate: pregnantDate,
                             birthDate: birthDate,
                             weanedDate: weanedDate)
    }

    /// 阶段推导的**纯函数版本**：编辑器手上只有 @State（还没生成实例），
    /// 但也要实时显示"改完之后算什么阶段"，所以推导规则必须能脱离实例调用。
    static func stage(matedDate: Date?,
                      pregnantDate: Date?,
                      birthDate: Date?,
                      weanedDate: Date?) -> BreedingStage {
        if weanedDate != nil { return .weaned }
        if birthDate != nil { return .birth }
        if pregnantDate != nil { return .pregnant }
        return .mated
    }

    /// 列表卡与详情页共用的"进展描述"。
    /// ⚠️ 这类句子**必须做成不依赖实例的纯函数**：编辑器手上只有 @State（还没生成实例），
    /// 若两处各写一份，两份必然漂移。入参全部是原始值，两边产出逐字相同的字符串。
    ///
    /// ⚠️ `kittenCount` 也必须是**入参**，不能省（第一版就栽在这里）：
    /// static 上下文里没有实例，直接写 `if let n = kittenCount` 报
    /// `instance member 'kittenCount' cannot be used on type 'BreedingRecord'`。
    static func progressLine(stage: BreedingStage,
                             matedDate: Date?,
                             pregnantDate: Date?,
                             birthDate: Date?,
                             weanedDate: Date?,
                             kittenCount: Int?) -> String {
        let f = Formatters.monthDay
        switch stage {
        case .mated:
            if let d = matedDate { return "计划配种 \(f.string(from: d))" }
            return "待配种"
        case .pregnant:
            var parts: [String] = []
            if let d = matedDate { parts.append("配种 \(f.string(from: d))") }
            if let d = pregnantDate { parts.append("怀孕 \(f.string(from: d))") }
            return parts.joined(separator: " · ")
        case .birth:
            var parts: [String] = []
            if let d = matedDate { parts.append("配种 \(f.string(from: d))") }
            if let d = birthDate { parts.append("生产 \(f.string(from: d))") }
            if let n = kittenCount { parts.append("产仔 \(n) 只") }
            return parts.joined(separator: " · ")
        case .weaned:
            var parts: [String] = ["已出窝"]
            if let d = weanedDate { parts.append("\(f.string(from: d))") }
            if let n = kittenCount { parts.append("出窝 \(n) 只") }
            return parts.joined(separator: " · ")
        }
    }

    var progressLine: String {
        BreedingRecord.progressLine(stage: stage,
                                    matedDate: matedDate,
                                    pregnantDate: pregnantDate,
                                    birthDate: birthDate,
                                    weanedDate: weanedDate,
                                    kittenCount: kittenCount)
    }

    // MARK: 派生：这一胎走了多久

    /// 猫的孕期参考范围（天）。
    /// ⚠️ 这是**给判断的参考，不是判据** —— 猫的个体差异真实存在（59 天到 70 天都有记录）。
    /// 所以界面上只会说"偏出参考范围"，**不会报错、不会标红说用户填错了**：
    /// 拿一个写死的"正常值"去否定用户亲眼看到的事实，是最傲慢的做法。
    static let gestationReference = 58...72

    /// 配种 → 生产 的天数
    static func gestationDays(matedDate: Date?, birthDate: Date?) -> Int? {
        spanDays(from: matedDate, to: birthDate)
    }

    /// 生产 → 出窝 的天数
    static func nursingDays(birthDate: Date?, weanedDate: Date?) -> Int? {
        spanDays(from: birthDate, to: weanedDate)
    }

    /// 配种 → 出窝 的总天数
    static func totalDays(matedDate: Date?, weanedDate: Date?) -> Int? {
        spanDays(from: matedDate, to: weanedDate)
    }

    private static func spanDays(from: Date?, to: Date?) -> Int? {
        guard let from, let to else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day],
                                  from: cal.startOfDay(for: from),
                                  to: cal.startOfDay(for: to)).day
    }

    /// 一句人话："配种到生产 66 天（一般 63–65 天）"。
    /// 偏出参考范围时**只加一句说明**，不改颜色、不报警 —— 见 gestationReference 那段注释。
    static func gestationNote(matedDate: Date?, birthDate: Date?) -> String? {
        guard let days = gestationDays(matedDate: matedDate, birthDate: birthDate) else { return nil }
        if gestationReference.contains(days) { return "配种到生产 \(days) 天（一般 63–65 天）" }
        return "配种到生产 \(days) 天 —— 偏出常见范围（\(gestationReference.lowerBound)–\(gestationReference.upperBound) 天），但个体差异是存在的"
    }

    static func nursingNote(birthDate: Date?, weanedDate: Date?) -> String? {
        guard let days = nursingDays(birthDate: birthDate, weanedDate: weanedDate) else { return nil }
        return "生产到出窝 \(days) 天"
    }

    var title: String { "\(motherName) × \(fatherName)" }

    // 展示用的名字由 AppStore 在装配时注入，模型本身不持有引用，避免循环。
    var motherName: String = ""
    var fatherName: String = ""
}

struct Bill: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var category: BillCategory
    var amount: Double            // 支出记正数，展示时前面加 -
    var date: Date
    var note: String = ""
    var catIDs: [UUID] = []

    var metaLine: String {
        let f = Formatters.monthDay
        return "\(f.string(from: date)) · \(note.isEmpty ? category.label : note)"
    }
}

struct Reminder: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var kind: ReminderKind
    var title: String
    var detail: String
    var dueDate: Date
    var isDone: Bool = false
    var catID: UUID?

    /// 紧急度由截止日期推导，**不允许手工设置** —— 否则"逾期"会依赖人的记性。
    static func urgency(dueDate: Date, now: Date = Date()) -> ReminderUrgency {
        let cal = Calendar.current
        if dueDate < cal.startOfDay(for: now) { return .overdue }
        if cal.isDateInToday(dueDate) { return .today }
        return .thisWeek
    }

    var urgency: ReminderUrgency { Reminder.urgency(dueDate: dueDate) }

    /// 截止文案。首页提醒行与 09 屏提醒列表**共用这一个纯函数**。
    /// 两处各写一份的话，"逾期 1 天"和"已逾期 1 天"这种差异迟早出现。
    ///
    /// ⚠️ **今天这一档要带上时刻**：提醒是可以设具体几点几分的（如"今天 20:00 喂药"），
    /// 只写"今天到期"会让人以为"什么时候都行"，而通知其实只在那一个时刻响。
    /// 隔了几天的那几档不带时刻 —— 那时候"还有 6 天"才是用户在意的信息。
    static func dueLabel(dueDate: Date, now: Date = Date()) -> (text: String, isOverdue: Bool) {
        let cal = Calendar.current
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: now),
                                      to: cal.startOfDay(for: dueDate)).day ?? 0
        if days < 0 { return ("逾期 \(-days) 天", true) }
        if days == 0 { return ("今天 \(timeLabel(dueDate))", false) }
        if days == 1 { return ("明天 \(timeLabel(dueDate))", false) }
        return ("还有 \(days) 天", false)
    }

    /// HH:mm。给"今天/明天"这种需要精确到时刻的场合用。
    static func timeLabel(_ date: Date) -> String { Formatters.hourMinute.string(from: date) }

    var dueLabel: (text: String, isOverdue: Bool) { Reminder.dueLabel(dueDate: dueDate) }

    /// 这条提醒"已经过去了"—— 判据是**完整时刻**而不是日期。
    /// 本地通知只对未来的时刻有意义；今天 09:00 而现在已经 15:00，那个通知不会再响。
    /// （列表里它仍然算"今天"，该做的事没做还是没做。）
    static func isPast(dueDate: Date, now: Date = Date()) -> Bool { dueDate <= now }

    /// 提醒行副标题：类型 · 事项
    var subtitle: String { "\(kind.label) · \(detail)" }
}

// MARK: - 疫苗 / 驱虫记录
//
// ⚠️ 它和「提醒」**不是一件事**，别合并：
//   · 提醒是**将来**该做的事（可以有、可以改、做完了勾掉）
//   · 记录是**已经发生**的事实（打完那天记一笔，之后一直是真的）
// 而"下次什么时候做"应该是从记录**推**出来的，不是各存一份 ——
// 存两份的话，改了记录却忘了改提醒，两者就开始互相骗人。
// （同一条约定在繁育那边也用过：阶段由日期推导。）

enum HealthKind: String, Codable, CaseIterable, Identifiable {
    case vaccine
    case dewormInternal
    case dewormExternal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vaccine: return "疫苗"
        case .dewormInternal: return "内驱"
        case .dewormExternal: return "外驱"
        }
    }

    var symbol: String {
        switch self {
        case .vaccine: return "syringe"
        case .dewormInternal: return "pills"
        case .dewormExternal: return "drop"
        }
    }

    /// 参考间隔（天）。
    ///
    /// ⚠️ **这是常见做法，不是规则。** 具体要听兽医的、看药盒说明（不同产品差很多）。
    /// 所以界面上只会说「参考下次」，**不说「该做了」** ——
    /// 这个 App 没有资格替兽医下判断，说错了会让人真的耽误事。
    var referenceIntervalDays: Int {
        switch self {
        case .vaccine: return 365          // 成年猫年免
        case .dewormInternal: return 90    // 体内驱虫，常见 3 个月一次
        case .dewormExternal: return 30    // 体外驱虫，常见 1 个月一次
        }
    }

    /// 生成提醒时用哪一类（提醒那边只有"驱虫"一档，不细分内外）
    var reminderKind: ReminderKind {
        switch self {
        case .vaccine: return .vaccine
        case .dewormInternal, .dewormExternal: return .deworm
        }
    }
}

struct HealthRecord: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var catID: UUID
    var kind: HealthKind
    var date: Date
    var note: String = ""

    /// 参考下一次的日期（由类型间隔推出来，不存）
    var referenceNextDate: Date? {
        Calendar.current.date(byAdding: .day, value: kind.referenceIntervalDays, to: date)
    }

    /// 「5月12日 · 猫三联第二针」
    var title: String {
        let day = Formatters.monthDay.string(from: date)
        return note.isEmpty ? day : "\(day) · \(note)"
    }

    /// 距今天数（负数 = 还没到，用于"参考下次"）
    static func days(from: Date, to: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: from), to: cal.startOfDay(for: to)).day ?? 0
    }

    /// 「3 个月前」这类人话。**"上次是什么时候做的"就是这个功能的全部意义**，
    /// 所以这个换算必须一眼能懂，别让用户自己拿日期减。
    ///
    /// ⚠️ 分档的判据用**天**，不要用"算出来的月数"：
    /// 早先写的是 `if months < 12 { … }`，于是 **364 天**（= 12.13 个月）
    /// 会掉进年份分支，而 364/365 = 0 年、余下 12 个月 → 显示成
    /// **「0 年 12 个月前」**。这个 bug 是被"把算法移植到 Python 跑边界"抓出来的
    /// （纯文本换算，没有编译器也能验 —— 见技能里"纯算法可以脱离 Swift 验"）。
    static func agoText(_ date: Date, now: Date = Date()) -> String {
        let days = days(from: date, to: now)
        if days < 0 { return "还没到" }
        if days == 0 { return "今天" }
        if days == 1 { return "昨天" }
        if days < 30 { return "\(days) 天前" }
        if days < 365 { return "\(days / 30) 个月前" }
        let years = days / 365
        let rest = (days % 365) / 30
        return rest == 0 ? "\(years) 年前" : "\(years) 年 \(rest) 个月前"
    }

    /// 「还有 12 天」/「已过 5 天」
    static func dueText(_ date: Date, now: Date = Date()) -> String {
        let days = days(from: now, to: date)
        if days == 0 { return "就是今天" }
        if days > 0 { return "还有 \(days) 天" }
        return "已过 \(-days) 天"
    }
}

// MARK: 金额与日期格式化
//
// 金额一律走这里。展示口径必须唯一：
//   · 对外只出现支出金额，不带符号歧义
//   · 千分位 + ¥ 前缀
//   · 表格里右对齐（等宽字体）靠 DS.Typo.rowAmount 保证，不靠空格凑

enum Money {
    static func plain(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "0"
    }

    /// ¥3,280
    static func yuan(_ value: Double) -> String { "¥" + plain(value) }

    /// -¥328（账单行）
    static func signedYuan(_ value: Double) -> String { "-¥" + plain(abs(value)) }

    /// 日历格子里的那种金额：**不带 ¥、不带千分位、必要时才缩写**。
    ///
    /// 为什么要单独一个：格子只有约 50pt 宽，¥ 和逗号都是纯占用；
    /// 而缩写是**有代价的**（看不准），所以只在真的塞不下时才缩（≥1000 才用 k）。
    static func compact(_ value: Double) -> String {
        if value >= 10000 { return String(format: "%.0fk", value / 1000) }
        if value >= 1000 { return String(format: "%.1fk", value / 1000) }
        return String(format: "%.0f", value)
    }
}

enum Formatters {
    static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd"
        return f
    }()

    static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let monthTitle: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy 年 M 月"
        return f
    }()

    /// HH:mm —— 提醒的时刻。用 en_US_POSIX 保证数字形态稳定（不受地区数字系统影响）。
    static let hourMinute: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// M月d日 HH:mm —— 提醒表单里"会在什么时候提醒我"那句人话。
    static let monthDayTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f
    }()
}

extension String {
    /// 表单里最好用的一句话工具：清掉用户输入的首尾空白与换行。
    /// 为什么必须做：`"Mochi "` 和 `"Mochi"` 会被当成两只不同的猫，
    /// 而在列表里它们看起来一模一样 —— 这类"看不见的差异"是最难排查的一类数据脏。
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
