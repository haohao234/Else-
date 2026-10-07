# Elese的猫舍 · iOS 起步骨架

> **⚠️ 这份代码没有编译过。**
> 生成它的机器上没有 Xcode。下面「怎么低成本编译」一节给了三条路，请先让它编译起来再继续加功能。
>
> **但"没编译过"不等于"不知道哪里可能错"** —— 只有编译器能裁决的问题一共三类，已逐条列在
> `编译预检清单.md` 里，并各给了两种修法。静态层面能拦的那几类已经拦过了（见下）。

---

## 一句话结论

这是一份**让工程师能立刻起步、并且能被云端编译**的骨架，不是成品 App。
阶段一交付了「令牌层 + 组件层 + 模型层 + 工程声明 + CI」，主流程屏与二级页在阶段二补齐。

---

## 设计来源

- 画布：`Elese的猫舍 - iOS App`，定稿 v8（15 屏：10 个业务屏 + 5 个状态屏）
- 交付件：`Elese的猫舍 - iOS App 设计稿 v8（15屏·含空状态与加载态）.pdf`
- 可点击原型：`Elese的猫舍 - 可点击原型.html`
- 视觉：**奶油粉紫 · INS 风**。主色 `#B57EDC`，屏底 `#FAF1F5`，白卡 + **柔粉阴影**（不是灰阴影）

---

## 目录结构

```
EleseApp/
├── project.yml                     工程真相（不是 .xcodeproj）
├── App/
│   ├── Info.plist                  手写，每个键都带"漏了会怎样"的注释
│   ├── EleseCattery.entitlements   故意是空的（不需要 App Group）
│   ├── EleseCatteryApp.swift       @main 入口
│   ├── DesignSystem/
│   │   ├── Tokens.swift            ★ 唯一真值来源：颜色 / 字体 / 圆角 / 间距 / 阴影 / 布局常量
│   │   └── Components.swift        ★ 组件层：卡片 / 按钮 / 徽章 / 导航 / 图表 / 空状态 / 骨架 / 底部导航
│   ├── Models/
│   │   ├── Models.swift            实体 + 枚举 + 展示文案纯函数 + 金额格式化
│   │   └── AppStore.swift          本地 JSON 存储 + 示例数据（内容与设计稿一致）
│   └── Features/
│       ├── RootTabView.swift       自绘胶囊底部导航 + 4 个 tab
│       └── HomeView.swift          01 首页（用满组件层，用来验证令牌够不够用）
├── tools/check_swift.mjs           静态结构校验（node，无依赖）
└── .github/workflows/ios-build.yml 云端编译（macOS runner）
```

**依赖方向（不许往回指）**：`Features → DesignSystem / Models`。令牌层不 import 任何业务文件。

---

## 怎么生成工程并编译

### 有 Mac
```bash
brew install xcodegen
xcodegen generate          # 生成 EleseCattery.xcodeproj
open EleseCattery.xcodeproj
```

### 没有 Mac（推荐先走这条）
仓库自带 `.github/workflows/ios-build.yml`，**推到 GitHub 就能拿到编译器结论**：
Actions → iOS build → Run workflow。约 3–5 分钟。
它的产出是「错误 / 警告清单」，不是能装的包（见下）。

### 先跑静态校验（1 秒，零依赖）
```bash
node tools/check_swift.mjs
```

---

## 为什么工程是 `project.yml` 而不是 `.xcodeproj`

1. **它把"最容易漏的手工操作"变成结构化声明。** 建 target 时最容易漏的三件事
   （Info.plist 键、entitlements、bundle id 前缀）漏了都**不报错**，只是功能悄悄不全。
2. `.xcodeproj` 是 UUID 的 XML，两人改必冲突，diff 出来看不懂。
3. `xcodegen` 只读 YAML、写工程，**不碰 Apple SDK —— 所以在 Windows 上也能跑**。
4. `.xcodeproj` 已加进 `.gitignore`，真相只留在 YAML 里。

---

## 令牌落地要点（改视觉只改 Tokens.swift）

| 设计稿 | iOS 落地 | 为什么 |
|---|---|---|
| 中文 `Noto Sans SC` | **系统字体**（苹方） | 捆绑三个字重约 +15MB 包体，换来的是一套略逊于系统的中文 |
| 关键数字 `Noto Sans Mono` | **SF Mono**（`.system(design: .monospaced)`） | 同一个理由：系统自带 |
| 会变化的数字 | 一律加 `.monospacedDigit()` | 否则时刻/计数一变宽，整行都在跳 |
| 卡片阴影 `blur 18 / spread -6 / 13%` | **`radius 9 / y 6 / 10%`** | SwiftUI 没有 spread；`shadowRadius ≈ CSS blur 的一半`。**这不是转抄，是换算**，改前先看截图 |
| 手绘 SVG 图标 | SF Symbols（对照表见下） | 自动跟随字号字重、矢量不用切图 |

### 图标映射

| 设计稿位置 | SF Symbol |
|---|---|
| 底部导航 首页 / 种猫 / 繁育 / 记账 / 更多 | `house` / `cat` / `heart` / `creditcard` / `square.grid.2x2` |
| 首页通知铃 | `bell` |
| 记账分类 猫粮 / 医疗 / 疫苗 / 配种 / 用品 / 其他 | `bag` / `cross.case` / `syringe` / `heart` / `shippingbox` / `ellipsis` |
| 提醒类型 疫苗 / 驱虫 / 称重 / B 超 / 预产期 / 出窝 | `checkmark.shield` / `drop` / `scalemass` / `waveform.path.ecg` / `calendar` / `pawprint` |
| 设置 · 本地备份 | `externaldrive` |
| 搜索 / 返回 / 更多 / 编辑 / 相机 | `magnifyingglass` / `chevron.left` / `ellipsis` / `pencil` / `camera` |

---

## 平台差异与限制（已改变设计或需要特别处理的）

| 能力 | 现状 | 限制 / 必须注意 |
|---|---|---|
| 本地通知 | 阶段二实现 | **权限一辈子只问一次**。被拒后只能引导去系统设置 → 所以「权限被拒」要当成一个**状态**设计，不是错误 |
| 相册选头像 | 用 `PhotosPicker` | **不需要完整相册权限**（系统面板，选哪张给哪张）。图片落沙盒后**只记文件名，不存路径**——沙盒路径每次安装都会变 |
| 「每天自动备份」 | 阶段二用「**启动时补做**」 | `BGTaskScheduler` **不保证按时执行**。所以实现是"上次备份超过 24h 就在下次打开时顺便做"，不能依赖它准点跑 |
| 导出 CSV / Excel | 落 Documents + `ShareLink` | `UIFileSharingEnabled` 已开，用户在「文件」App 里能自己删 |
| 数据存放 | Application Support 单个 JSON | **数据库不进 Documents**，避免用户从文件 App 误删 |
| 云同步 | **已从设计中删除** | 产品承诺"数据不出本机"。这条一旦破例就回不去了 —— 不引任何网络依赖（包括埋点） |
| App Group / 扩展 | **不需要** | 没有自定义通知 UI 就不需要 Notification Content Extension，也就绕开了免费 Apple ID 侧载的最大拦路虎 |
| 深色模式 | **强制浅色** | 设计只有浅色一套，且主色在深底上会过曝。要做深色必须整套重做文字层级，不是反色 |

---

## 静态校验已经覆盖到的

`node tools/check_swift.mjs` 会拦这几类（都是**实测真炸过**的）：

1. 括号配平
2. 顶层类型重名
3. **框架 import 漏项**（反查表：用到某 API 却没 import 对应库 —— `UNNotificationContentExtension` 属于 `UserNotificationsUI` 而不是 `UserNotifications`，这一族真在云端炸过两次）
4. **struct 有 private 存储属性却又需要外部传参构造**（逐成员初始化器会降级成 private，只能在同文件构造；报错落在调用方）
5. **构造调用的实参顺序不是存储属性声明顺序的子序列**（Swift 的逐成员初始化器参数顺序 = 声明顺序；实测这一条省下过一整轮云端编译）
6. 关键令牌是否落地 + **旧版配色是否回流**

> 写这个脚本时自己踩了两个坑，都写在脚本头部注释里：
> ① 计算属性不是存储属性（行尾/行内含 `{` 的一律跳过）；
> ② 取实参标签必须按**括号深度为 0** 取，否则嵌套调用里的 `day:` 和三元里的 `.alert :` 会被当成顶层标签，报一片假错。
> **判据：校验脚本自己也会误报 —— 先怀疑脚本，再怀疑代码。**

---

## 还差什么

**第一件该做的不是补屏，是先让它编译起来。** 然后：

- **阶段二（补主流程）**：种猫列表/详情/新增、繁育列表/详情、记账列表/记一笔、提醒页、设置页（本地备份 + 导出）
- **阶段二（补状态）**：5 个状态屏接入（空状态已有 `DSEmptyState`，骨架屏已有 `DSSkeletonRow`）
- **阶段二（服务层）**：通知调度、导出、备份/恢复
- **后补**：App 图标资源目录（本轮不带任何资源）、真机验收通道（见 `编译预检清单.md`）

### 已知的偏离设计之处

| 位置 | 设计稿 | 骨架里 | 原因 |
|---|---|---|---|
| 首页"今日提醒"条数 | 静态文案「全部 3 条」 | `全部 \(openReminders.count) 条` | 真实数据驱动，避免写死 |
| 空状态提示语 | 固定文案 | 参数化（`hint:`） | 一个组件覆盖 4 个空状态 |
| 卡片阴影 | blur18 / spread-6 / 13% | radius9 / y6 / 10% | SwiftUI 无 spread，见上表 |
| 「更多」tab | 设置页 | 阶段二前是占位视图 | 阶段一目标是"能编译"，不是"功能全" |
