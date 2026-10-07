import SwiftUI

// MARK: - 设计令牌（唯一真值来源）
//
// 对应画布：`Elese的猫舍 - iOS App` v8（奶油粉紫 · INS 风）
// 规则：**任何界面文件里不得出现裸色值 / 裸字号**。要改视觉，只改这个文件。

enum DS {

    // MARK: 颜色

    /// 屏底色 · 奶油粉白
    static let bg = Color(hex: 0xFAF1F5)
    /// 卡片面 · 纯白（配柔粉阴影，不用描边）
    static let surface = Color(hex: 0xFFFFFF)
    /// 主色浅底 / chip 底 / 图标底
    static let surfaceSoft = Color(hex: 0xF6E4F0)
    /// 输入框底
    static let input = Color(hex: 0xF7ECF2)
    /// 进度条与图表轨道
    static let track = Color(hex: 0xF0E2EE)

    /// 主色 · 柔紫（按钮 / 激活态 / 进度 / 关键数字 / 链接）
    static let primary = Color(hex: 0xB57EDC)
    /// 主色深一档（渐变末端 / 次级强调）
    static let primaryDeep = Color(hex: 0xA96BD0)
    /// 主色浅一档（渐变起点）
    static let primaryLight = Color(hex: 0xC79BE8)

    /// 大标题 · 暖紫黑
    static let ink = Color(hex: 0x3A2E3F)
    /// 次级文字
    static let inkSecondary = Color(hex: 0x5B6167)
    /// 三级文字 / 说明
    static let inkTertiary = Color(hex: 0x9A8DA0)
    /// 更浅的兜底提示
    static let inkFaint = Color(hex: 0xC3B6C9)
    /// 图标灰（未激活）
    static let icon = Color(hex: 0x9A8DA0)

    /// 唯一警示色（逾期 / 需关注）
    static let alert = Color(hex: 0xD9736B)
    static let alertSoft = Color(hex: 0xFBE4E2)

    /// 数据条 / 图表阶梯（深 → 浅）
    static let ramp: [Color] = [
        Color(hex: 0xB57EDC), Color(hex: 0xCFA9E4),
        Color(hex: 0xDCC2EF), Color(hex: 0xEFE0F8),
    ]

    /// 记账分类配搭色。**只允许用在这里**——它们是"携带信息"的，不是装饰。
    enum CategoryTint {
        static let food = Color(hex: 0xB57EDC)      // 猫粮主食
        static let medical = Color(hex: 0x7FB8C9)   // 医疗健康（青）
        static let breeding = Color(hex: 0xE39BC8)  // 配种费用（玫红）
        static let supplies = Color(hex: 0xD9B08C)  // 用品耗材（砂金）
        static let other = Color(hex: 0x9A8DA0)     // 其他
    }

    /// 大 CTA 渐变（画布 45°）
    static let primaryGradient = LinearGradient(
        colors: [primaryLight, primaryDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: 字体
    //
    // 平台差异（重要，改了要同步文档）：
    //   画布中文用 Noto Sans SC → **iOS 直接用系统字体（苹方）**。
    //   捆绑 Noto Sans SC 三个字重约 +15MB 包体，换来的是一套略逊于系统的中文，不划算。
    //   画布关键数字用 Noto Sans Mono → **iOS 用 SF Mono（.monospaced）**，同样不用捆字体。
    //   ⚠️ 凡是"会变化的数字"（时刻、计数），即使不用等宽设计也必须加 .monospacedDigit()，
    //      否则数字一变宽，整行都在跳。

    enum Typo {
        /// 屏幕大标题（22 / Bold）
        static let screenTitle = Font.system(size: 22, weight: .bold)
        /// 导航标题（17 / Semibold）
        static let navTitle = Font.system(size: 17, weight: .semibold)
        /// 卡片标题（14 / Semibold）
        static let cardTitle = Font.system(size: 14, weight: .semibold)
        /// 条目主文字（13 / Medium）
        static let rowTitle = Font.system(size: 13, weight: .medium)
        /// 正文（13 / Regular）
        static let body = Font.system(size: 13, weight: .regular)
        /// 说明 / 元信息（10 / Regular）
        static let caption = Font.system(size: 10, weight: .regular)
        /// 小标题、分组名（13 / Semibold）
        static let sectionTitle = Font.system(size: 13, weight: .semibold)
        /// chip 文字（10 / Semibold）
        static let chip = Font.system(size: 10, weight: .semibold)
        /// 按钮文字（15 / Semibold）
        static let button = Font.system(size: 15, weight: .semibold)
        /// 空状态标题（17 / Semibold）
        static let emptyTitle = Font.system(size: 17, weight: .semibold)

        /// 关键数字 · 统计值（24 / Bold / 等宽）
        static let statNumber = Font.system(size: 24, weight: .bold, design: .monospaced)
        /// 关键数字 · 主金额（32 / Bold / 等宽）
        static let heroAmount = Font.system(size: 32, weight: .bold, design: .monospaced)
        /// 关键数字 · 条目金额（13 / Semibold / 等宽）
        static let rowAmount = Font.system(size: 13, weight: .semibold, design: .monospaced)
        /// 会变化但不需要等宽设计的数字（如"3 次/日"里的数字）
        static func numeric(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight).monospacedDigit()
        }
    }

    // MARK: 圆角

    enum Radius {
        static let input: CGFloat = 12
        static let iconButton: CGFloat = 12
        static let button: CGFloat = 16
        static let row: CGFloat = 16
        static let card: CGFloat = 18
        static let cardLarge: CGFloat = 20
        /// 胶囊（chip / 状态徽章）统一用 Capsule()，这里只留语义名
        static let capsule: CGFloat = 999
    }

    // MARK: 间距

    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 14
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 20
        /// 屏幕左右安全边距
        static let screenH: CGFloat = 20
    }

    // MARK: 阴影
    //
    // ⚠️ CSS 与 SwiftUI 不是一一对应，别直译：
    //   · shadowRadius ≈ CSS blur 的**一半**（所以画布 blur 18 → 这里 9）
    //   · CSS 的 spread 在 SwiftUI **没有对应值**（画布是 -6）→ 阴影实际会偏大偏软，
    //     因此把不透明度从画布的 0.13 下调到 0.10 做视觉补偿
    //   · offset.y 可以照搬
    //   结论：这里的数值不是画布数值的转抄，是**换算后的落地值**。改动前先看截图。

    struct ShadowSpec {
        let y: CGFloat
        let radius: CGFloat
        let opacity: Double
    }

    enum Elev {
        /// 列表行 / 小卡
        static let row = ShadowSpec(y: 6, radius: 9, opacity: 0.10)
        /// 大卡 / 数据卡
        static let card = ShadowSpec(y: 8, radius: 11, opacity: 0.12)
        /// 主按钮的彩色投影
        static let button = ShadowSpec(y: 8, radius: 9, opacity: 0.30)
    }

    // MARK: 布局常量

    enum Metrics {
        static let screenWidth: CGFloat = 390
        static let screenHeight: CGFloat = 844
        static let statusBarHeight: CGFloat = 62
        static let navHeight: CGFloat = 56
        static let tabBarHeight: CGFloat = 95
        static let buttonHeight: CGFloat = 48
        static let largeButtonHeight: CGFloat = 50
        static let inputHeight: CGFloat = 44
        /// 空状态图标圆底
        static let iconOrb: CGFloat = 108
    }
}

// MARK: - 颜色十六进制构造

extension Color {
    /// 用 0xRRGGBB 构造。设计令牌全部走这个入口，避免散落的裸色值。
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - 阴影修饰器

private struct DSShadow: ViewModifier {
    let spec: DS.ShadowSpec
    let color: Color

    func body(content: Content) -> some View {
        content.shadow(
            color: color.opacity(spec.opacity),
            radius: spec.radius,
            x: 0,
            y: spec.y
        )
    }
}

extension View {
    /// 画布上的"卡片/行"阴影。**柔和粉阴影，不是灰阴影**——
    /// 白卡配灰阴影会显脏，这是这套 INS 风的关键。
    func dsRowSurface() -> some View {
        self
            .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous))
            .modifier(DSShadow(spec: DS.Elev.row, color: Color(hex: 0xBF8CAD)))
    }

    func dsCardSurface(radius: CGFloat = DS.Radius.card) -> some View {
        self
            .background(DS.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .modifier(DSShadow(spec: DS.Elev.card, color: Color(hex: 0xBF8CAD)))
    }

    /// 主按钮的彩色投影
    func dsButtonShadow() -> some View {
        modifier(DSShadow(spec: DS.Elev.button, color: DS.primary))
    }
}
