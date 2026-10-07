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

    /// 已达成阶段数（1…4），用于四段进度条
    var completedCount: Int {
        switch self {
        case .mated: return 2       // 配对已完成，正在怀孕
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
    var stage: BreedingStage
    var matedDate: Date?
    var pregnantDate: Date?
    var expectedDueDate: Date?
    var birthDate: Date?
    var weanedDate: Date?
    var kittenCount: Int?
    var note: String = ""

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
    static func dueLabel(dueDate: Date, now: Date = Date()) -> (text: String, isOverdue: Bool) {
        let cal = Calendar.current
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: now),
                                      to: cal.startOfDay(for: dueDate)).day ?? 0
        if days < 0 { return ("逾期 \(-days) 天", true) }
        if days == 0 { return ("今天到期", false) }
        if days == 1 { return ("明天到期", false) }
        return ("还有 \(days) 天", false)
    }

    var dueLabel: (text: String, isOverdue: Bool) { Reminder.dueLabel(dueDate: dueDate) }

    /// 提醒行副标题：类型 · 事项
    var subtitle: String { "\(kind.label) · \(detail)" }
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
}
