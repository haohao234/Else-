import SwiftUI
import UIKit

// MARK: - 组件层 · 阶段二新增
//
// 与 Components.swift 同一套约定，改之前先看那边的头部注释：
//   · 组件里不写裸色值 / 裸字号，全部走 DS
//   · **不使用 private 存储属性** —— 逐成员初始化器会因此降级成 private，
//     于是组件只能在同文件里被构造，而报错会落在调用方（最难查的那种）

// MARK: 头像

/// 种猫头像块：**有照片就显示照片，没有就用「首字 + 柔和底」**。
///
/// 为什么一定要有兜底样式：猫舍里总有几只还没拍照的猫，
/// 缺图不该让列表看起来像坏了 —— 那是"数据没填"的视觉表达，不是错误。
///
/// 组件本身**不认识 AppStore**（照片从外面传进来）：这样它既能被列表用、
/// 也能被编辑页用（编辑页显示的是"还没保存的草稿照片"），而不用为了预览去动数据库。
struct DSCatAvatar: View {
    let name: String
    var image: UIImage? = nil
    var size: CGFloat = 56

    private var initial: String { name.isEmpty ? "?" : String(name.prefix(1)) }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(DS.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DS.surfaceSoft)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
    }
}

// MARK: 表单行

/// 表单文本行：左标签 + 输入框。整行在一张白卡里，行与行之间用间距分开（不用分割线）。
struct DSTextFieldRow: View {
    let label: String
    var placeholder: String = ""
    @Binding var text: String

    var body: some View {
        HStack(spacing: DS.Space.m) {
            Text(label)
                .font(DS.Typo.body)
                .foregroundStyle(DS.inkSecondary)
                .frame(width: 64, alignment: .leading)
            TextField(placeholder, text: $text)
                .font(DS.Typo.rowTitle)
                .foregroundStyle(DS.ink)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, DS.Space.l)
        .frame(height: DS.Metrics.inputHeight)
        .background(DS.input, in: RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous))
    }
}

/// 表单数字行（体重、金额这类）。用 decimalPad，避免用户敲出键盘上没有的字符。
struct DSDigitFieldRow: View {
    let label: String
    var unit: String? = nil
    @Binding var text: String

    var body: some View {
        HStack(spacing: DS.Space.m) {
            Text(label)
                .font(DS.Typo.body)
                .foregroundStyle(DS.inkSecondary)
                .frame(width: 64, alignment: .leading)
            TextField("0", text: $text)
                .font(DS.Typo.rowAmount)
                .foregroundStyle(DS.ink)
                .keyboardType(.decimalPad)
            if let unit {
                Text(unit)
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.inkTertiary)
            }
        }
        .padding(.horizontal, DS.Space.l)
        .frame(height: DS.Metrics.inputHeight)
        .background(DS.input, in: RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous))
    }
}

/// 表单日期行。日期在右，点开是系统日历 —— 不自己写日历控件。
struct DSDateRow: View {
    let label: String
    @Binding var date: Date

    var body: some View {
        HStack(spacing: DS.Space.m) {
            Text(label)
                .font(DS.Typo.body)
                .foregroundStyle(DS.inkSecondary)
                .frame(width: 64, alignment: .leading)
            Spacer(minLength: 0)
            DatePicker("", selection: $date, displayedComponents: .date)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "zh_CN"))
        }
        .padding(.horizontal, DS.Space.l)
        .frame(height: DS.Metrics.inputHeight)
        .background(DS.input, in: RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous))
    }
}

/// 可选日期行（"还没有这个时间点"是常态：预产期未定、还没出窝）。
/// 开关关掉 = 存 nil。用 nil 而不是"占位日期"，因为占位日期会污染计算。
struct DSOptionalDateRow: View {
    let label: String
    @Binding var date: Date?
    var defaultDate: Date = Date()

    var body: some View {
        VStack(spacing: DS.Space.s) {
            HStack(spacing: DS.Space.m) {
                Text(label)
                    .font(DS.Typo.body)
                    .foregroundStyle(DS.inkSecondary)
                    .frame(width: 64, alignment: .leading)
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(
                    get: { date != nil },
                    set: { on in date = on ? defaultDate : nil }
                ))
                .labelsHidden()
                .tint(DS.primary)
            }
            if let d = date {
                HStack(spacing: DS.Space.m) {
                    Spacer(minLength: 0)
                    DatePicker("", selection: Binding(
                        get: { d },
                        set: { date = $0 }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                }
            }
        }
        .padding(.horizontal, DS.Space.l)
        .padding(.vertical, DS.Space.s)
        .background(DS.input, in: RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous))
    }
}

/// 表单备注行（多行）。
struct DSNotesField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .font(DS.Typo.body)
            .foregroundStyle(DS.ink)
            .lineLimit(3...6)
            .padding(DS.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.input, in: RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous))
    }
}

// MARK: 设置 / 列表里的行

/// 可点行：图标底 + 标题 + 说明 + 右侧值/箭头。
/// 用于设置页与详情页里"跳去别处"或"执行一个动作"的条目。
struct DSActionRow: View {
    let systemName: String
    let title: String
    var subtitle: String? = nil
    var detail: String? = nil
    var isDestructive: Bool = false
    var showsChevron: Bool = true
    var action: () -> Void

    private var titleColor: Color { isDestructive ? DS.alert : DS.ink }
    private var tileTint: Color { isDestructive ? DS.alert : DS.primary }
    private var tileBG: Color { isDestructive ? DS.alertSoft : DS.surfaceSoft }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.m) {
                DSIconTile(systemName: systemName, tint: tileTint, background: tileBG)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(title).font(DS.Typo.rowTitle).foregroundStyle(titleColor)
                    if let subtitle {
                        Text(subtitle).font(DS.Typo.caption).foregroundStyle(DS.inkTertiary)
                    }
                }
                Spacer(minLength: DS.Space.s)
                if let detail {
                    Text(detail).font(DS.Typo.caption).foregroundStyle(DS.inkTertiary)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.inkFaint)
                }
            }
            .padding(.vertical, DS.Space.m)
            .padding(.horizontal, DS.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsRowSurface()
        }
        .buttonStyle(.plain)
    }
}

/// 主按钮的「跳转」版本。
/// 为什么必须有它：`DSPrimaryButton` 收的是 action 闭包，没法做导航；
/// 而空状态里的主 CTA 大多要"跳到新增页"——用 `NavigationLink` 才是对的做法
/// （`navigationDestination` 需要值路由，用 action + state 手动 push 会绕过它）。
struct DSPrimaryLink: View {
    let title: String
    let route: AppRoute
    var height: CGFloat = DS.Metrics.buttonHeight

    var body: some View {
        NavigationLink(value: route) {
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

/// 下拉选择行：左标签 + 右侧当前值 + 上下箭头。
/// 选项少、且需要"看到当前值"的场合用它（比 Picker 的滚轮省地方，也比 segmented 装得下更多项）。
struct DSMenuRow<T: Hashable>: View {
    let label: String
    let options: [(value: T, label: String)]
    @Binding var selection: T
    var placeholder: String? = nil

    private var currentLabel: String {
        if let hit = options.first(where: { $0.value == selection }) { return hit.label }
        return placeholder ?? "未选择"
    }

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                }
            }
        } label: {
            HStack(spacing: DS.Space.m) {
                Text(label)
                    .font(DS.Typo.body)
                    .foregroundStyle(DS.inkSecondary)
                    .frame(width: 64, alignment: .leading)
                Spacer(minLength: 0)
                Text(currentLabel)
                    .font(DS.Typo.rowTitle)
                    .foregroundStyle(DS.ink)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.inkFaint)
            }
            .padding(.horizontal, DS.Space.l)
            .frame(height: DS.Metrics.inputHeight)
            .background(DS.input, in: RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous))
        }
    }
}

// MARK: 记账

/// 金额输入：¥ 符号固定在前，数字大号等宽。
/// 用 String 绑定而不是 Double 绑定 —— 用户敲到一半的 "12." 不该被解析，
/// 也不该在输入过程中被格式化（边打边加千分位是最招人烦的交互之一）。
struct DSMoneyField: View {
    @Binding var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
            Text("¥")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(DS.primary)
            TextField("0", text: $text)
                .font(DS.Typo.heroAmount)
                .foregroundStyle(DS.ink)
                .keyboardType(.decimalPad)
        }
        .padding(.horizontal, DS.Space.xl)
        .frame(height: 78)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.cardLarge, style: .continuous))
    }
}

/// 分类选择网格：每个分类一个带配搭色圆点的胶囊。
/// 配搭色是**携带信息**的（和分类占比图例一一对应），不是装饰 —— 这是唯一允许用它的地方。
struct DSCategoryGrid: View {
    @Binding var selection: BillCategory

    // ⚠️ 不加 private：本项目已确认"逐成员初始化器遇到 private 存储属性会降级"，
    // 而它需要被 BillEditView 在别的文件里构造。组件层统一不用 private 存储属性。
    let columns = [
        GridItem(.flexible(), spacing: DS.Space.s),
        GridItem(.flexible(), spacing: DS.Space.s),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: DS.Space.s) {
            ForEach(BillCategory.allCases) { category in
                let active = category == selection
                Button {
                    selection = category
                } label: {
                    HStack(spacing: DS.Space.s) {
                        Circle()
                            .fill(DS.CategoryTint.color(for: category))
                            .frame(width: 8, height: 8)
                        Text(category.label)
                            .font(.system(size: 12, weight: active ? .semibold : .regular))
                            .foregroundStyle(active ? .white : DS.inkSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, DS.Space.m)
                    .frame(height: 38)
                    .background(
                        active ? AnyShapeStyle(DS.primary) : AnyShapeStyle(DS.surface),
                        in: RoundedRectangle(cornerRadius: DS.Radius.iconButton, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 月份切换（记账页顶部）：「‹ 2026 年 10 月 ›」。
/// 不用系统 DatePicker 选月份 —— 那是"挑一个具体日子"，而这里要的是"翻月份"。
struct DSMonthSwitcher: View {
    let title: String
    let onPrev: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.m) {
            DSIconButton(systemName: "chevron.left", size: 30, action: onPrev)
            Spacer(minLength: DS.Space.s)
            Text(title)
                .font(DS.Typo.cardTitle)
                .foregroundStyle(DS.ink)
                .monospacedDigit()
            Spacer(minLength: DS.Space.s)
            DSIconButton(systemName: "chevron.right", size: 30, action: onNext)
        }
    }
}
