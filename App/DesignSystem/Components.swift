import SwiftUI

// MARK: - 组件层
//
// 规则：**组件里不写裸色值 / 裸字号**，全部走 DS。
// ⚠️ 注意：本文件里的类型一律不使用 `private` 存储属性。
//    原因——Swift 的逐成员初始化器只要遇到一个 private 存储属性就会降级成 private，
//    于是该组件只能在同文件里被构造；要到"第一次被别的文件引用"时才炸，且报错落在调用方。

// MARK: 卡片容器

/// 白卡 + 柔粉阴影，**无描边**。分区靠阴影和留白，不靠边框线。
struct DSCard<Content: View>: View {
    var radius: CGFloat = DS.Radius.card
    var padding: CGFloat = DS.Space.xl
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCardSurface(radius: radius)
    }
}

/// 列表行：白卡 + 行阴影，常用于「猫 / 繁育 / 账单 / 提醒」的重复条目。
struct DSListRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: DS.Space.m) { content }
            .padding(.vertical, DS.Space.m)
            .padding(.horizontal, DS.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsRowSurface()
    }
}

// MARK: 按钮

/// 主按钮：主色渐变 + 彩色投影。
struct DSPrimaryButton: View {
    let title: String
    var height: CGFloat = DS.Metrics.buttonHeight
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DS.Typo.button)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(DS.primaryGradient, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
        }
        .buttonStyle(.plain)
        .dsButtonShadow()
    }
}

/// 次级按钮：白底 + 深色字（画布上"导出成长报告"那一类）。
struct DSGhostButton: View {
    let title: String
    var height: CGFloat = DS.Metrics.buttonHeight
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DS.Typo.button)
                .foregroundStyle(DS.ink)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// 圆形图标按钮（导航栏右上角的「+」「编辑」）。
struct DSIconButton: View {
    let systemName: String
    var size: CGFloat = 36
    var filled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(filled ? .white : DS.ink)
                .frame(width: size, height: size)
                .background(
                    filled ? AnyShapeStyle(DS.primary) : AnyShapeStyle(DS.surface),
                    in: RoundedRectangle(cornerRadius: DS.Radius.iconButton, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: 状态徽章
//
// 设计约定：**状态靠「填充强度」表达，不靠颜色种类**。
// 只有逾期/需关注才允许用警示色；其余三档全是同一主色的深浅。
enum DSChipTone {
    case current    // 进行中 / 当前 —— 实心主色 + 白字
    case done       // 已完成 —— 主色浅底 + 主色字
    case mid        // 中间态（如"配对中"）—— 浅底 + 深灰字
    case archived   // 归档 / 未开始 —— 浅底 + 浅灰字
    case alert      // 逾期 / 需关注 —— 唯一保留的警示色
}

struct DSStatusChip: View {
    let text: String
    var tone: DSChipTone = .mid

    private var bg: Color {
        switch tone {
        case .current: return DS.primary
        case .done: return DS.surfaceSoft
        case .mid: return DS.surfaceSoft
        case .archived: return DS.surfaceSoft
        case .alert: return DS.alertSoft
        }
    }

    private var fg: Color {
        switch tone {
        case .current: return .white
        case .done: return DS.primary
        case .mid: return DS.inkSecondary
        case .archived: return DS.icon
        case .alert: return DS.alert
        }
    }

    var body: some View {
        Text(text)
            .font(DS.Typo.chip)
            .foregroundStyle(fg)
            .padding(.horizontal, DS.Space.s)
            .frame(height: 22)
            .background(bg, in: Capsule())
    }
}

// MARK: 图标底

/// 柔和圆角图标底（画布上提醒行 / 账单行左侧那个小方块）。
struct DSIconTile: View {
    let systemName: String
    var size: CGFloat = 36
    var tint: Color = DS.primary
    var background: Color = DS.surfaceSoft

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.5, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(background, in: RoundedRectangle(cornerRadius: size * 0.33, style: .continuous))
    }
}

/// 空状态用的大圆底（108 + 48pt 图标）。
struct DSIconOrb: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: DS.Metrics.iconOrb * 0.44, weight: .light))
            .foregroundStyle(DS.primary)
            .frame(width: DS.Metrics.iconOrb, height: DS.Metrics.iconOrb)
            .background(DS.surfaceSoft, in: Circle())
    }
}

// MARK: 导航栏

/// 屏幕大标题 + 右侧动作（tab 主页用）
struct DSScreenTitle: View {
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack {
            Text(title).font(DS.Typo.screenTitle).foregroundStyle(DS.ink)
            Spacer(minLength: DS.Space.m)
            if let trailing { trailing }
        }
        .padding(.horizontal, DS.Space.screenH)
        .padding(.top, DS.Space.xxs)
        .padding(.bottom, DS.Space.m)
    }
}

/// 二级页导航：返回 + 居中标题 + 可选右侧动作
struct DSNavBar<Trailing: View>: View {
    let title: String
    var onBack: (() -> Void)? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: DS.Space.m) {
            if let onBack {
                DSIconButton(systemName: "chevron.left", action: onBack)
            } else {
                Color.clear.frame(width: 36, height: 36)
            }
            Spacer(minLength: 0)
            Text(title).font(DS.Typo.navTitle).foregroundStyle(DS.ink)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, DS.Space.screenH)
        .padding(.top, DS.Space.xxs)
        .padding(.bottom, DS.Space.m)
    }
}

extension DSNavBar where Trailing == Color {
    init(title: String, onBack: (() -> Void)? = nil) {
        self.init(title: title, onBack: onBack) { Color.clear.frame(width: 36, height: 36) }
    }
}

// MARK: 分组标题

struct DSSectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title).font(DS.Typo.sectionTitle).foregroundStyle(DS.ink)
            Spacer(minLength: DS.Space.s)
            if let actionTitle, let onAction {
                Button(actionTitle, action: onAction)
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.primary)
                    .buttonStyle(.plain)
            }
        }
    }
}

// MARK: 数据展示

/// 首页三宫格用的统计块：大数字（等宽）+ 小标签
struct DSStatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(value)
                .font(DS.Typo.statNumber)
                .foregroundStyle(DS.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(DS.Typo.caption)
                .foregroundStyle(DS.inkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 键值行（详情页基础信息 / 表单只读值）
struct DSKeyValueRow: View {
    let key: String
    let value: String
    var valueIsNumeric: Bool = false
    var monospaced: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).font(DS.Typo.body).foregroundStyle(DS.inkSecondary)
            Spacer(minLength: DS.Space.m)
            Text(value)
                .font(monospaced ? DS.Typo.rowAmount : DS.Typo.rowTitle)
                .monospacedDigit()
                .foregroundStyle(monospaced ? DS.ink : (valueIsNumeric ? DS.ink : DS.ink))
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: 进度 / 图表

/// 繁育四阶段进度条（实心主色 = 已达成，浅轨道 = 未达成）
struct DSStageProgress: View {
    let filled: Int
    let total: Int = 4

    var body: some View {
        HStack(spacing: DS.Space.xxs) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i < filled ? DS.primary : DS.track)
                    .frame(height: 6)
            }
        }
    }
}

/// 迷你柱状图（月度支出趋势）。数值会自动归一化到可用高度。
struct DSBarChart: View {
    let values: [Double]
    var height: CGFloat = 38
    var highlightLast: Bool = true
    var accent: Color = DS.primary
    var base: Color = DS.primary.opacity(0.34)

    private var maxValue: Double { max(values.max() ?? 1, 0.0001) }

    var body: some View {
        HStack(alignment: .bottom, spacing: DS.Space.xxs) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, v in
                let isPeak = highlightLast && index == values.count - 1
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isPeak ? accent : base)
                    .frame(height: max(4, height * CGFloat(v / maxValue)))
            }
        }
        .frame(height: height, alignment: .bottom)
    }
}

// MARK: 表单

struct DSSearchField: View {
    var placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DS.inkTertiary)
            TextField(placeholder, text: $text)
                .font(DS.Typo.body)
                .foregroundStyle(DS.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, DS.Space.l)
        .frame(height: DS.Metrics.inputHeight)
        .background(DS.input, in: RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous))
    }
}

/// 分段选择（性别、种猫/幼猫那种）。激活态用实心主色。
struct DSSegmented<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: DS.Space.xxs) {
            ForEach(options, id: \.value) { option in
                let active = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.system(size: 13, weight: active ? .semibold : .medium))
                        .foregroundStyle(active ? .white : DS.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            active ? AnyShapeStyle(DS.primary) : AnyShapeStyle(Color.clear),
                            in: RoundedRectangle(cornerRadius: DS.Radius.iconButton, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DS.Space.xxs)
        .background(DS.surfaceSoft, in: RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
    }
}

// MARK: 空状态 / 骨架屏

/// 空状态。**每个空状态的 CTA 都要有明确落点**，尤其是"搜索无结果"——
/// 不能只让用户退回去，必须给"新增"的出口。
struct DSEmptyState<Actions: View>: View {
    let systemName: String
    let title: String
    let message: String
    var hint: String? = nil
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: DS.Space.l) {
            DSIconOrb(systemName: systemName)
            Text(title).font(DS.Typo.emptyTitle).foregroundStyle(DS.ink)
            Text(message)
                .font(DS.Typo.caption)
                .foregroundStyle(DS.inkTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            actions
            if let hint {
                Text(hint).font(.system(size: 11)).foregroundStyle(DS.inkFaint)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DS.Space.xxl * 2)
    }
}

extension DSEmptyState where Actions == EmptyView {
    init(systemName: String, title: String, message: String, hint: String? = nil) {
        self.init(systemName: systemName, title: title, message: message, hint: hint) { EmptyView() }
    }
}

/// 骨架屏占位块。
/// 用"形状"而不是"加载中…"四个字——形状能让用户预判接下来会出现什么，等待感更低。
struct DSSkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12
    var corner: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(DS.track)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

/// 列表骨架卡：形状与真实行一一对应（头像块 / 两行 / 徽章块）。
struct DSSkeletonRow: View {
    var avatarSize: CGFloat = 56
    var line1Width: CGFloat = 132
    var line2Width: CGFloat = 196

    var body: some View {
        HStack(spacing: DS.Space.m) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DS.track)
                .frame(width: avatarSize, height: avatarSize)
            VStack(alignment: .leading, spacing: 9) {
                DSSkeletonBlock(width: line1Width, height: 12)
                DSSkeletonBlock(width: line2Width, height: 10, corner: 5)
            }
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(DS.track)
                .frame(width: 54, height: 22)
        }
        .padding(.vertical, DS.Space.m)
        .padding(.horizontal, DS.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsRowSurface()
    }
}

// MARK: 底部导航
//
// 设计稿用的是**自绘胶囊导航**，不是系统 TabView —— 所以这里手写。
// 激活态是实心主色胶囊 + 白色图标文字，全场对比最强的一处。

struct DSTabItem: Identifiable {
    let id: String
    let systemName: String
    let title: String
}

struct DSTabBar: View {
    let items: [DSTabItem]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let active = item.id == selection
                Button {
                    selection = item.id
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.systemName)
                            .font(.system(size: 19, weight: .regular))
                            .foregroundStyle(active ? .white : DS.icon)
                        Text(item.title)
                            .font(.system(size: 10, weight: active ? .semibold : .medium))
                            .foregroundStyle(active ? .white : DS.icon)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        active ? AnyShapeStyle(DS.primary) : AnyShapeStyle(Color.clear),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DS.Space.xxs)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, DS.Space.xxl)
        .padding(.top, DS.Space.m)
        .padding(.bottom, DS.Space.xxl)
    }
}
